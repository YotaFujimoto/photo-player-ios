"""Capture one live stalled-operation stack; never control or retry playback."""
from datetime import datetime, timezone
from pathlib import Path
import subprocess
import re
import sys
import time

source, offset, result = sys.argv[1:]
destination = Path("build") / (Path(result).stem + "-live-seek.log")
with open(source) as stream:
    stream.seek(int(offset))
    pending = ""
    stage = None
    stage_since = None
    while True:
        line = stream.readline()
        if not line:
            if stage_since is None or time.monotonic() - stage_since < 20:
                time.sleep(0.1)
                continue
            line = f"CI_CAPTURE_LIFECYCLE_WAIT last={stage}\n"
        else:
            pending += line
            if not pending.endswith("\n"):
                continue
            line, pending = pending, ""
            if "CI_LIFECYCLE_STAGE " in line:
                stage = line.strip()
                stage_since = None if "CI_LIFECYCLE_STAGE finished " in line else time.monotonic()
            if "CI_CAPTURE_SEEK_WAIT" not in line:
                continue
        with destination.open("w") as log:
            print(datetime.now(timezone.utc).isoformat(), line, file=log, flush=True)
            try:
                # Resolving every process's full path exceeded five seconds
                # before capture began. Native tests provide their own PID;
                # UI tests use exact-name lookup, with no system-wide inventory.
                supplied = re.search(r"\bpid=(\d+)\b", line)
                pids = [supplied.group(1)] if supplied else subprocess.check_output(
                    ["pgrep", "-x", "PhotoPlayer"], text=True, timeout=5).split()
                for pid in pids:
                    if not pid.isdigit() or int(pid) <= 1:
                        raise ValueError("Invalid capture process")
                    print(f"\nSTACK PhotoPlayer pid={pid}", file=log, flush=True)
                    # The last privileged spindump could not resolve the
                    # simulator's shared cache or XCTest images. sample runs
                    # as the same user as this owned test process and resolves
                    # its loaded images; keep the old stackshot as a fallback.
                    stack = destination.with_name(destination.stem + f"-{pid}-sample.log")
                    try:
                        sampled = subprocess.run(["sample", pid, "1", "10", "-file", str(stack)], stdout=log,
                                                 stderr=subprocess.STDOUT, timeout=8, check=False)
                        captured = sampled.returncode == 0
                    except subprocess.TimeoutExpired:
                        captured = False
                        print("sample exceeded capture budget", file=log, flush=True)
                    if not captured:
                        stack = destination.with_name(destination.stem + f"-{pid}-spindump.log")
                        subprocess.run(["sudo", "-n", "spindump", pid, "1", "10", "-onlyTarget", "-file", str(stack)], stdout=log,
                                       stderr=subprocess.STDOUT, timeout=45, check=False)
                # An app's output-queue wait alone cannot distinguish a hidden
                # layer from a stopped compositor/media service. Capture these
                # services once too, without changing or restarting any process.
                for service in ("backboardd", "mediaserverd"):
                    try:
                        service_pids = subprocess.check_output(["pgrep", "-x", service], text=True, timeout=5).split()
                        for service_pid in service_pids[:2]:
                            if not service_pid.isdigit() or int(service_pid) <= 1:
                                raise ValueError("Invalid service process")
                            sample = destination.with_name(destination.stem + f"-{service}-{service_pid}.log")
                            subprocess.run(["sudo", "-n", "sample", service_pid, "1", "10", "-file", str(sample)],
                                           stdout=log, stderr=subprocess.STDOUT, timeout=10, check=False)
                    except (OSError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                        print(service, type(error).__name__, file=log, flush=True)
            except (OSError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                print(type(error).__name__, file=log)
        break
