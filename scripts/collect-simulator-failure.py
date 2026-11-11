"""Bounded, read-only evidence after a failed CI host; never retries tests."""
from pathlib import Path
import subprocess
import sys

simulator, result_bundle = sys.argv[1:]
destination = Path("build") / (Path(result_bundle).stem + "-system-failure.log")
with destination.open("w") as log:
    try:
        subprocess.run(
            ["xcrun", "simctl", "spawn", simulator, "log", "show", "--style", "compact",
             "--last", "3m", "--predicate",
             'process == "mediaserverd" OR process == "PhotoPlayer" OR process == "runningboardd"'],
            stdout=log, stderr=subprocess.STDOUT, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(type(error).__name__, file=log)
    # Take stacks only if the failed process/service still exists. No launch,
    # kill, app input, buffer reset or media mutation is performed here.
    try:
        processes = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True, timeout=5)
        for line in processes.splitlines():
            pid, executable = line.strip().split(maxsplit=1)
            if executable.endswith(("/PhotoPlayer.app/PhotoPlayer", "/mediaserverd")):
                print(f"\nSTACK {Path(executable).name} pid={pid}", file=log, flush=True)
                subprocess.run(["sample", pid, "1", "10"], stdout=log,
                               stderr=subprocess.STDOUT, timeout=10, check=False)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(type(error).__name__, file=log)
