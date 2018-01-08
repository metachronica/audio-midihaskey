{-# LANGUAGE UnicodeSyntax #-}

import Prelude.Unicode
import Data.Proxy

import Data.Function
import Control.Concurrent
import Control.Concurrent.MVar

import Sound.MIDI.Message.Channel

-- local
import Utils
import Keys
import GUI
import MIDIPlayer


main = do
  let startMidiKey = toPitch 20
      allRowsList = getAllRows startMidiKey (Proxy ∷ Proxy AllRows)

  sendToMIDIPlayer ← runMIDIPlayer

  runGUI GUIContext { allRows       = allRowsList
                    , buttonHandler = \_ midiNote → sendToMIDIPlayer $ NoteOn midiNote (toVelocity 127)
                    }