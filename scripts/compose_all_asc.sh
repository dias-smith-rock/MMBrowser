#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
LIB="scripts/asc_layout.swift"
TMP="/tmp/mmb_asc_compose.swift"

for n in 01 02 03 04 05; do
  cat "$LIB" "scripts/compose_asc${n}.swift" > "$TMP"
  swift "$TMP"
done

file website/assets/appstore/0*.png
ls -la website/assets/appstore/0{2,3,4}*.png
