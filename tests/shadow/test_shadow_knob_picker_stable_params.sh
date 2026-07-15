#!/usr/bin/env bash
set -euo pipefail

file="src/shadow/shadow_ui.js"

if ! command -v rg >/dev/null 2>&1; then
  echo "rg is required to run this test" >&2
  exit 1
fi

# Picker labels should prefer module metadata names (e.g. "FX Density") over
# raw keys, and momentary idle/trigger actions must not be assignable to knobs.
if ! rg -Fq 'function getKnobPickerParamInfo(entry, metaByKey)' "$file"; then
  echo "FAIL: knob picker metadata normalizer is missing" >&2
  exit 1
fi
if ! rg -Fq 'if (isTriggerEnumMeta(triggerMeta)) return null;' "$file"; then
  echo "FAIL: knob picker still exposes momentary trigger actions" >&2
  exit 1
fi
if ! rg -Fq '(inlineMeta.name || inlineMeta.label)' "$file" ||
   ! rg -Fq '(chainMeta.name || chainMeta.label)' "$file"; then
  echo "FAIL: knob picker does not use human-readable module parameter names" >&2
  exit 1
fi
if ! rg -Fq 'const info = getKnobPickerParamInfo(p, metaByKey);' "$file" ||
   ! rg -Fq 'const info = getKnobPickerParamInfo(k, metaByKey);' "$file"; then
  echo "FAIL: hierarchy parameter and knob lists do not share picker filtering" >&2
  exit 1
fi

echo "PASS: knob picker exposes stable parameters with module-defined labels"
