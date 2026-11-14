"""Bounded process cleanup after every XCTest host, without AX state."""
import subprocess
import sys
import time

simulator, label = sys.argv[1:]
bundle = "io.github.photoplayer.p6a936d329b934a8ba532081564a51c07"


def app_pids():
    # Unlimited width is required: simulator executable paths are much longer
    # than a terminal line. Never mistake a truncated path for process absence.
    processes = subprocess.check_output(["ps", "-axww", "-o", "pid=,comm="], text=True, timeout=5)
    result = []
    for line in processes.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) != 2:
            continue
        pid, executable = fields
        if (f"/Devices/{simulator}/" in executable
                and executable.endswith("/PhotoPlayer.app/PhotoPlayer")):
            result.append(int(pid))
    return result


try:
    # Resolve the app on this exact simulator before treating absence as valid.
    subprocess.run(["xcrun", "simctl", "get_app_container", simulator, bundle, "app"],
                   check=True, stdout=subprocess.DEVNULL, timeout=10)
    initial = app_pids()
    print(f"CI_HOST_CLEANUP {label} initial_pids={initial}", flush=True)
    if len(initial) > 1:
        raise RuntimeError("Multiple app processes on one simulator")
    if initial:
        # One termination request only, never relaunch/retry the test or the app.
        subprocess.run(["xcrun", "simctl", "terminate", simulator, bundle],
                       check=True, timeout=10)
        deadline = time.monotonic() + 10
        while app_pids():
            if time.monotonic() >= deadline:
                raise TimeoutError("App process remained after termination")
            time.sleep(0.1)
    print(f"CI_HOST_CLEANUP verified_not_running {label}", flush=True)
except (OSError, subprocess.SubprocessError, RuntimeError, TimeoutError) as error:
    print(f"CI_HOST_CLEANUP_FAILED {label} {type(error).__name__}: {error}", flush=True)
    sys.exit(1)
