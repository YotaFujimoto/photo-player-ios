#!/bin/bash
set -euo pipefail

# Each CI group starts on a fresh standard runner. Never run two simulators at
# once or retry a case; the workflow requires every group before archiving.
test_group="${TEST_GROUP:-full}"
case "$test_group" in full|core|playback|library|frames|original) ;; *) exit 2 ;; esac

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

# Do not overlap cold compilation with the simulator's first boot/media import.
# A launch-time diagnostic on the standard 7 GB VM showed sustained compressor
# work while the app's main thread was idle. Bound compiler concurrency instead
# of extending UI test deadlines or changing application behavior.
xcodebuild build-for-testing \
  -jobs 2 \
  -project PhotoPlayer.xcodeproj \
  -scheme PhotoPlayer \
  -configuration Release \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath build/simulator \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee build/test-build.log

record_resources() {
  {
    printf '\nResource checkpoint: %s\n' "$1"
    date -u
    sysctl vm.swapusage
    vm_stat
    # Names and resource usage only; no arguments/environment/credentials.
    ps -axo pid,ppid,pcpu,rss,comm | sort -k4 -nr | head -n 15
  } >> build/resources.log 2>&1 || true
}
record_resources after-build
xcrun simctl boot "$simulator_id" 2>&1 | tee -a build/simulator.log
xcrun simctl bootstatus "$simulator_id" -b 2>&1 | tee -a build/simulator.log
xcrun simctl addmedia "$simulator_id" build/fixtures/synthetic-still.png build/fixtures/*.mov

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

bash scripts/prepare-fixture-probe.sh
fixture_probe='io.github.photoplayer.ci-fixture-readiness'
xcrun simctl install "$simulator_id" build/FixtureReadiness.app
xcrun simctl privacy "$simulator_id" grant photos "$fixture_probe"
# This helper is installed once and never reinstalled during the suite. Resolve
# its stable container once; querying the service again immediately after a
# reboot stalled even though bootstatus had completed.
fixture_container="$(xcrun simctl get_app_container "$simulator_id" "$fixture_probe" data)"
test -d "$fixture_container"
expected_videos=12
fixture_dirty=true
test_hosts=0
run_tests() {
  local result_bundle=$1
  shift
  test_hosts=$((test_hosts + 1))
  # Verify after every import or simulator restart. Between these explicit
  # boundaries the video library is unchanged (tests only add still photos).
  # Relaunching an extra foreground app before each host added independent
  # FrontBoard launch failures before otherwise unchanged test inputs.
  if [[ "$fixture_dirty" == true ]]; then
    local readiness_log="build/fixture-ready-$test_hosts.log"
    python3 scripts/check-fixture-ready.py "$simulator_id" "$fixture_probe" "$expected_videos" "$fixture_container" \
      2>&1 | tee "$readiness_log" || return $?
    fixture_dirty=false
  fi
  record_resources "$result_bundle"
  local host_status=0
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
  2>&1 | tee -a build/test.log || host_status=$?
  if [[ "$host_status" -ne 0 ]]; then
    python3 scripts/collect-simulator-failure.py "$simulator_id" "$result_bundle" || true
  fi
  return "$host_status"
}

run_frame_ui() {
  local frame_status=0
  xcrun simctl addmedia "$simulator_id" build/frame-fixtures/frames-ui.mov
  fixture_dirty=true
  expected_videos=$((expected_videos + 1))
  run_tests build/copy-results/FrameEndpoints.xcresult \
    "-only-testing:PhotoPlayerUITests/FrameExtractionUITests/testFixedWindowIndependentCursorAndEndpointButtons" || frame_status=$?
  run_tests build/copy-results/FramePixelsGestures.xcresult \
    "-only-testing:PhotoPlayerUITests/FrameExtractionUITests/testEntryPixelsFrameStepsSwipeAndNormalGestureRestoration" || frame_status=$?
  run_tests build/copy-results/FrameSaveLandscape.xcresult \
    "-only-testing:PhotoPlayerUITests/FrameExtractionUITests/testLandscapeControlsStayVisibleAndDoneSavesThenReturnsPaused" || frame_status=$?
  run_tests build/copy-results/FrameCropPortrait.xcresult \
    "-only-testing:PhotoPlayerUITests/FrameCropUITests/testPortraitCropGesturesRelativeWindowResetAndCancel" || frame_status=$?
  run_tests build/copy-results/FrameCropLandscape.xcresult \
    "-only-testing:PhotoPlayerUITests/FrameCropUITests/testLandscapeCropEdgesRotationAndOnePhotoSave" || frame_status=$?
  xcrun simctl addmedia "$simulator_id" build/frame-fixtures/frames-hdr-ui.mov
  fixture_dirty=true
  expected_videos=$((expected_videos + 1))
  run_tests build/copy-results/FrameHDR.xcresult \
    "-only-testing:PhotoPlayerUITests/FrameHDRUITests" || frame_status=$?
  return "$frame_status"
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
if [[ "$test_group" == full || "$test_group" == core ]]; then
  run_tests build/copy-results/UnitTests.xcresult "-only-testing:PhotoPlayerTests" \
    "-skip-testing:PhotoPlayerTests/LongGOPFixtureTests"
fi
if [[ "${PLAYBACK_CHECK_ONLY:-false}" == true ]]; then
  # Evidence-only diagnosis of startup/termination and the original encoding.
  # The full path below still runs every test once before any IPA is produced.
  playback_status=0
  run_tests build/copy-results/SeekBarLandscape.xcresult \
    "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testBarTapDragAndPlaybackIntentLandscape" || playback_status=$?
  run_tests build/copy-results/SeekHorizontalPortrait.xcresult \
    "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testHorizontalSwipePriorityAndHoldExclusionPortrait" || playback_status=$?
  xcrun simctl addmedia "$simulator_id" build/fixture-source/long-gop-regression.mov
  fixture_dirty=true
  expected_videos=$((expected_videos + 1))
  run_tests build/copy-results/OriginalFixtureIdentity.xcresult \
    "-only-testing:PhotoPlayerTests/LongGOPFixtureTests" || playback_status=$?
  run_tests build/copy-results/OriginalSeekBarPortrait.xcresult \
    "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testOriginalLongGOPBarTapDragAndPlaybackIntentPortrait" || playback_status=$?
  run_tests build/copy-results/OriginalSeekBarLandscape.xcresult \
    "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testOriginalLongGOPBarTapDragAndPlaybackIntentLandscape" || playback_status=$?
  exit "$playback_status"
fi
if [[ "${FRAME_CHECK_ONLY:-false}" == true ]]; then
  # An explicitly requested diagnostic CI scope, never a distributable build.
  # The workflow skips both archive and IPA upload in this mode.
  run_tests build/copy-results/SeekBarLandscape.xcresult \
    "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testBarTapDragAndPlaybackIntentLandscape"
  run_frame_ui
  exit 0
fi
# Collect independent UI failures in one run; keep every case, deadline and
# nonzero result. No retries or acceptance changes. Unit/build gates stay fatal.
test_status=0
if [[ "$test_group" == full || "$test_group" == core ]]; then
run_tests build/copy-results/FullscreenCanvas.xcresult "-only-testing:PhotoPlayerUITests/FullscreenUITests/testLandscapeCanvasSafeControlsAndPortraitPreserved" || test_status=$?
run_tests build/copy-results/FullscreenChrome.xcresult "-only-testing:PhotoPlayerUITests/FullscreenUITests/testAutoHideSingleDoubleTapAndPausedControls" || test_status=$?
run_tests build/copy-results/FullscreenMenu.xcresult "-only-testing:PhotoPlayerUITests/FullscreenUITests/testSpeedMenuPinsControlsThroughPressAndSelection" || test_status=$?
run_tests build/copy-results/FullscreenLifecycle.xcresult "-only-testing:PhotoPlayerUITests/FullscreenUITests/testHiddenSwipeHeldRateBarAndLifecycleCleanup" || test_status=$?
fi
if [[ "$test_group" == full ]]; then
# Restore the established single service boundary. Rebooting before every host
# added startup/service failures without proving that it fixes XCTest stalls.
# The read-only fixture check repeats after this boundary. No retry, erasure,
# assertion removal, deadline extension or application change is involved.
record_resources before-regression-reboot
xcrun simctl shutdown "$simulator_id" 2>&1 | tee -a build/simulator.log
xcrun simctl boot "$simulator_id" 2>&1 | tee -a build/simulator.log
xcrun simctl bootstatus "$simulator_id" -b 2>&1 | tee -a build/simulator.log
fixture_dirty=true
record_resources after-regression-reboot
fi
if [[ "$test_group" == full || "$test_group" == playback ]]; then
run_tests build/copy-results/PlaybackSeek.xcresult "-only-testing:$playback_seek" || test_status=$?
# Isolate each new interaction case too. A combined host showed multi-second
# accessibility snapshots and timed out before a swipe could be synthesized.
# Keep every case and deadline, and run each once on the same simulator.
run_tests build/copy-results/SeekBarPortrait.xcresult "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testBarTapDragAndPlaybackIntentPortrait" || test_status=$?
run_tests build/copy-results/SeekBarLandscape.xcresult "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testBarTapDragAndPlaybackIntentLandscape" || test_status=$?
run_tests build/copy-results/SeekHorizontalPortrait.xcresult "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testHorizontalSwipePriorityAndHoldExclusionPortrait" || test_status=$?
run_tests build/copy-results/SeekHorizontalLandscape.xcresult "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testHorizontalSwipePriorityAndHoldExclusionLandscape" || test_status=$?
run_tests build/copy-results/SeekLayout.xcresult "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testLoadingErrorAndSeekOverlaysNeverMoveNormalControls" || test_status=$?
run_tests build/copy-results/SeekFeedback.xcresult "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testSkipFeedbackIsBoundedReplacedAndDoesNotBlockInput" || test_status=$?
run_tests build/copy-results/GestureSkip.xcresult "-only-testing:$gesture_skip" || test_status=$?
run_tests build/copy-results/GestureHold.xcresult "-only-testing:$gesture_hold" || test_status=$?
fi

if [[ "$test_group" == full || "$test_group" == library ]]; then
run_tests build/TestResults.xcresult \
  "-skip-testing:PhotoPlayerTests" \
  "-skip-testing:PhotoPlayerUITests/VideoPlaybackTests" \
  "-skip-testing:PhotoPlayerUITests/SeekInteractionUITests" \
  "-skip-testing:PhotoPlayerUITests/FullscreenUITests" \
  "-skip-testing:PhotoPlayerUITests/FrameExtractionUITests" \
  "-skip-testing:PhotoPlayerUITests/FrameHDRUITests" \
  "-skip-testing:PhotoPlayerUITests/FrameCropUITests" \
  "-skip-testing:$copy_contact" "-skip-testing:$copy_reopen" \
  "-skip-testing:$geometry_live" "-skip-testing:$geometry_controls" \
  "-skip-testing:PhotoPlayerUITests/InputLifecycleTests" \
  "-skip-testing:PhotoPlayerUITests/PlaybackGestureTests" || test_status=$?
# The combined gesture session observed a 5.74s accessibility snapshot and a
# stale Loading value while the fresh query already showed Playing. Isolate each
# gesture case in a fresh host, keeping every assertion and deadline unchanged.
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
fi
if [[ "$test_group" == full || "$test_group" == frames || "$test_group" == original ]]; then
# A second, explicitly identified fixture condition, never a retry of a failed
# case. Preserve the former 25-second-GOP decoding coverage alongside bounded UI
# material. The import is last so all twelve-card selection assertions stay intact.
xcrun simctl addmedia "$simulator_id" build/fixture-source/long-gop-regression.mov
fixture_dirty=true
expected_videos=$((expected_videos + 1))
run_tests build/copy-results/OriginalFixtureIdentity.xcresult \
  "-only-testing:PhotoPlayerTests/LongGOPFixtureTests"
run_tests build/copy-results/OriginalPlaybackSeek.xcresult \
  "-only-testing:PhotoPlayerUITests/VideoPlaybackTests/testOriginalLongGOPPhotoKitVideoPlaybackRateAndSeek" || test_status=$?
run_tests build/copy-results/OriginalSeekBarPortrait.xcresult \
  "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testOriginalLongGOPBarTapDragAndPlaybackIntentPortrait" || test_status=$?
run_tests build/copy-results/OriginalSeekBarLandscape.xcresult \
  "-only-testing:PhotoPlayerUITests/SeekInteractionUITests/testOriginalLongGOPBarTapDragAndPlaybackIntentLandscape" || test_status=$?
fi
# Import numbered frame material only after the original twelve/thirteen-video
# selection regressions. Each frame UI case gets a fresh host on this same phone.
if [[ "$test_group" == full || "$test_group" == frames ]]; then
  run_frame_ui || test_status=$?
fi
exit "$test_status"
