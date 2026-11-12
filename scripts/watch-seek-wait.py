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
                    stack = destination.with_name(destination.stem + f"-{pid}-spindump.log")
                    subprocess.run(["sudo", "-n", "spindump", pid, "1", "10", "-onlyTarget", "-file", str(stack)], stdout=log,
                                   stderr=subprocess.STDOUT, timeout=45, check=False)
            except (OSError, ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                print(type(error).__name__, file=log)
        break
