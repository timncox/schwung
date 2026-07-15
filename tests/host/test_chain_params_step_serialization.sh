#!/usr/bin/env bash
set -euo pipefail

host_file="src/modules/chain/dsp/chain_host.c"
params_file="src/modules/chain/dsp/chain_params.c"
header_file="src/modules/chain/dsp/chain_internal.h"

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required to run this test" >&2
  exit 1
fi

# Shadow UI must receive the parsed step/default metadata. Without step, a
# declared 0..100/step=5 control falls back to 0.01 and appears stuck when the
# plugin rounds its getter to whole percentages.
if ! rg -Fq '"\"min\":%g,\"max\":%g,\"default\":%g,\"step\":%g"' "$params_file"; then
  echo "FAIL: chain_params serializer does not preserve default and step" >&2
  exit 1
fi
if ! rg -Fq 'serialize_chain_params_json(const chain_param_info_t *params' "$header_file"; then
  echo "FAIL: shared chain_params serializer declaration is missing" >&2
  exit 1
fi
if ! rg -Fq '\"knob_acceleration\":\"%s\"' "$params_file"; then
  echo "FAIL: chain_params serializer drops knob_acceleration metadata" >&2
  exit 1
fi
if ! rg -Fq 'knob_wide_accel_multiplier(' "$host_file" ||
   ! rg -Fq 'knob_wide_accel_multiplier(' "src/modules/chain/dsp/chain_midi.c"; then
  echo "FAIL: assigned knob paths do not honor wide acceleration" >&2
  exit 1
fi

call_count="$(rg -c 'return serialize_chain_params_json\(' "$host_file")"
if [[ "$call_count" != "5" ]]; then
  echo "FAIL: expected synth, FX1/2, and MIDI FX1/2 to share the serializer; found $call_count call sites" >&2
  exit 1
fi

echo "PASS: fallback chain_params preserve knob step/default metadata"
