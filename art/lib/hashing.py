"""Input hashes for the staleness check: a model's .glb is current when it was
built from exactly its script plus the shared library as they are now."""

import hashlib
from pathlib import Path

ART = Path(__file__).resolve().parent.parent


def input_hash(script: str, args: dict | None = None, deps: list | None = None) -> str:
    """`deps` are extra files (relative to art/) the script imports, such as a
    multi-file model's own modules."""
    h = hashlib.sha256()
    h.update(repr(sorted((args or {}).items())).encode())
    files = [ART / script] + [ART / d for d in (deps or [])] + sorted((ART / "lib").glob("*.py")) + [ART / "run.py"]
    for f in files:
        h.update(f.relative_to(ART).as_posix().encode())
        h.update(f.read_bytes())
    return h.hexdigest()[:16]
