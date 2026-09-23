#!/usr/bin/env python3
"""Fails if any model's committed .glb is missing or older than its inputs.

    python3 art/check.py

"Older" means art/manifest.json records a different hash of the model's
script, art/lib and art/run.py than they have now. Rebuild with
`nix develop .#art -c art/build.sh MODEL_ID`. Needs only Python (no Blender).
"""

import json
import sys
from pathlib import Path

ART = Path(__file__).resolve().parent
sys.path.insert(0, str(ART))

from lib.hashing import input_hash  # noqa: E402


def main() -> int:
    catalog = json.loads((ART / "catalog.json").read_text())
    manifest_path = ART / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    problems = []
    for m in catalog["models"]:
        if m.get("status") == "planned":
            continue
        out = ART.parent / "godot" / m["output"]
        if not out.is_file():
            problems.append(f"{m['id']}: {m['output']} is missing")
        elif manifest.get(m["id"], {}).get("inputs") != input_hash(m["script"], m.get("args")):
            problems.append(f"{m['id']}: {m['output']} is out of date with {m['script']} or art/lib")
    for p in problems:
        print("stale: " + p)
    if problems:
        print("Rebuild with: nix develop .#art -c art/build.sh " + " ".join(p.split(":")[0] for p in problems))
        return 1
    print(f"All {sum(1 for m in catalog['models'] if m.get('status') != 'planned')} models are up to date.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
