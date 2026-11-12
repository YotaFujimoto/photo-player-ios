"""Capture one live stalled-operation stack; never control or retry playback."""
from datetime import datetime, timezone
from pathlib import Path
import subprocess
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
                processes = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True, timeout=5)
                # Names only (no command arguments). New runtimes may move
                # media work into differently named XPC processes.
                print("PROCESS INVENTORY\n" + processes, file=log, flush=True)
                for entry in processes.splitlines():
                    pid, executable = entry.strip().split(maxsplit=1)
                    if executable.endswith(("/PhotoPlayer.app/PhotoPlayer", "/mediaserverd", "/VTDecoderXPCService")):
                        print(f"\nSTACK {Path(executable).name} pid={pid}", file=log, flush=True)
                        # Sampling finished but symbolication exceeded ten
                        # seconds on the standard VM. This collector's budget
                        # does not change the application's/test's deadlines.
                        try:
                            # sample returned zero thread samples even as root.
                            # Switch to spindump's kernel stack capture; retain
                            # its separate output in the same evidence artifact.
                            stack = destination.with_name(destination.stem + f"-{pid}-spindump.log")
                            subprocess.run(["sudo", "-n", "spindump", pid, "1", "10", "-onlyTarget", "-file", str(stack)], stdout=log,
                                           stderr=subprocess.STDOUT, timeout=45, check=False)
                        except subprocess.TimeoutExpired:
                            print("Symbolication timed out", file=log, flush=True)
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                print(type(error).__name__, file=log)
        break
