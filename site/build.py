#!/usr/bin/env python3
"""Builds Linguini's landing page, a static site with download links.

    python3 site/build.py                          # dist/builds/* -> dist/site/
    python3 site/build.py --builds DIR --out DIR
    python3 site/build.py --base-url https://example.com/releases/v0.1.0/

Build artifacts are matched to platforms by file name (see PLATFORMS), e.g.
linguini-linux-x86_64.zip, linguini-windows-x86_64.zip, linguini-macos.zip.
By default they are copied into <out>/downloads/. With --base-url the page
links to that location instead and nothing is copied. Either way the page
lists each file's size and links a SHA256SUMS it writes. Platforms without an
artifact are left off the page.

Uses only the Python standard library.
"""

import argparse
import datetime
import hashlib
import html
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
        "arch": "Apple Silicon & Intel",
        "pattern": re.compile(r"mac|osx|darwin", re.I),
        "note": "macOS 11 or later. Not notarized yet: allow it under System Settings › Privacy & Security on first launch.",
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


def download_row(platform: dict, artifact: dict) -> str:
    e = html.escape
    return f"""
        <li>
          <h3>{e(platform["name"])} <span class="arch">{e(platform["arch"])}</span></h3>
          <p><a href="{e(artifact["href"])}" download>{e(artifact["name"])}</a> <span class="size">{e(artifact["size"])}</span></p>
          <p class="note">{e(platform["note"])}</p>
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
        artifacts[pid] = {"name": path.name, "href": href, "size": human_size(path.stat().st_size)}
        sums.append(f"{digest}  {path.name}\n")
    if sums:
        target = out / ("SHA256SUMS" if args.base_url else "downloads/SHA256SUMS")
        target.write_text("".join(sums))

    e = html.escape
    if artifacts:
        sums_href = "SHA256SUMS" if args.base_url else "downloads/SHA256SUMS"
        rows = "".join(download_row(p, artifacts[p["id"]]) for p in PLATFORMS if p["id"] in artifacts)
        downloads = f"""<ul class="downloads">{rows}
      </ul>
      <p class="small">Version {e(version)}, built {datetime.date.today().isoformat()}. <a href="{sums_href}">SHA256SUMS</a></p>"""
    else:
        source = f'<a href="{e(args.repo_url)}">Build from source</a>' if args.repo_url else "Build from source"
        downloads = f"<p>No builds yet. {source} in the meantime.</p>"
    repo_link = f'<a href="{e(args.repo_url)}">Source code</a>. ' if args.repo_url else ""

    page = (SITE / "template.html").read_text()
    replacements = {"downloads": downloads, "repo_link": repo_link}
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
