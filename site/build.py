#!/usr/bin/env python3
"""Builds Linguini's landing page, a static site with download links.

    python3 site/build.py                          # dist/builds/* -> dist/site/
    python3 site/build.py --builds DIR --out DIR
    python3 site/build.py --base-url https://example.com/releases/v0.1.0/

Build artifacts are matched to platforms by file name (see PLATFORMS), e.g.
linguini-linux-x86_64.zip, linguini-windows-x86_64.zip, linguini-macos.zip.
By default they are copied into <out>/downloads/. With --base-url the page
links to that location instead and nothing is copied. Either way the page
lists each file's size and SHA-256, and writes SHA256SUMS.

Platforms without an artifact still get a card, marked as not available yet.
Uses only the Python standard library.
"""

import argparse
import datetime
import hashlib
import html
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = Path(__file__).resolve().parent

PLATFORMS = [
    {
        "id": "linux",
        "name": "Linux",
        "arch": "x86_64",
        "pattern": re.compile(r"linux", re.I),
        "note": "glibc 2.35+ (Ubuntu 22.04, Debian 12, Fedora 36 or newer) and libva.",
    },
    {
        "id": "windows",
        "name": "Windows",
        "arch": "x86_64",
        "pattern": re.compile(r"(?<![a-z])win(dows|32|64)?(?![a-z])", re.I),  # not "darwin"
        "note": "Windows 10 or later.",
    },
    {
        "id": "macos",
        "name": "macOS",
        "arch": "Apple Silicon",
        "pattern": re.compile(r"mac|osx|darwin", re.I),
        "note": "macOS 12 or later.",
    },
]

ARTIFACT_SUFFIXES = (".zip", ".tar.gz", ".tar.xz", ".tgz", ".AppImage", ".dmg", ".exe", ".msi")


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} GB"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git_version() -> str:
    try:
        return subprocess.check_output(
            ["git", "describe", "--tags", "--always", "--dirty"], cwd=ROOT, stderr=subprocess.DEVNULL
        ).decode().strip()
    except (OSError, subprocess.CalledProcessError):
        return "dev"


def find_artifacts(builds: Path) -> dict:
    """Maps platform id -> artifact path. Warns about files it can't place."""
    found = {}
    if not builds.is_dir():
        return found
    for path in sorted(builds.iterdir()):
        if not path.is_file() or not path.name.endswith(ARTIFACT_SUFFIXES):
            continue
        matches = [p for p in PLATFORMS if p["pattern"].search(path.name)]
        if len(matches) != 1:
            print(f"warning: can't tell which platform {path.name} is for; skipping", file=sys.stderr)
            continue
        pid = matches[0]["id"]
        if pid in found:
            print(f"warning: two {pid} builds ({found[pid].name}, {path.name}); using the first", file=sys.stderr)
            continue
        found[pid] = path
    return found


def download_card(platform: dict, artifact: dict | None) -> str:
    e = html.escape
    icon = f'<svg class="os-icon" aria-hidden="true"><use href="#os-{platform["id"]}"/></svg>'
    head = f"""
        {icon}
        <h3>{e(platform["name"])}</h3>
        <p class="arch">{e(platform["arch"])}</p>"""
    if artifact is None:
        return f"""
      <li class="download unavailable" data-os="{platform["id"]}">{head}
        <p class="status">Not built yet</p>
        <p class="note">{e(platform["note"])}</p>
      </li>"""
    return f"""
      <li class="download" data-os="{platform["id"]}">{head}
        <a class="button" href="{e(artifact["href"])}" download>Download <span class="size">{e(artifact["size"])}</span></a>
        <p class="file">{e(artifact["name"])}</p>
        <p class="note">{e(platform["note"])}</p>
        <details class="checksum">
          <summary>SHA-256</summary>
          <code>{e(artifact["sha256"])}</code>
        </details>
      </li>"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--builds", type=Path, default=ROOT / "dist" / "builds", help="directory of build artifacts")
    parser.add_argument("--out", type=Path, default=ROOT / "dist" / "site", help="output directory (replaced)")
    parser.add_argument("--base-url", help="link downloads here instead of copying them into the site")
    parser.add_argument("--version", default=None, help="version label (default: git describe)")
    parser.add_argument("--repo-url", default="", help="source repository link for the footer")
    args = parser.parse_args()

    version = args.version or git_version()
    out: Path = args.out.resolve()
    if ROOT.is_relative_to(out) or SITE.is_relative_to(out) or args.builds.resolve().is_relative_to(out):
        print(f"refusing to replace {out}", file=sys.stderr)
        return 1
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    shutil.copytree(SITE / "assets", out / "assets")
    shutil.copy2(SITE / "style.css", out / "style.css")

    artifacts = {}
    sums = []
    for pid, path in find_artifacts(args.builds).items():
        digest = sha256(path)
        if args.base_url:
            href = args.base_url.rstrip("/") + "/" + path.name
        else:
            (out / "downloads").mkdir(exist_ok=True)
            shutil.copy2(path, out / "downloads" / path.name)
            href = "downloads/" + path.name
        artifacts[pid] = {"name": path.name, "href": href, "size": human_size(path.stat().st_size), "sha256": digest}
        sums.append(f"{digest}  {path.name}\n")
    if sums:
        target = out / ("SHA256SUMS" if args.base_url else "downloads/SHA256SUMS")
        target.write_text("".join(sums))

    cards = "".join(download_card(p, artifacts.get(p["id"])) for p in PLATFORMS)
    available = [p["id"] for p in PLATFORMS if p["id"] in artifacts]
    sums_href = ("SHA256SUMS" if args.base_url else "downloads/SHA256SUMS") if sums else ""
    repo_link = (
        f'<a href="{html.escape(args.repo_url)}">Source code</a> · ' if args.repo_url else ""
    )

    page = (SITE / "template.html").read_text()
    replacements = {
        "version": html.escape(version),
        "platforms": ", ".join(p["name"] for p in PLATFORMS if p["id"] in artifacts) or "Build from source",
        "built": datetime.date.today().isoformat(),
        "download_cards": cards,
        "available_json": html.escape(json.dumps(available)),
        "checksums_link": f'<a href="{sums_href}">SHA256SUMS</a>' if sums_href else "",
        "repo_link": repo_link,
        "downloads_summary": (
            f"{len(available)} of {len(PLATFORMS)} platforms available"
            if available else "No builds published yet. "
            + (f'<a href="{html.escape(args.repo_url)}">Build from source</a> in the meantime.'
               if args.repo_url else "Build from source in the meantime.")
        ),
    }
    for key, value in replacements.items():
        page = page.replace("{{" + key + "}}", value)
    leftover = re.findall(r"\{\{\w+\}\}", page)
    if leftover:
        print(f"template placeholders not filled: {leftover}", file=sys.stderr)
        return 1
    (out / "index.html").write_text(page)

    print(f"Built {out} ({version})")
    for p in PLATFORMS:
        a = artifacts.get(p["id"])
        print(f"  {p['name']:8} {a['name'] + '  ' + a['size'] if a else '(no build)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
