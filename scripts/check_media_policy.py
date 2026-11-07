"""Supplement code review with a ban on media mutation, exports and upload APIs."""
from pathlib import Path
import re

forbidden = re.compile(
    r"PHAsset(?:Creation|Change)Request|performChanges|AVAssetExportSession|"
    r"requestExportSession|PHAssetResourceManager|URLSession|uploadTask|"
    r"Data\s*\(\s*contentsOf:|copyItem\s*\("
)
violations = []
for path in Path("PhotoPlayer").rglob("*.swift"):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if forbidden.search(line):
            violations.append(f"{path}:{number}: forbidden media/network API")
if violations:
    raise SystemExit("\n".join(violations))
print("Media policy: no library mutations, full-video copies/exports or upload APIs found.")
