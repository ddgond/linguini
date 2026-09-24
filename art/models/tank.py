"""The fish tank: glass, silicone seams, trim, hood with its lamp, gravel, and
the wooden stand.

Origin is the inside bottom of the tank (Godot's Tank node), matching
godot/scripts/room_builder.gd: interior x -0.6..0.6, height 0..0.6, depth
-0.25..0.25 (front glass toward Godot +Z, which is Blender -Y), 1 cm glass,
gravel averaging 3 cm deep. The stand fills the 0.8 m below.

Materials Godot treats specially: "Glass" (glass shader) and "Lamp" (emissive).
"""

import math
import random

import bmesh
from mathutils import Vector, noise

from lib.common import (PALETTE, add_modifier, apply_modifiers, bevelled_box, box_uv, image, join, material,
                        mesh_object, shade_smooth, smoothstep)

W, H, D = 1.2, 0.6, 0.5  # interior
G = 0.01                 # glass
GRAVEL = 0.03
STAND_H = 0.8

RENDER_VIEWS = [(28, 16), (90, 8), (0, 55)]


def _glass():
    mat = material("Glass", (0.85, 0.95, 1.0), roughness=0.05, alpha=0.15)
    panes = [
        bevelled_box("Front", (W + 2 * G, G, H), 0.0015, 1, mat, (0, -(D / 2 + G / 2), H / 2)),
        bevelled_box("Back", (W + 2 * G, G, H), 0.0015, 1, mat, (0, D / 2 + G / 2, H / 2)),
        bevelled_box("Left", (G, D, H), 0.0015, 1, mat, (-(W / 2 + G / 2), 0, H / 2)),
        bevelled_box("Right", (G, D, H), 0.0015, 1, mat, (W / 2 + G / 2, 0, H / 2)),
        bevelled_box("Bottom", (W + 2 * G, D + 2 * G, G), 0.0015, 1, mat, (0, 0, -G / 2)),
    ]
    return panes


def _seams():
    mat = material("Silicone", (0.08, 0.1, 0.1), roughness=0.3, alpha=0.7)
    beads = []
    r = 0.004
    # Vertical beads in the four inside corners.
    for sx in (-1, 1):
        for sy in (-1, 1):
            beads.append(bevelled_box("Bead", (r * 1.4, r * 1.4, H - 0.01), r * 0.6, 2, mat,
                                      (sx * (W / 2 - r * 0.4), sy * (D / 2 - r * 0.4), H / 2)))
    return beads


def _trim():
    mat = material("Trim", PALETTE["plastic_black"], roughness=0.45)
    parts = []
    t = 0.022
    for z, height in ((-0.012, 0.03), (H + 0.002, 0.026)):
        parts.append(bevelled_box("RimFront", (W + 2 * G + 2 * t / 2, t, height), 0.004, 2, mat, (0, -(D / 2 + G), z)))
        parts.append(bevelled_box("RimBack", (W + 2 * G + 2 * t / 2, t, height), 0.004, 2, mat, (0, D / 2 + G, z)))
        parts.append(bevelled_box("RimLeft", (t, D + 2 * G, height), 0.004, 2, mat, (-(W / 2 + G), 0, z)))
        parts.append(bevelled_box("RimRight", (t, D + 2 * G, height), 0.004, 2, mat, (W / 2 + G, 0, z)))
    # The hood: a low rounded cover over the whole top, with a lamp strip underneath.
    hood_z = H + 0.03
    parts.append(bevelled_box("Hood", (W + 2 * G + 0.03, D + 2 * G + 0.03, 0.045), 0.012, 3, mat, (0, 0, hood_z)))
    # A feeding flap in the front of the hood, slightly proud of it.
    parts.append(bevelled_box("Flap", (0.3, 0.12, 0.006), 0.002, 2, mat, (0.28, -0.13, hood_z + 0.024)))
    parts.append(bevelled_box("FlapHandle", (0.06, 0.012, 0.008), 0.003, 2, mat, (0.28, -0.195, hood_z + 0.027)))
    lamp = material("Lamp", (1.0, 0.97, 0.9), roughness=0.3)
    parts.append(bevelled_box("LampStrip", (W * 0.8, 0.05, 0.004), 0.0015, 1, lamp, (0, 0.02, hood_z - 0.0235)))
    return parts


