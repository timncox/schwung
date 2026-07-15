#!/usr/bin/env bash
set -euo pipefail

host_file="src/modules/chain/dsp/chain_host.c"
params_file="src/modules/chain/dsp/chain_params.c"
patch_file="src/modules/chain/dsp/chain_patch.c"

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required to run this test" >&2
  exit 1
fi

# Mapping assignment, value queries, and patch restore must all seed relative
# encoder state from the plugin's current value rather than a manifest default.
if ! rg -q 'knob_read_current_value\(inst, target, param, pinfo, fallback, &current\)' "$host_file"; then
  echo "FAIL: knob assignment does not seed from the live plugin value" >&2
  exit 1
fi
if ! rg -q 'knob_read_current_value\(inst, target, param, param_info,' "$host_file"; then
  echo "FAIL: knob value query does not refresh the assigned-knob cache" >&2
  exit 1
fi
if ! rg -q 'knob_read_current_value\(inst, target, param, pinfo, fallback, &current\)' "$patch_file"; then
  echo "FAIL: patch restore does not sync assigned knobs from live DSP state" >&2
  exit 1
fi

# Writes from hierarchy/module/remote surfaces must update matching mappings
# without calling back into the plugin on the SPI set_param path.
for target in synth fx1 fx2 midi_fx1 midi_fx2; do
  if ! rg -Fq "knob_sync_mapped_value(inst, \"${target}\", subkey, val);" "$host_file"; then
    echo "FAIL: ${target} writes do not synchronize assigned-knob state" >&2
    exit 1
  fi
done
if ! rg -q 'strcmp\(mapping->target, target\).*strcmp\(mapping->param, param\)' "$params_file"; then
  echo "FAIL: mapped-value synchronization is not scoped to target and parameter" >&2
  exit 1
fi

# Mapping removal compacts acceleration timestamps alongside the mappings.
if ! rg -Fq 'inst->knob_last_time_ms[j] = inst->knob_last_time_ms[j + 1];' "$host_file"; then
  echo "FAIL: clearing a mapping leaves acceleration timestamps misaligned" >&2
  exit 1
fi

echo "PASS: assigned knobs stay synchronized with live plugin values"
