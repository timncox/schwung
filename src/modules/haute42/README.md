# Haute42 Module

Turns a Haute42 leverless arcade controller into a scale-aware note source for
Move's native tracks and Schwung slot synths, over the USB-A port.

Two halves:

- `firmware/` — CircuitPython for the controller's RP2040. Makes it a
  class-compliant USB MIDI device.
- `ui.js` — a Schwung overtake module that maps its buttons to a scale and
  routes them.

## Why it works this way

Move's USB-A port is not wired to the Pi's USB controller — it goes through an
XMOS chip that forwards **USB MIDI class traffic only** (see
`docs/plans/2026-04-08-usb-c-host-mode.md`). A gamepad plugged into USB-A is
invisible to Linux. But the Haute42 runs
[GP2040-CE](https://gp2040-ce.info/) on an RP2040, so it can be reflashed into
something USB-A *does* accept: a MIDI device.

The split is deliberate. The firmware is dumb — 16 buttons, 16 fixed note
numbers, always on MIDI channel 16 — so the musical logic lives in JavaScript
on the Move where you can change it without reflashing.

Channel 16 is not arbitrary. Move's tracks listen on channels 1–4, so nothing
the controller sends reaches Move directly. It also prevents the injection
cascade described in `docs/MIDI_INJECTION.md`: this module injects on cable 2,
which is the same buffer that feeds `onMidiMessageExternal`, so injected notes
can echo straight back. The guard is channel separation — we only ever read
channel 16 and never inject there, so every echo is dropped by the first line
of the handler.

## Flashing the controller

Everything here is reversible. Keep your GP2040-CE `.uf2` and you can put the
controller back to being a fightstick by repeating step 2 with that file.

1. **Back up your GP2040-CE config first.** Plug the controller into a
   computer, open <http://192.168.7.1>, and save your button mapping and RGB
   settings. Flashing wipes them.
2. **Install CircuitPython.** Hold **BOOTSEL** while plugging in — the board
   mounts as `RPI-RP2`. Drag on the CircuitPython `.uf2` for Raspberry Pi Pico
   from <https://circuitpython.org/board/raspberry_pi_pico/>. (If your Haute42
   is an RP2350 board, use the Pico 2 build instead.) It reboots as
   `CIRCUITPY`.
3. **Copy the firmware.** Put `firmware/boot.py` and `firmware/code.py` in the
   root of `CIRCUITPY`.
4. **Replug.** It should now enumerate as a MIDI device named
   "Haute42 MIDI" — and `CIRCUITPY` will be *gone*. That is intentional.

### Getting back in to edit

`boot.py` hides the drive so the controller presents as a clean single-function
MIDI device — a composite device (drive + serial + HID + MIDI) is much more
likely to be rejected by an embedded host like Move's XMOS.

**Hold S1 (Select/Coin) while plugging in** to keep `CIRCUITPY` mounted. Without
that you would need CircuitPython safe mode to recover `code.py`.

### Pin map

`code.py` uses the GP2040-CE **Haute42 COSMOX** pinout. GP2040-CE ships several
Haute42 variants (COSMOX, COSMOXCAS, COSMOXCAT, COSMOXMLite, COSMOXMUltra,
COSMOXXAnalog). If yours is a different one, check its `BoardConfig.h` under
<https://github.com/OpenStickCommunity/GP2040-CE/tree/main/configs> and edit
`NOTE_PINS` / `CC_PINS`.

Button order as scale degrees 0–15: bottom action row, top action row,
direction cluster, then aux. S1/S2/Turbo send CC 20/21/22.

## Installing the module

Copy the module directory to the device and restart Schwung:

```bash
scp -r src/modules/haute42 ableton@move.local:/data/UserData/schwung/modules/
```

Note that the usual `./scripts/install.sh local --skip-modules` shortcut
**skips modules** — use the copy above, or drop the `--skip-modules` flag.

Then: **Shift + Vol + Jog Click** → Tools menu → **Haute42** (below the
Overtake divider).

## Using it

| Control | Action |
|---------|--------|
| **Knob 1** | Root note (C–B) |
| **Knob 2** | Scale |
| **Knob 3** | Octave (−3…+3) |
| **Knob 4** | Destination — channels 1–4 are Move tracks 1–4, 5–16 reach a Schwung slot whose Receive Channel matches |
| **Controller S1 / S2** | Octave down / up |
| **Controller Turbo** | All notes off (panic) |
| **Step LEDs 1–16** | Light up to show which controller buttons are held |
| **Shift + Vol + Jog Click** | Exit |

Scales: Major, Minor, Dorian, Mixolydian, Pentatonic Major, Pentatonic Minor,
Blues, Chromatic. Buttons past the end of a scale continue up into the next
octave, so a 5-note pentatonic spreads 16 buttons across three octaves.

## Known limitations

- **Exiting with buttons held sticks notes.** There is no exit hook, so the
  note-offs never get sent. Release everything before you leave, or hit Turbo
  to panic.
- **No velocity.** The buttons are digital; velocity is fixed at 100. The
  COSMOXXAnalog variant has analog inputs that could drive velocity, but this
  firmware does not read them.
- **Don't set a Move track's MIDI In to "All"** — it would pick up channel 16
  directly and double-trigger alongside the module's injected notes.
- **Untested on hardware.** Written against the docs; `move.local` was
  unreachable throughout. The riskiest unverified assumption is that Move's
  XMOS accepts a CircuitPython MIDI device at all — that is what `boot.py`'s
  descriptor stripping is there to maximise, but it needs a real plug-in to
  confirm.
