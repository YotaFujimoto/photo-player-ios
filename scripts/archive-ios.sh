#!/bin/bash
set -euo pipefail

xcodebuild archive \
  -project PhotoPlayer.xcodeproj \
  -scheme PhotoPlayer \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath build/PhotoPlayer.xcarchive \
  -derivedDataPath build/device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  2>&1 | tee build/archive.log

app='build/PhotoPlayer.xcarchive/Products/Applications/PhotoPlayer.app'
test -d "$app"
xcrun vtool -show-build "$app/PhotoPlayer" | tee build/device-platform.log
if codesign -dv "$app" > build/codesign.log 2>&1; then
  echo 'Expected an unsigned application, but found a code signature.' >&2
  exit 1
fi

mkdir -p build/package/Payload
ditto "$app" build/package/Payload/PhotoPlayer.app
# XML remains a valid iOS plist and enables independent verification on Windows.
plutil -convert xml1 build/package/Payload/PhotoPlayer.app/Info.plist
ditto -c -k --keepParent build/package/Payload dist/PhotoPlayer.ipa

python3 scripts/verify_ipa.py dist/PhotoPlayer.ipa > dist/build-info.json
cat dist/build-info.json | tee -a "$GITHUB_STEP_SUMMARY"
