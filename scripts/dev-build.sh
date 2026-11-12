#!/bin/bash
# Builds a debug app with the Swift compiler alone, for machines where xcodebuild is not set up.
# Output: build/dev/RecordPlayer.app
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/dev
APP=$OUT/RecordPlayer.app
TARGET=arm64-apple-macos15.0
mkdir -p "$APP/Contents/MacOS"

swiftc -parse-as-library -swift-version 6 -target $TARGET \
  -emit-module -emit-library -static -module-name TurntableCore \
  Packages/TurntableCore/Sources/TurntableCore/*.swift \
  -o $OUT/libTurntableCore.a -emit-module-path $OUT/TurntableCore.swiftmodule

find RecordPlayer -name '*.swift' -print0 | xargs -0 swiftc -parse-as-library -swift-version 6 \
  -target $TARGET -Onone -D DEBUG -I $OUT -L $OUT -lTurntableCore \
  -o "$APP/Contents/MacOS/RecordPlayer"

if [ -d RecordPlayer/Resources ]; then
  mkdir -p "$APP/Contents/Resources"
  find RecordPlayer/Resources -maxdepth 1 -type f -exec cp {} "$APP/Contents/Resources/" \;
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RecordPlayer</string>
<key>CFBundleIdentifier</key><string>com.amitka.recordplayer.dev</string>
<key>CFBundleName</key><string>RecordPlayer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
echo "$APP"
