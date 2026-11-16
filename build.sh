#!/bin/bash
# Build AgentLight.app (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"
APP=AgentLight.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/AgentLight" Sources/AgentLight/main.swift
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>AgentLight</string>
  <key>CFBundleIdentifier</key><string>com.agentlight.app</string>
  <key>CFBundleName</key><string>AgentLight</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "built $PWD/$APP"
