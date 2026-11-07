#!/bin/bash
set -euo pipefail

# Select exactly one available iPhone, from the newest installed iOS runtime.
simulator_id="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if ".iOS-" not in runtime:
        continue
    phones = [d for d in devices[runtime] if d["isAvailable"] and d["name"].startswith("iPhone")]
    if phones:
        print(phones[0]["udid"])
        break
else:
    sys.exit("No available iPhone simulator")
')"
printf 'Simulator: %s\n' "$simulator_id" | tee build/simulator.log
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b

xcodebuild test \
  -project PhotoPlayer.xcodeproj \
  -scheme PhotoPlayer \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -derivedDataPath build/simulator \
  -resultBundlePath build/TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  | tee build/test.log

xcrun xcresulttool export attachments \
  --path build/TestResults.xcresult --output-path build/screenshots
