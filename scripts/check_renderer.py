"""Verify the licensed offline asset without contacting a registry or CDN."""

import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent / "IssueTalk/Resources/Renderer"
manifest = json.loads((root / "vendor.json").read_text())
actual = hashlib.sha256((root / "mermaid.min.js").read_bytes()).hexdigest()
if actual != manifest["sha256"]:
    raise SystemExit("Mermaid checksum mismatch; review and update vendor.json")
if not (root / "MERMAID-LICENSE.txt").read_text().startswith("The MIT License (MIT)"):
    raise SystemExit("Mermaid license missing")
print(f"Verified Mermaid {manifest['version']} for offline rendering")
