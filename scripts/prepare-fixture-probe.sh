#!/bin/bash
set -euo pipefail

# A separate, simulator-only executable keeps readiness checks out of the app.
mkdir -p build/FixtureReadiness.app
cat > build/FixtureReadiness.app/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FixtureReadiness</string>
<key>CFBundleIdentifier</key><string>io.github.photoplayer.ci-fixture-readiness</string>
<key>CFBundleName</key><string>FixtureReadiness</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key>
<dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
<key>NSPhotoLibraryUsageDescription</key><string>Read synthetic CI fixtures.</string>
</dict></plist>
PLIST
xcrun --sdk iphonesimulator swiftc -parse-as-library -swift-version 5 -O \
  -target arm64-apple-ios17.0-simulator -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  scripts/FixtureReadiness.swift -o build/FixtureReadiness.app/FixtureReadiness
