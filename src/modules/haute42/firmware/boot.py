"""
boot.py -- Haute42 (RP2040) as a MIDI-only USB device.

Runs once at power-on, before code.py, and is the only place CircuitPython
lets you change the USB descriptors.

Why this file exists: Ableton Move's USB-A port is not wired to the Pi's USB
controller. It goes through an XMOS chip that forwards USB MIDI class traffic
only. A stock CircuitPython board enumerates as a *composite* device -- mass
storage (CIRCUITPY) + CDC serial + HID + MIDI -- and an embedded host is far
more likely to reject that composite outright than a clean single-function
MIDI device. So we strip everything except MIDI.

MAINTENANCE MODE: hold S1 (the Select/Coin button, GP16) while plugging in to
keep CIRCUITPY and the serial console alive so you can edit code.py. Without
this escape hatch you would have to use CircuitPython safe mode to recover
the board after the first successful boot.
"""

import board
import digitalio
import storage
import usb_cdc
import usb_hid
import usb_midi

# S1 / Select on the Haute42 COSMOX pinout. Adjust if your board differs.
MAINTENANCE_PIN = board.GP16

_pin = digitalio.DigitalInOut(MAINTENANCE_PIN)
_pin.direction = digitalio.Direction.INPUT
_pin.pull = digitalio.Pull.UP
# Buttons are active-low: value False means the button is held down.
_maintenance = not _pin.value
# Release the pin so code.py can claim it again as a normal button.
_pin.deinit()

usb_midi.enable()

if not _maintenance:
    storage.disable_usb_drive()
    usb_cdc.disable()
    usb_hid.disable()

# Cosmetic, and makes the device easy to identify on a host. Wrapped because
# set_usb_identification is not present on every CircuitPython build.
try:
    import supervisor

    supervisor.set_usb_identification(manufacturer="Schwung", product="Haute42 MIDI")
except Exception:
    pass
