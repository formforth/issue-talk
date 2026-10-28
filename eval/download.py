"""Download only the pinned public model and verify it before inference."""

import hashlib
import json
import sys
import urllib.request
from pathlib import Path

manifest = json.loads((Path(__file__).parent / "model.json").read_text())
output = Path(sys.argv[1])
if (
    output.exists()
    and hashlib.file_digest(output.open("rb"), "sha256").hexdigest()
    == manifest["sha256"]
):
    raise SystemExit(0)
url = f"https://huggingface.co/{manifest['model']}/resolve/{manifest['revision']}/{manifest['filename']}"
partial = output.with_suffix(".partial")
output.parent.mkdir(parents=True, exist_ok=True)
with urllib.request.urlopen(url, timeout=120) as response, partial.open("wb") as stream:
    while block := response.read(1024 * 1024):
        stream.write(block)
with partial.open("rb") as stream:
    if hashlib.file_digest(stream, "sha256").hexdigest() != manifest["sha256"]:
        partial.unlink()
        raise SystemExit("Model checksum mismatch")
partial.replace(output)
