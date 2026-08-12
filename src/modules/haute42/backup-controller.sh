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

# On macOS picotool generally needs root to claim the USB device -- without it
# it can segfault rather than report a permissions error. When run under sudo,
# $HOME is root's, so resolve the real user's home and hand the files back at
# the end.
REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_HOME="$(eval echo "~$REAL_USER")"

DEST="${1:-$REAL_HOME/tim-os/scratch/haute42-backup-$(date +%Y-%m-%d)}"

die() { printf '\n\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
note() { printf '\033[36m==>\033[0m %s\n' "$1"; }

command -v picotool >/dev/null 2>&1 || die \
  "picotool not installed. Run: brew install picotool"

# ---- Confirm a board is actually in BOOTSEL mode --------------------------
# picotool info exits non-zero with a readable message when it finds nothing,
# so surface that rather than letting `save` fail more cryptically later.
note "Looking for a device in BOOTSEL mode..."
# Capture the status separately -- `if ! cmd` inverts it, so $? inside the
# branch would read 0 and the crash case below would never fire.
rc=0
INFO="$(picotool info -a 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$INFO" >&2
    # 139 = SIGSEGV. picotool crashes rather than erroring when it cannot claim
    # the USB device, which on macOS means either missing root or being run from
    # a launchd-spawned process (macOS 15.3+ blocks USB access for those).
    if [ "$rc" -ge 128 ] || [ -z "$INFO" ]; then
        die "picotool crashed trying to reach the device (exit $rc).

This is a USB permissions problem, not a missing device. Two fixes, in order:
  1. Run this with sudo:  sudo $0
  2. Run it from Terminal.app directly, not from an editor, IDE, or agent --
     macOS 15.3+ blocks USB access for launchd-spawned processes."
    fi
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
# Relative path, so `shasum -c` still works if the backup directory is moved.
( cd "$DEST" && shasum -a 256 flash-backup.uf2 > SHA256 )

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

This is only half the backup. The GP2040-CE config export (from the web
configurator at 192.168.7.1) downloads to ~/Downloads -- move it in here
so both halves live together.
EOF

# Hand the files back if we ran under sudo, so they are not root-owned.
if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$REAL_USER" "$DEST"
    note "Ownership returned to $REAL_USER"
fi

note "Done."
printf '\n'
cat "$DEST/README.txt"
printf '\nBackup directory: %s\n' "$DEST"