def _pebble_texture():
    rng = random.Random(4)
    points = [(rng.random(), rng.random()) for _ in range(90)]
    tones = [rng.choice([(0.8, 0.68, 0.52), (0.72, 0.6, 0.46), (0.86, 0.78, 0.64), (0.66, 0.56, 0.46),
                         (0.78, 0.64, 0.46), (0.84, 0.8, 0.72)]) for _ in points]

    def px(u, v):
        best, second, tone = 9.0, 9.0, (0.7, 0.6, 0.5)
        for (x, y), t in zip(points, tones):
            dx = min(abs(u - x), 1 - abs(u - x))
            dy = min(abs(v - y), 1 - abs(v - y))
            d = dx * dx + dy * dy
            if d < best:
                second, best, tone = best, d, t
            elif d < second:
                second = d
        edge = smoothstep(0.0, 0.0012, second - best)  # soft cracks between pebbles
        highlight = 1.0 - 4.0 * best
        k = (0.62 + 0.38 * edge) * (0.9 + 0.12 * highlight)
        return (tone[0] * k, tone[1] * k, tone[2] * k)

    return image("Pebbles", (192, 192), px)


def _gravel_height(x, y):
    # Gently sloped up toward the back, with pebble-sized bumps.
    slope = 0.008 * (y / (D / 2))
    bumps = 0.0035 * noise.noise(Vector((x * 60, y * 60, 0.3)))
    return GRAVEL + slope + bumps


def _gravel():
    tex = _pebble_texture()
    mat = material("Gravel", roughness=0.85, image=tex)
    nx, ny = 120, 50
    bm = bmesh.new()
    top = []
    for i in range(nx + 1):
        row = []
        for j in range(ny + 1):
            x = -W / 2 + W * i / nx
            y = -D / 2 + D * j / ny
            row.append(bm.verts.new((x, y, _gravel_height(x, y))))
        top.append(row)
    for i in range(nx):
        for j in range(ny):
            bm.faces.new((top[i][j], top[i + 1][j], top[i + 1][j + 1], top[i][j + 1]))
    # Skirts down to the tank floor, seen through the glass.
    edges = ([top[i][0] for i in range(nx + 1)], [top[nx][j] for j in range(ny + 1)],
             [top[i][ny] for i in range(nx, -1, -1)], [top[0][j] for j in range(ny, -1, -1)])
    for edge in edges:
        base = [bm.verts.new((v.co.x, v.co.y, 0.0)) for v in edge]
        for k in range(len(edge) - 1):
            bm.faces.new((edge[k], base[k], base[k + 1], edge[k + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object("Gravel", bm, [mat])
    shade_smooth(obj)
    box_uv(obj, 6.0)
    return obj


def _wood_texture(dark=False):
    base = tuple(c * 0.78 for c in PALETTE["wood"]) if dark else PALETTE["wood"]

    def px(u, v):
        n = noise.noise(Vector((u * 3.0, v * 40.0, 0.5)))
        rings = 0.5 + 0.5 * math.sin((u * 18.0 + n * 3.0) * math.pi)
        k = 0.85 + 0.15 * rings + 0.05 * noise.noise(Vector((u * 40, v * 2, 1.5)))
        return (base[0] * k, base[1] * k, base[2] * k)

    return image("WoodDark" if dark else "Wood", (128, 128), px)


def _stand():
    wood = material("Wood", roughness=0.55, image=_wood_texture())
    dark = material("WoodDark", roughness=0.6, image=_wood_texture(dark=True))
    brass = material("Brass", PALETTE["brass"], roughness=0.3, metallic=1.0)
    parts = []
    w, d = W + 0.1, D + 0.1
    parts.append(bevelled_box("StandTop", (w + 0.03, d + 0.03, 0.04), 0.008, 3, wood, (0, 0, -0.02 - G)))
    parts.append(bevelled_box("StandBody", (w, d, STAND_H - 0.11), 0.006, 2, wood, (0, 0, -(STAND_H - 0.11) / 2 - 0.04 - G)))
    parts.append(bevelled_box("Plinth", (w - 0.04, d - 0.04, 0.07), 0.004, 2, dark, (0, 0, -STAND_H + 0.035)))
    # Two doors with a raised panel each (4 mm proud: level with the door's
    # face, the two z-fought), and brass knobs.
    door_w, door_h = w / 2 - 0.035, STAND_H - 0.2
    for sx in (-1, 1):
        cx = sx * (w / 4 - 0.004)
        cz = -STAND_H / 2 - 0.01
        parts.append(bevelled_box("Door", (door_w, 0.02, door_h), 0.004, 2, wood, (cx, -d / 2 - 0.008, cz)))
        parts.append(bevelled_box("Panel", (door_w - 0.08, 0.012, door_h - 0.1), 0.004, 2, dark, (cx, -d / 2 - 0.016, cz)))
        parts.append(bevelled_box("Knob", (0.034, 0.036, 0.034), 0.016, 3, brass, (cx - sx * (door_w / 2 - 0.045), -d / 2 - 0.028, cz + 0.05)))
    for p in parts:
        if p.data.materials and p.data.materials[0].name.startswith("Wood"):
            box_uv(p, 1.5)
    return parts


def build():
    parts = _glass() + _seams() + _trim() + [_gravel()] + _stand()
    for p in parts:
        if not p.data.uv_layers:
            box_uv(p, 1.0)
    return [join(parts, "Tank")]
