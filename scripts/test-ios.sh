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
  local bundle name
  trap - EXIT
  for bundle in build/TestResults.xcresult build/copy-results/*.xcresult; do
    if [[ -d "$bundle" ]]; then
      name="$(basename "$bundle" .xcresult)"
      xcrun xcresulttool export attachments \
        --path "$bundle" --output-path "build/screenshots/$name" || {
        if [[ "$result" -eq 0 ]]; then result=1; fi
      }
    fi
  done
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

run_tests() {
  local result_bundle=$1
  shift
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
  -resultBundlePath "$result_bundle" \
  "$@" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee -a build/test.log
}

# Keep clipboard/large accessibility-report cases in fresh test-host
# sessions. The combined session previously stalled while terminating the app
# between tests; Xcode's host restart allowed the remaining cases to pass.
# Every test still runs once, sequentially on this same simulator, with unchanged
# assertions and individual deadlines. Preserve all result bundles on failure.
copy_contact='PhotoPlayerUITests/SingleTapTests/testCopyDistinguishesNewUnacceptedContactFromPreviousPlayback'
copy_reopen='PhotoPlayerUITests/SingleTapTests/testCopyKeepsDistinctOperationsWhenReopeningSameVideo'
geometry_live='PhotoPlayerUITests/ContactGeometryUITests/testLiveCellGeometryAfterScrollReturnReloadAndToggle'
geometry_controls='PhotoPlayerUITests/ContactGeometryUITests/testCopyAndToggleHaveDistinctControlInputsAndNeverSelect'
input_on='PhotoPlayerUITests/InputLifecycleTests/testFourToFiveAfterTabReturnWithMonitor'
input_off='PhotoPlayerUITests/InputLifecycleTests/testSameSingleTapsWithMonitorDisabled'
input_background='PhotoPlayerUITests/InputLifecycleTests/testBackgroundStopsPlaybackAndInputContinuesAfterReturn'
gesture_skip='PhotoPlayerUITests/PlaybackGestureTests/testDoubleTapBoundsSingleTapAndControlsInBothOrientations'
gesture_hold='PhotoPlayerUITests/PlaybackGestureTests/testHeldDoubleSpeedRestoresRateAndNeverStartsPausedPlayback'
playback_seek='PhotoPlayerUITests/VideoPlaybackTests/testPhotoKitVideoPlaybackRateAndSeek'
mkdir -p build/copy-results
# Validate the input under investigation first. On failure retain its evidence
# immediately; a successful candidate still runs every test exactly once.
run_tests build/copy-results/PlaybackSeek.xcresult "-only-testing:$playback_seek"
test_status=0
run_tests build/TestResults.xcresult \
  "-skip-testing:PhotoPlayerUITests/VideoPlaybackTests" \
  "-skip-testing:$copy_contact" "-skip-testing:$copy_reopen" \
  "-skip-testing:$geometry_live" "-skip-testing:$geometry_controls" \
  "-skip-testing:PhotoPlayerUITests/InputLifecycleTests" \
  "-skip-testing:PhotoPlayerUITests/PlaybackGestureTests" || test_status=$?
# The combined gesture session observed a 5.74s accessibility snapshot and a
# stale Loading value while the fresh query already showed Playing. Isolate each
# gesture case in a fresh host, keeping every assertion and deadline unchanged.
run_tests build/copy-results/GestureSkip.xcresult "-only-testing:$gesture_skip" || test_status=$?
run_tests build/copy-results/GestureHold.xcresult "-only-testing:$gesture_hold" || test_status=$?
run_tests build/copy-results/CopyContact.xcresult \
  "-only-testing:$copy_contact" || test_status=$?
run_tests build/copy-results/CopyReopen.xcresult \
  "-only-testing:$copy_reopen" || test_status=$?
run_tests build/copy-results/GeometryLive.xcresult \
  "-only-testing:$geometry_live" || test_status=$?
run_tests build/copy-results/GeometryControls.xcresult \
  "-only-testing:$geometry_controls" || test_status=$?
run_tests build/copy-results/InputOn.xcresult "-only-testing:$input_on" || test_status=$?
run_tests build/copy-results/InputOff.xcresult "-only-testing:$input_off" || test_status=$?
run_tests build/copy-results/InputBackground.xcresult "-only-testing:$input_background" || test_status=$?
exit "$test_status"
