"""Permit only the reviewed new-photo writer; ban destructive/video/network APIs."""
from pathlib import Path
import re

forbidden = re.compile(
    r"PHAssetChangeRequest|deleteAssets|deleteAssetCollections|AVAssetExportSession|"
    r"requestExportSession|PHAssetResourceManager|URLSession|uploadTask|"
    r"Data\s*\(\s*contentsOf:|copyItem\s*\("
)
violations = []
for path in Path("PhotoPlayer").rglob("*.swift"):
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if forbidden.search(line):
            violations.append(f"{path}:{number}: forbidden media/network API")
        if re.search(r"PHAssetCreationRequest|performChanges", line) and path.name != "PhotoFrameWriter.swift":
            violations.append(f"{path}:{number}: photo creation outside the dedicated writer")
writer = Path("PhotoPlayer/PhotoFrameWriter.swift").read_text(encoding="utf-8")
if writer.count("performChanges") != 1 or writer.count("PHAssetCreationRequest.forAsset()") != 1 or "with: .photo," not in writer:
    violations.append("Expected one add-only photo transaction")
if violations:
    raise SystemExit("\n".join(violations))
print("Media policy: only the dedicated add-only photo writer; no edits/deletes, video copies/exports or upload APIs.")
