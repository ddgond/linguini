#!/usr/bin/env python3
"""Linguini progress tracker: the roadmap and model renders, live.

    python3 tools/tracker/server.py            # http://0.0.0.0:57197
    python3 tools/tracker/server.py --port N

Serves the page in this directory plus:
  /data.json          roadmap (tools/tracker/roadmap.json) + models
                      (art/catalog.json) + render timestamps, rebuilt per request
  /renders/<file>     images from art/renders/

The page polls /data.json and redraws when anything changes, so editing the
roadmap or re-rendering a model shows up within a few seconds.
Uses only the Python standard library.
"""

import argparse
import hashlib
import json
import mimetypes
import os
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
ROADMAP = HERE / "roadmap.json"
CATALOG = ROOT / "art" / "catalog.json"
RENDERS = ROOT / "art" / "renders"
PAGE_FILES = {"/": "index.html", "/index.html": "index.html", "/app.js": "app.js", "/style.css": "style.css"}


def read_json(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        return {**default, "error": f"{path.name}: {e}"} if isinstance(default, dict) else default


def build_data() -> dict:
    roadmap = read_json(ROADMAP, {"milestones": []})
    catalog = read_json(CATALOG, {"models": []})
    models = []
    for m in catalog.get("models", []):
        model = dict(m)
        renders = []
        for suffix in ("", "_2", "_3"):
            png = RENDERS / f"{m['id']}{suffix}.png"
            if png.exists():
                renders.append({"url": f"/renders/{png.name}?v={int(png.stat().st_mtime)}",
                                "updated": png.stat().st_mtime})
        model["renders"] = renders
        model["updated"] = max((r["updated"] for r in renders), default=None)
        output = ROOT / "godot" / m.get("output", "")
        model["built"] = output.is_file()
        models.append(model)
    data = {"roadmap": roadmap, "models": models}
    if "error" in catalog:
        data["catalog_error"] = catalog["error"]
    body = json.dumps(data, sort_keys=True)
    data["version"] = hashlib.sha1(body.encode()).hexdigest()[:12]
    return data


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # quiet

    def _send(self, body: bytes, content_type: str, cache: bool = False):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "max-age=3600" if cache else "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = unquote(urlparse(self.path).path)
        if path == "/data.json":
            self._send(json.dumps(build_data()).encode(), "application/json")
        elif path in PAGE_FILES:
            f = HERE / PAGE_FILES[path]
            self._send(f.read_bytes(), mimetypes.guess_type(f.name)[0] or "text/plain")
        elif path.startswith("/renders/"):
            name = Path(path).name
            f = RENDERS / name
            if f.suffix.lower() in (".png", ".jpg", ".webp") and f.is_file():
                # Versioned by ?v=mtime, so these can be cached.
                self._send(f.read_bytes(), mimetypes.guess_type(f.name)[0], cache=True)
            else:
                self.send_error(404)
        else:
            self.send_error(404)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=57197)
    args = parser.parse_args()
    RENDERS.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Linguini tracker on http://{args.host}:{args.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
