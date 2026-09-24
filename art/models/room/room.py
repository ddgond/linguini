"""The streamer's bedroom: shell, furniture and dressing, joined into one mesh
with a lightmap UV map, baked once per mood.

Outputs (godot/art/room/):
  room.glb                the room (UV2 is the lightmap layout) and the
                          window glass
  layout.json             where things are: the tank, screen, speakers, lights
  lightmap_<mood>.exr     baked light (no albedo), one per mood

What's outside the window is its own model (art/models/street).

Bake quality comes from ART_BAKE: "none" (skip baking), "draft" (the default:
small and quick, fine on a laptop CPU) or "final" (full size, many samples;
use a fast machine, and ART_DEVICE=GPU for its graphics card).
"""

import json
import os
from pathlib import Path

import bpy

from lib.common import join

import dressing
import furniture
import layout as L
import moods
import shell

OUT = Path(__file__).resolve().parents[3] / "godot" / "art" / "room"


def _write_layout(path, quality):
    """The layout points Godot places things by (godot/scripts/room_builder.gd),
    and the quality the lightmaps were baked at."""
    if quality == "none":  # the existing bakes stay
        try:
            quality = json.loads(path.read_text()).get("bake", "none")
        except (OSError, ValueError):
            pass
    path.write_text(json.dumps({
        "tank_origin": L.TANK_ORIGIN,
        "screen_center": L.SCREEN_CENTER,
        "screen_size": L.SCREEN_SIZE,
        "speakers": L.SPEAKERS,
        "room_camera": L.ROOM_CAMERA,
        "room_min": L.ROOM_MIN,
        "room_max": L.ROOM_MAX,
        "window": [L.WINDOW_CENTER_X, L.WINDOW_SILL, L.WINDOW_TOP, L.WINDOW_WIDTH],
        "floor_lamp": L.FLOOR_LAMP,
        "bedside_lamp": L.BEDSIDE_LAMP,
        "ceiling_light": L.CEILING_LIGHT,
        "monitor_glow": L.MONITOR_GLOW,
        "rgb_strip": L.RGB_STRIP,
        "bias_light": L.BIAS_LIGHT,
        "fairy_window_y": L.FAIRY_WINDOW_Y,
        "bake": quality,
    }, indent=2) + "\n")


def build():
    m = dressing.mats()
    parts = shell.build() + furniture.build(m) + dressing.build(m)
    room = join(parts, "Room")
    moods.lightmap_uvs(room)
    window = moods.window_glass()

    OUT.mkdir(parents=True, exist_ok=True)
    quality = os.environ.get("ART_BAKE", "draft")
    _write_layout(OUT / "layout.json", quality)
    if quality != "none":
        moods.bake_all(room, [window], OUT, quality)
    return [room, window]


def render(objects, renders_dir, model_id):
    """Tracker renders: the room lit by each mood, from the doorway."""
    moods.render_moods(objects, renders_dir, model_id)
