#!/usr/bin/env python3
"""Captures a snapshot of how the game looks, for the progress tracker.

    nix develop -c python3 tools/tracker/capture.py            # all shots, for the current milestone
    nix develop -c python3 tools/tracker/capture.py --milestone 3d --only menu editor
    python3 tools/tracker/capture.py --import DIR --milestone 3b --time "2026-09-23 17:40" \\
        --commit 3da5bdc night.png:"The bedroom at night" ...   # file existing screenshots

Each shot in shots.json runs the game with its arguments (under xvfb-run, so
it works headless) and saves a screenshot. A snapshot is a folder in
art/renders/scenes/ named <milestone>_<YYYYMMDD-HHMM>, with the images and a
meta.json (milestone, time, commit, shots). The tracker shows the newest one
as "the latest look" and every snapshot on a timeline.
"""

import argparse
import datetime
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SCENES = ROOT / "art" / "renders" / "scenes"


def git_commit() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def current_milestone() -> str:
    return json.loads((HERE / "roadmap.json").read_text()).get("now", "")


def capture(shot: dict, out: Path, godot: str, project: Path) -> dict | None:
    target = out / f"{shot['id']}.png"
    with tempfile.TemporaryDirectory() as tmp:
        main_shot = Path(tmp) / "main.png"
        args = list(shot.get("args", []))
        if shot.get("tracking"):
            args.append(f"--tracking-shot={target}")
            args.append(f"--screenshot={main_shot}")
        else:
            args.append(f"--screenshot={target}")
        args.append("--delay=6")
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 2000x1200x24", godot, "--path", str(project),
               "--resolution", "1280x720", "--", *args]
        # Its own process group, so a timeout takes Godot down with xvfb-run.
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        try:
            proc.wait(timeout=480)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
    if not target.is_file():
        print(f"  failed: {shot['id']}", file=sys.stderr)
        return None
    print(f"  {shot['id']}")
    return {"file": target.name, "title": shot["title"], "id": shot["id"]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--milestone", default=None, help="milestone id (default: the roadmap's current one)")
    parser.add_argument("--only", nargs="*", help="shot ids to take (default: all)")
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--jobs", type=int, default=2, help="shots rendered at once")
    parser.add_argument("--note", default="", help="a line about this snapshot")
    parser.add_argument("--import", dest="import_files", nargs="*", metavar="FILE:TITLE",
                        help="file existing screenshots as a snapshot instead of capturing")
    parser.add_argument("--time", default=None, help='with --import: when they were taken, "YYYY-MM-DD HH:MM"')
    parser.add_argument("--commit", default=None)
    parser.add_argument("--into", default=None, help="add the shots to this existing snapshot (its folder name)")
    parser.add_argument("--project", default=None, help="the godot/ project to run (default: this checkout's)")
    args = parser.parse_args()

    milestone = args.milestone or current_milestone()
    when = datetime.datetime.strptime(args.time, "%Y-%m-%d %H:%M") if args.time else datetime.datetime.now()
    out = SCENES / (args.into or f"{milestone}_{when:%Y%m%d-%H%M}")
    out.mkdir(parents=True, exist_ok=True)
    existing = json.loads((out / "meta.json").read_text()) if args.into and (out / "meta.json").is_file() else None
    project = Path(args.project) if args.project else ROOT / "godot"
    shots = []
    if args.import_files is not None:
        for spec in args.import_files:
            path, _, title = spec.partition(":")
            src = Path(path)
            dest = out / src.name
            shutil.copyfile(src, dest)
            shots.append({"file": dest.name, "title": title or src.stem, "id": src.stem})
    else:
        wanted = json.loads((HERE / "shots.json").read_text())["shots"]
        if args.only:
            wanted = [s for s in wanted if s["id"] in args.only]
        print(f"Capturing {len(wanted)} shots into {out.relative_to(ROOT)}")
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            shots = [s for s in pool.map(lambda s: capture(s, out, args.godot, project), wanted) if s]
    if existing:
        # Keep the snapshot's own details; replace shots taken again, in shots.json order.
        order = [s["id"] for s in json.loads((HERE / "shots.json").read_text())["shots"]]
        merged = {s["id"]: s for s in existing.get("shots", [])}
        merged.update({s["id"]: s for s in shots})
        existing["shots"] = sorted(merged.values(), key=lambda s: order.index(s["id"]) if s["id"] in order else 99)
        meta = existing
        shots = meta["shots"]
    else:
        meta = {"milestone": milestone, "time": when.isoformat(timespec="minutes"),
                "commit": args.commit if args.commit is not None else git_commit(), "note": args.note, "shots": shots}
    (out / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"Snapshot {out.name}: {len(shots)} shots")
    return 0 if shots else 1


if __name__ == "__main__":
    sys.exit(main())
