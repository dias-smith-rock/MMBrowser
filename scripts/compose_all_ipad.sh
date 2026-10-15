#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
LIB="scripts/asc_layout.swift"
TMP="/tmp/mmb_asc_ipad_compose.swift"

mkdir -p website/assets/appstore/ipad

for n in 01 02 03 04 05 06; do
  cat "$LIB" "scripts/compose_ipad_asc${n}.swift" > "$TMP"
  swift "$TMP"
done

file website/assets/appstore/ipad/*.png
ls -la website/assets/appstore/ipad/
