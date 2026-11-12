#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project RecordPlayer.xcodeproj -scheme RecordPlayer -configuration Debug -derivedDataPath build -quiet build
