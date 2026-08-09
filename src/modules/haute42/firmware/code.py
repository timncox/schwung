"""
code.py -- Haute42 button -> USB MIDI bridge.

Deliberately dumb. Every button sends one fixed note number on one fixed
MIDI channel, forever. All the musical logic -- scale, root, octave, where
the notes are routed -- lives in the Schwung `haute42` module on the Move,
so you can change how the controller plays without reflashing it.

Channel 16 is used on purpose. Move's four tracks listen on channels 1-4 by
default, so nothing the controller sends is interpreted by Move directly;
the Schwung module is the only thing listening. That separation is also what
keeps the module's injected notes from feeding back into its own input --
see the cascade note in docs/MIDI_INJECTION.md.

Pin map below is the GP2040-CE **Haute42 COSMOX** config. GP2040-CE ships five
Haute42 variants (COSMOX, COSMOXCAS, COSMOXCAT, COSMOXMLite, COSMOXMUltra,
COSMOXXAnalog); if yours is a different one, check its BoardConfig.h at
https://github.com/OpenStickCommunity/GP2040-CE/tree/main/configs
and adjust NOTE_PINS / CC_PINS to match.
"""

import time

import board
import keypad
import usb_midi

# ---- Configuration -------------------------------------------------------

MIDI_CHANNEL = 15  # 0-based, so this is MIDI channel 16
BASE_NOTE = 36  # button 0 sends note 36; the Schwung module subtracts this
VELOCITY = 100  # buttons are digital, so velocity is fixed

# Playable buttons, in the order the Schwung module treats as scale degrees
# 0..15. Bottom action row first, then top action row, then the direction
# cluster, then the aux buttons.
NOTE_PINS = (
    board.GP6,   # 0  K1 / Cross      bottom action row
    board.GP7,   # 1  K2 / Circle
    board.GP8,   # 2  K3 / R2
    board.GP9,   # 3  K4 / L2
    board.GP10,  # 4  P1 / Square     top action row
    board.GP11,  # 5  P2 / Triangle
    board.GP12,  # 6  P3 / R1
    board.GP13,  # 7  P4 / L1
    board.GP5,   # 8  LEFT            direction cluster
    board.GP3,   # 9  DOWN
    board.GP4,   # 10 RIGHT
    board.GP2,   # 11 UP (thumb)
    board.GP18,  # 12 L3              aux
    board.GP19,  # 13 R3
    board.GP20,  # 14 A1 / Home
    board.GP21,  # 15 A2 / Capture
)

# Non-note buttons. The Schwung module uses these for octave shift.
CC_PINS = (
    board.GP16,  # S1 / Select  -> CC 20   (also the boot.py maintenance pin)
    board.GP17,  # S2 / Start   -> CC 21
    board.GP14,  # Turbo        -> CC 22
)
CC_NUMBERS = (20, 21, 22)

# Intentionally not claimed:
#   GP0, GP1, GP24  - reserved for GP2040-CE addons
#   GP23            - USB passthrough D+ (the PS5 auth dongle port)
#   GP28            - WS2812 RGB data
#   GP26, GP27      - alternate footprints for L3 / UP; on any given board only
#                     one of each pair is populated, and claiming both would
#                     double-trigger the note.

# ---- Setup ---------------------------------------------------------------

midi_out = usb_midi.ports[1]

ALL_PINS = NOTE_PINS + CC_PINS
NUM_NOTES = len(NOTE_PINS)

keys = keypad.Keys(ALL_PINS, value_when_pressed=False, pull=True)


def send(status, data1, data2):
    midi_out.write(bytes((status, data1, data2)))


def all_notes_off():
    """Clear anything a previous run might have left hanging."""
    for i in range(NUM_NOTES):
        send(0x80 | MIDI_CHANNEL, BASE_NOTE + i, 0)


all_notes_off()

# ---- Main loop -----------------------------------------------------------

while True:
    event = keys.events.get()
    if event is None:
        # keypad scans in the background and queues events, so sleeping here
        # costs nothing but CPU cycles saved.
        time.sleep(0.001)
        continue

    n = event.key_number

    if n < NUM_NOTES:
        note = BASE_NOTE + n
        if event.pressed:
            send(0x90 | MIDI_CHANNEL, note, VELOCITY)
        else:
            send(0x80 | MIDI_CHANNEL, note, 0)
    else:
        cc = CC_NUMBERS[n - NUM_NOTES]
        send(0xB0 | MIDI_CHANNEL, cc, 127 if event.pressed else 0)
