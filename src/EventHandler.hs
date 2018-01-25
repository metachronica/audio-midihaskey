{-# LANGUAGE UnicodeSyntax #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE ViewPatterns #-}

-- A module that transforms some events such as key press/release to MIDI events.
-- It also stores some application state such as current base note, current channel, etc., and
-- handles changes of this state and provides API to get current state.
module EventHandler
     ( runEventHandler
     , EventToHandle (..)
     , EventHandlerInterface (..)
     , AppState (..)
     ) where

import Prelude hiding (lookup)
import Prelude.Unicode

import Data.IORef
import Data.HashMap.Strict

import Control.Monad
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)

import Sound.MIDI.Message.Channel
import Sound.MIDI.Message.Channel.Voice (normalVelocity)

-- local
import Utils
import Keys.Types
import Keys.Specific.EventHandler
import MIDIPlayer


type EventHandlerBus    = MVar EventToHandle
type EventHandlerSender = EventToHandle → IO ()

data EventToHandle
  = KeyPress   RowKey
  | KeyRelease RowKey

  | NewBasePitch Pitch
  | NewChannel   Channel
  | NewVelocity  Velocity

  | PanicEvent

  deriving (Show, Eq)

data EventHandlerInterface
  = EventHandlerInterface
  { handleEvent ∷ EventHandlerSender
  , getAppState ∷ IO AppState
  }

data AppState
  = AppState
  { baseKey   ∷ RowKey
  , basePitch ∷ Pitch
  , channel   ∷ Channel
  , velocity  ∷ Velocity
  , pitchMap  ∷ HashMap RowKey Pitch
  } deriving (Show, Eq)


defaultAppState ∷ AppState
defaultAppState =

  AppState { baseKey   = baseKey'
           , basePitch = basePitch'
           , channel   = toChannel 0
           , velocity  = normalVelocity
           , pitchMap  = getPitchMapping baseKey' basePitch'
           }

  where baseKey'   = AKey
        basePitch' = toPitch 19 -- 20th in [1..128]


runEventHandler ∷ MIDIPlayerSender → IO EventHandlerInterface
runEventHandler sendToMP = do
  (bus ∷ EventHandlerBus) ← newEmptyMVar

  (appStateRef ∷ IORef AppState) ← newIORef defaultAppState

  let interface
        = EventHandlerInterface
        { handleEvent = putMVar bus
        , getAppState = readIORef appStateRef
        }

      handle (KeyPress k) = do
        appState ← readIORef appStateRef
        case lookup k $ pitchMap appState of
             Just x  → sendToMP $ NoteOn (channel appState) x $ velocity appState
             Nothing → pure ()

      handle (KeyRelease k) = do
        appState ← readIORef appStateRef
        case lookup k $ pitchMap appState of
             Just x  → sendToMP $ NoteOff (channel appState) x $ velocity appState
             Nothing → pure ()

      handle (NewBasePitch p) = modifyIORef appStateRef $ updateState $ \s → s { basePitch = p }
      handle (NewChannel c)   = modifyIORef appStateRef $ updateState $ \s → s { channel   = c }
      handle (NewVelocity v)  = modifyIORef appStateRef $ updateState $ \s → s { velocity  = v }

      handle PanicEvent = sendToMP Panic

      updateState ∷ (AppState → AppState) → AppState → AppState
      updateState f oldState = if baseKey   newState /= baseKey   oldState
                               || basePitch newState /= basePitch oldState
                                  then newState { pitchMap = getPitchMapping baseKey' basePitch' }
                                  else newState

        where newState   = f oldState
              baseKey'   = baseKey newState
              basePitch' = basePitch newState

  (interface <$) $ forkIO $ catchThreadFail "Event Handler" $ forever $ takeMVar bus >>= handle


getPitchMapping ∷ RowKey → Pitch → HashMap RowKey Pitch
getPitchMapping baseKey basePitch = fromList (zip l lp) `union` fromList (zip r rp)

  where (reverse → l, r) = span (/= baseKey) allKeysOrder

        lp, rp ∷ [Pitch]

        lp = eitherValue $ do
          if basePitch > minBound then Right () else Left []
          let prev = pred basePitch
          if prev > minBound then Right [prev, pred prev .. minBound] else Left [prev]

        rp = eitherValue $ do
          if maxBound > basePitch then Right () else Left [basePitch]
          let next = succ basePitch
          if maxBound > next then Right [basePitch .. maxBound] else Left [basePitch, next]


eitherValue ∷ Either a a → a
eitherValue (Left  x) = x
eitherValue (Right x) = x