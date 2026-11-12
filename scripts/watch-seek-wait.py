"""Capture a live pending-seek stack once; never control or retry playback."""
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
    while True:
        line = stream.readline()
        if not line:
            time.sleep(0.1)
            continue
        pending += line
        if not pending.endswith("\n"):
            continue
        line, pending = pending, ""
        if "CI_CAPTURE_SEEK_WAIT" not in line:
            continue
        with destination.open("w") as log:
            print(datetime.now(timezone.utc).isoformat(), line, file=log, flush=True)
            try:
                processes = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True, timeout=5)
                for entry in processes.splitlines():
                    pid, executable = entry.strip().split(maxsplit=1)
                    if executable.endswith(("/PhotoPlayer.app/PhotoPlayer", "/mediaserverd", "/VTDecoderXPCService")):
                        print(f"\nSTACK {Path(executable).name} pid={pid}", file=log, flush=True)
                        subprocess.run(["sample", pid, "1", "10"], stdout=log,
                                       stderr=subprocess.STDOUT, timeout=10, check=False)
            except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                print(type(error).__name__, file=log)
        break
