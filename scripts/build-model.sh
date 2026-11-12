#!/bin/bash
# Rebuilds the turntable model from Models/turntable.py with Blender.
# Output: RecordPlayer/Resources/Turntable.usdz, plus a top-view preview in build/model-preview.png
set -euo pipefail
cd "$(dirname "$0")/.."

BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
mkdir -p RecordPlayer/Resources build
"$BLENDER" --background --factory-startup --python Models/turntable.py -- \
  "$PWD/RecordPlayer/Resources/Turntable.usdz" "$PWD/build/model-preview.png" \
  | grep -vE '^(Blender |Read |Fra:|Saved:|Time:|$)' || true
ls -la RecordPlayer/Resources/Turntable.usdz
