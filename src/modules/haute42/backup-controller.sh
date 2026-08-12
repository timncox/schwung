#!/usr/bin/env bash
#
# backup-controller.sh -- full flash image backup of an RP2040 controller.
#
# Dumps every byte of the controller's flash to a .uf2 you can drag back on
# to restore it exactly as it is right now -- firmware, config, everything.
# Run this BEFORE flashing CircuitPython.
#
# The controller must be in BOOTSEL mode. On a Haute42 running GP2040-CE:
#   hold S1 + S2 + UP while plugging in
# (or hold the on-board BOOT button, if your case exposes it).
# It mounts as RPI-RP2.
#
# This is only half a backup. The other half is the GP2040-CE config JSON --
# see README.md, "Backing up before you flash". Do that one FIRST, because
# entering BOOTSEL mode means leaving the web configurator.

set -euo pipefail

DEST="${1:-$HOME/tim-os/scratch/haute42-backup-$(date +%Y-%m-%d)}"

die() { printf '\n\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
note() { printf '\033[36m==>\033[0m %s\n' "$1"; }

command -v picotool >/dev/null 2>&1 || die \
  "picotool not installed. Run: brew install picotool"

# ---- Confirm a board is actually in BOOTSEL mode --------------------------
# picotool info exits non-zero with a readable message when it finds nothing,
# so surface that rather than letting `save` fail more cryptically later.
note "Looking for a device in BOOTSEL mode..."
if ! INFO="$(picotool info -a 2>&1)"; then
    printf '%s\n' "$INFO" >&2
    die "No RP2040 found in BOOTSEL mode.

Unplug the controller, then plug it back in while holding S1 + S2 + UP.
It should appear as a drive named RPI-RP2. Then run this again."
fi

printf '%s\n' "$INFO"

mkdir -p "$DEST"
note "Backing up to $DEST"

# ---- Dump twice and compare ----------------------------------------------
# A truncated or flaky read is the one failure that would quietly destroy the
# thing we are trying to preserve -- GP2040-CE keeps its config at the END of
# flash, so a short read loses exactly the button mapping. Two identical dumps
# is cheap proof the read is stable and complete.
note "Reading flash (pass 1 of 2)..."
picotool save -a "$DEST/flash-backup.uf2"

note "Reading flash (pass 2 of 2, verification)..."
picotool save -a "$DEST/.verify.uf2"

if ! cmp -s "$DEST/flash-backup.uf2" "$DEST/.verify.uf2"; then
    rm -f "$DEST/.verify.uf2"
    die "The two dumps differ -- the read is not reliable, do NOT trust this backup.
Try a different USB port or cable and run this again."
fi
rm -f "$DEST/.verify.uf2"
note "Both passes identical -- read is stable."

# ---- Record provenance ----------------------------------------------------
printf '%s\n' "$INFO" > "$DEST/picotool-info.txt"
shasum -a 256 "$DEST/flash-backup.uf2" > "$DEST/SHA256"

SIZE_H="$(du -h "$DEST/flash-backup.uf2" | cut -f1)"
BYTES="$(wc -c < "$DEST/flash-backup.uf2" | tr -d ' ')"
# A UF2 carries 256 payload bytes per 512-byte block, so the image is ~2x the
# flash it represents. Anything much under 4 MB means a 2 MB part; well under
# that suggests a partial read worth a second look.
printf 'flash-backup.uf2  %s (%s bytes) -- represents ~%s MB of flash\n' \
    "$SIZE_H" "$BYTES" "$(( BYTES / 2 / 1024 / 1024 ))" > "$DEST/README.txt"

cat >> "$DEST/README.txt" <<'EOF'

To restore the controller exactly as it was:
  1. Hold BOOTSEL (or S1+S2+UP if GP2040-CE is still installed) while plugging in.
  2. Drag flash-backup.uf2 onto the RPI-RP2 drive.
  3. Wait for it to reboot.

Verify this file still matches its checksum before relying on it:
  shasum -a 256 -c SHA256
EOF

note "Done."
printf '\n'
cat "$DEST/README.txt"
printf '\nBackup directory: %s\n' "$DEST"
