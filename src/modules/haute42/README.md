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

## Backing up before you flash

Flashing wipes GP2040-CE and everything it stored. Take **both** backups below
— they cover different failure modes, and the second one cannot be taken once
you have left GP2040-CE behind.

### 1. GP2040-CE config (do this first)

This is the readable, portable copy of your button mapping — the one you want
if you ever reinstall a *newer* GP2040-CE rather than restoring this exact
image.

1. Plug the controller in **while holding S2**. (Or, if it is already plugged
   in, hold **S2 + B3 + B4** for five seconds.) This boots the web
   configurator instead of the gamepad.
2. Open <http://192.168.7.1>.
3. **Configuration → Data Backup and Restoration → Backup To File**, with all
   options selected.
4. While you are in there, note the **firmware version** and **board config**
   shown on the home page, and open **Pin Mapping** — see "Pin map" below,
   because this is your chance to confirm `code.py` matches your board.

### 2. Full flash image

This is the belt-and-braces one: every byte of flash, restorable by drag and
drop, putting the controller back exactly as it is today.

```bash
brew install picotool          # once
./backup-controller.sh         # writes to ~/tim-os/scratch/haute42-backup-<date>/
```

Plug the controller in **while holding S1 + S2 + UP** to enter BOOTSEL mode
(it mounts as `RPI-RP2`), then run the script. It dumps flash twice and
compares the two reads before declaring success — GP2040-CE keeps its config at
the *end* of flash, so a truncated read would silently lose exactly the thing
you are trying to preserve.

To restore later: hold BOOTSEL, drag `flash-backup.uf2` onto `RPI-RP2`.

## Flashing the controller

Everything here is reversible — see "Going back" below.

1. **Take both backups above.**
2. **Install CircuitPython.** With the board in BOOTSEL mode (hold
   **S1 + S2 + UP** while plugging in, or the on-board BOOT button if your case
   exposes it) it mounts as `RPI-RP2`. Drag on the CircuitPython `.uf2` for
   Raspberry Pi Pico from
   <https://circuitpython.org/board/raspberry_pi_pico/>. (If your Haute42 is an
   RP2350 board, use the Pico 2 build instead.) It reboots as `CIRCUITPY`.
3. **Copy the firmware.** Put `firmware/boot.py` and `firmware/code.py` in the
   root of `CIRCUITPY`.
4. **Replug.** It should now enumerate as a MIDI device named
   "Haute42 MIDI" — and `CIRCUITPY` will be *gone*. That is intentional.

### Going back

Once CircuitPython replaces GP2040-CE, the **S1 + S2 + UP** combo no longer
exists — that was GP2040-CE's. If your case does not expose the BOOT button,
the way back is through the REPL:

1. **Hold S1 while plugging in** (maintenance mode — see below). This keeps the
   serial console alive.
2. Connect to the REPL (`screen /dev/tty.usbmodem*`, or Mu / Thonny) and run:

   ```python
   import microcontroller
   microcontroller.on_next_reset(microcontroller.RunMode.UF2)
   microcontroller.reset()
   ```

   Eject `CIRCUITPY` first if it is mounted.
3. The board reappears as `RPI-RP2`. Drag on `flash-backup.uf2` to restore
   GP2040-CE exactly, or a fresh GP2040-CE `.uf2` plus your config backup.

### Getting back in to edit

`boot.py` hides the drive so the controller presents as a clean single-function
MIDI device — a composite device (drive + serial + HID + MIDI) is much more
likely to be rejected by an embedded host like Move's XMOS.

**Hold S1 (Select/Coin) while plugging in** to keep `CIRCUITPY` mounted. Without
that you would need CircuitPython safe mode to recover `code.py`.

### Pin map

**Verified 2026-08-12** against a **Haute42 COSMOX_Lite_Ultra** running
GP2040-CE v0.7.10: all 19 GPIOs claimed by `code.py` match the board's own
config exactly.

If you have a different Haute42 (GP2040-CE ships COSMOX, COSMOXCAS, COSMOXCAT,
COSMOXMLite, COSMOXMUltra, COSMOXXAnalog), re-check before flashing — the web
configurator's `/api/getPinMappings` endpoint is the authoritative source, and
it is only reachable while in web-config mode. `curl` it and decode with the
`GpioAction` enum in
<https://github.com/OpenStickCommunity/GP2040-CE/blob/main/proto/enums.proto>:

| GPIO | Button | | GPIO | Button |
|------|--------|-|------|--------|
| GP2  | UP     | | GP12 | R1 / P3 |
| GP3  | DOWN   | | GP13 | L1 / P4 |
| GP4  | RIGHT  | | GP14 | Turbo  |
| GP5  | LEFT   | | GP16 | S1     |
| GP6  | B1 / K1 | | GP17 | S2    |
| GP7  | B2 / K2 | | GP18 | L3    |
| GP8  | R2 / K3 | | GP19 | R3    |
| GP9  | L2 / K4 | | GP20 | A1    |
| GP10 | B3 / P1 | | GP21 | A2    |
| GP11 | B4 / P2 | |      |       |

**Alternate footprints are real, and both halves are live.** On this board
GP26 also maps to L3 and GP27 also maps to UP — the same action on two GPIOs,
because the PCB supports two switch positions. `code.py` deliberately claims
only GP18 and GP2. Claiming a pair would make that button fire its note twice.

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
