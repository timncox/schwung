#!/usr/bin/env bash
set -euo pipefail

# Regression: suspend_keeps_js overtakes may claim Back for an internal modal,
# and a real Note Off from the volume touch sensor must release the emergency
# Shift+Volume+Jog escape chord.

file="src/shadow/shadow_ui.js"

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required to run this test" >&2
  exit 1
fi

if ! rg -q 'MidiNoteOn, MidiNoteOff' "$file"; then
  echo "FAIL: overtake escape tracking does not import MidiNoteOff" >&2
  exit 1
fi

if ! perl -0ne 'exit((/\(status & 0xF0\) === MidiNoteOn \|\|[\s\S]*\(status & 0xF0\) === MidiNoteOff\)[\s\S]*hostVolumeKnobTouched = \(status & 0xF0\) === MidiNoteOn && d2 > 0;/s) ? 0 : 1)' "$file"; then
  echo "FAIL: volume touch release does not handle both Note On 0 and Note Off" >&2
  exit 1
fi

captures=$(rg -c 'wantsBack: \(globalThis\.wantsBack !== savedWantsBack\)' "$file")
if [ "$captures" -ne 2 ]; then
  echo "FAIL: wantsBack must be captured for fresh and reconnected overtakes" >&2
  exit 1
fi

if ! rg -q 'function overtakeModuleWantsBack\(\)' "$file"; then
  echo "FAIL: missing safe wantsBack callback wrapper" >&2
  exit 1
fi

if ! perl -0ne 'exit((/d1 === MoveBack && d2 > 0 &&[\s\S]*overtakeSuspendKeepsJs[\s\S]*if \(!overtakeModuleWantsBack\(\)\)[\s\S]*suspendOvertakeMode\(\);/s) ? 0 : 1)' "$file"; then
  echo "FAIL: host suspend still runs before an overtake modal can claim Back" >&2
  exit 1
fi

echo "PASS: overtake modal Back routing and volume-touch release are guarded"
