#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
open build/Build/Products/Debug/RecordPlayer.app
