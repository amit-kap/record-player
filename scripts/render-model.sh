#!/bin/bash
# Renders high-resolution pictures of the turntable model from several angles with Blender (Cycles).
# Usage: scripts/render-model.sh [width height samples [shots]]   e.g. scripts/render-model.sh 3200 2000 160 01,04
# Output: docs/renders/*.png
set -euo pipefail
cd "$(dirname "$0")/.."

BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
"$BLENDER" --background --factory-startup --python Models/render.py -- "$PWD/docs/renders" "$@" \
  | grep -E '^(rendered|GPU unavailable|Error|Traceback|  File)' || true
ls -la docs/renders
