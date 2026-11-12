"""Read a unique, durable result from the simulator-only PhotoKit probe."""
from pathlib import Path
import os
import subprocess
import sys
import time
import uuid

simulator, bundle, expected, container = sys.argv[1:]
assert expected.isdigit() and int(expected) >= 12
token = str(uuid.uuid4())
assert Path(container).is_dir(), "The installed fixture helper container must remain present"
result = Path(container) / "Documents" / f"readiness-{token}.txt"
assert not result.exists(), "Never accept a previous probe result"

def finish_probe(lines):
    pids = [int(line.removeprefix("FIXTURE_PID=")) for line in lines if line.startswith("FIXTURE_PID=")]
    assert len(pids) == 1 and pids[0] > 1, "Require this probe's process identity"
    # This occurs only after the launch command returned and a terminal result
    # for our unique token was read. No extra launch, retry or arbitrary delay.
    result.with_suffix(".ack").write_text(token)
    stopped_by = time.monotonic() + 30
    while time.monotonic() < stopped_by:
        try:
            os.kill(pids[0], 0)  # Observe existence only; never send a signal.
        except ProcessLookupError:
            assert "FIXTURE_EXIT_ACKNOWLEDGED" in result.read_text().splitlines()
            print("FIXTURE_PROCESS_EXIT_CONFIRMED", flush=True)
            return
        time.sleep(0.1)
    raise TimeoutError("Fixture helper did not exit after host acknowledgement")

try:
    subprocess.run(
        ["xcrun", "simctl", "launch", "--terminate-running-process", simulator, bundle,
         "--expected-videos", expected, "--result-token", token], check=True, timeout=45
    )
except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
    if result.exists():
        print(result.read_text(), end="", flush=True)
    raise
# Console attachment can miss output from an app that exits during launch.
# Observe the atomic result instead, with one launch and a bounded condition.
deadline = time.monotonic() + 45
text = ""
while time.monotonic() < deadline:
    if result.exists():
        text = result.read_text()
        lines = text.splitlines()
        if f"FIXTURE_READY videos={expected}" in lines:
            print(text, end="", flush=True)
            finish_probe(lines)
            sys.exit(0)
        if any(line.startswith(("FIXTURE_NOT_READY", "FIXTURE_ACCESS_ERROR", "FIXTURE_UNEXPECTED")) for line in lines):
            print(text, end="", flush=True)
            finish_probe(lines)
            sys.exit(1)
    time.sleep(0.1)
print(text, end="", flush=True)
print(f"PROBE_DOCUMENTS_EXISTS={(Path(container) / 'Documents').is_dir()}", flush=True)
try:
    subprocess.run(["xcrun", "simctl", "spawn", simulator, "log", "show", "--style", "compact", "--last", "3m",
                    "--predicate", 'process == "FixtureReadiness" OR eventMessage CONTAINS "ci-fixture-readiness"'], timeout=30)
except (OSError, subprocess.TimeoutExpired) as error:
    print(f"Probe system log unavailable: {type(error).__name__}", flush=True)
for crash in sorted((Path.home() / "Library/Logs/DiagnosticReports").glob("FixtureReadiness*.ips"))[-2:]:
    print(crash.read_text(errors="replace")[:40_000], flush=True)
sys.exit("FIXTURE_RESULT_TIMEOUT")
