#!/bin/bash
set -euo pipefail

# Use the pinned stable runtime instead of selecting an installed beta/RC.
xcrun simctl list devices available --json > build/simulators.json
simulator_id="$(python3 -c '
import json, os, sys
with open("build/simulators.json") as source:
    devices = json.load(source)["devices"]
runtime = "com.apple.CoreSimulator.SimRuntime.iOS-" + os.environ["SIMULATOR_OS"].replace(".", "-")
phones = [d for d in devices.get(runtime, [])
          if d["isAvailable"] and d["name"] == os.environ["SIMULATOR_MODEL"]]
if not phones:
    sys.exit("Pinned stable iPhone simulator is not available")
print(phones[0]["udid"])
')"
printf 'Simulator: %s / iOS %s / %s\n' "$SIMULATOR_MODEL" "$SIMULATOR_OS" "$simulator_id" | tee build/simulator.log
xcrun simctl boot "$simulator_id" 2>&1 | tee -a build/simulator.log
xcrun simctl bootstatus "$simulator_id" -b 2>&1 | tee -a build/simulator.log

# Export screenshots on test failure too, without losing the original failure status.
export_test_evidence() {
  local result=$?
  trap - EXIT
  if [[ -d build/TestResults.xcresult ]]; then
    xcrun xcresulttool export attachments \
      --path build/TestResults.xcresult --output-path build/screenshots || {
        if [[ "$result" -eq 0 ]]; then result=1; fi
      }
  fi
  exit "$result"
}
trap export_test_evidence EXIT

xcrun simctl addmedia "$simulator_id" build/fixtures/synthetic-still.png build/fixtures/*.mov

xcodebuild build-for-testing \
  -project PhotoPlayer.xcodeproj \
  -scheme PhotoPlayer \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/simulator \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee build/test-build.log

# Grant read access on the synthetic simulator library before exercising the real PhotoKit path.
xcrun simctl install "$simulator_id" build/simulator/Build/Products/Release-iphonesimulator/PhotoPlayer.app
xcrun simctl privacy "$simulator_id" grant photos io.github.photoplayer.p6a936d329b934a8ba532081564a51c07

# Register the UI test host explicitly. Xcode's implicit installation previously
# reached launch with FrontBoard reporting that this bundle was unknown.
ui_runner='build/simulator/Build/Products/Release-iphonesimulator/PhotoPlayerUITests-Runner.app'
test -d "$ui_runner"
xcrun simctl install "$simulator_id" "$ui_runner" 2>&1 | tee -a build/simulator.log
xcrun simctl get_app_container "$simulator_id" \
  io.github.photoplayer.p6a936d329b934a8ba532081564a51c07.uitests.xctrunner app \
  2>&1 | tee -a build/simulator.log

xcodebuild test-without-building \
  -project PhotoPlayer.xcodeproj \
  -scheme PhotoPlayer \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -destination-timeout 60 \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -derivedDataPath build/simulator \
  -resultBundlePath build/TestResults.xcresult \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee build/test.log
