"""Dressing: streamer gear, tidy gamer touches, cosy things and fish fandom.

Lived-in but looked after: no cans, no snack bags, cables kept neat.
Coordinates are Godot's (x right, y up, z toward the door), via G().
"""

import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

from lib.common import G, bevelled_box, fill_colour, gbox, image_np, material, mesh_object, paint, shade_smooth
from lib.decor import bezier, ribbon, rng, tube

import furniture
import layout as L


def mats():
    m = furniture.mats()
    m.update({
        "gold": material("Gold", (0.95, 0.72, 0.28), roughness=0.25, metallic=1.0),
        "ink_cream": material("InkCream", (0.98, 0.94, 0.84), roughness=0.6),
        "ink_yellow": material("InkYellow", (1.0, 0.83, 0.2), roughness=0.6),
        "orange": material("PlushOrange", (1.0, 0.52, 0.16), roughness=0.95),
        "rgb": material("GlowRGB", (0.62, 0.3, 1.0), roughness=0.5),
        "fairy": material("GlowFairy", (1.0, 0.82, 0.5), roughness=0.4),
        "ring": material("GlowRing", (1.0, 0.98, 0.95), roughness=0.4),
        "chat": material("GlowChat", roughness=0.3, image=_chat_image()),
        "mug": material("Mug", (0.95, 0.93, 0.9), roughness=0.3),
        "poster_fish": material("PosterTortellini", roughness=0.7, image=_poster_tortellini()),
        "poster_gud": material("PosterGitGud", roughness=0.7, image=_poster_git_gud()),
        "poster_pixel": material("PosterPixel", roughness=0.7, image=_poster_pixel()),
    })
    return m


# --- placement helpers ---------------------------------------------------------

def _face(obj, center, facing):
    """Turns an object built in local XY (facing local +Z) to face `facing`
    (a Godot x/z direction) and moves it to `center` (Godot)."""
    dx, dz = facing
    local = obj.location.copy()
    obj.rotation_euler = (math.radians(90), 0.0, math.atan2(dx, dz))
    obj.location = G(*center) + obj.rotation_euler.to_matrix() @ local
    return obj


def _quad(name, w, h, mat, z=0.0):
    bm = bmesh.new()
    vs = [bm.verts.new((-w / 2, -h / 2, z)), bm.verts.new((w / 2, -h / 2, z)),
          bm.verts.new((w / 2, h / 2, z)), bm.verts.new((-w / 2, h / 2, z))]
    bm.faces.new(vs)
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop, co in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv].uv = co
    return mesh_object(name, bm, [mat])


def _text(name, body, size, mat, x=0.0, y=0.0, z=0.001, extrude=0.001):
    """Text as a mesh in local XY (facing +Z), centred on (x, y)."""
    curve = bpy.data.curves.new(name, "FONT")
    curve.body = body
    curve.size = size
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.extrude = extrude
    curve.offset = size * 0.02  # a touch bolder
    tmp = bpy.data.objects.new(name, curve)
    bpy.context.scene.collection.objects.link(tmp)
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(tmp, do_unlink=True)
    me.transform(Matrix.Translation((x, y, z + extrude)))
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    me.materials.clear()
    me.materials.append(mat)
    # Lettering takes its lightmap from the surface under it (moods._decal_uvs).
    decal = me.attributes.new("Decal", "INT", "FACE")
    decal.data.foreach_set("value", [1] * len(me.polygons))
    return obj


def _poster(name, w, h, mat, center, facing, frame_mat, texts=()):
    """A framed poster on a wall: frame, picture and any lettering, as one."""
    parts = [bevelled_box(name + "Frame", (w + 0.04, h + 0.04, 0.02), 0.004, 1, frame_mat, (0, 0, -0.01)),
             _quad(name, w, h, mat, 0.0008)]
    for body, size, ink, y in texts:
        parts.append(_text(name + "Text", body, size, ink, 0.0, y))
    for p in parts:
        _face(p, center, facing)
    return parts


def _ball(name, center, radii, mat, subdivisions=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * radii[0], v.co.y * radii[2], v.co.z * radii[1]))
    obj = mesh_object(name, bm, [mat])
    obj.location = G(*center)
    shade_smooth(obj)
    return obj


def _cylinder(name, center, radius, height, mat, segments=20, radius_top=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius,
                          radius2=radius if radius_top is None else radius_top, depth=height)
    obj = mesh_object(name, bm, [mat])
    obj.location = G(*center)
    shade_smooth(obj, 40)
    return obj


def _lathe(name, profile, center, mat, segments=24):
    """A turned shape from (radius, height) pairs, bottom to top."""
    bm = bmesh.new()
    rings = []
    for r, y in profile:
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), y))
                      for a in (math.tau * i / segments for i in range(segments))])
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    obj = mesh_object(name, bm, [mat])
    obj.location = G(*center)
    shade_smooth(obj, 50)
    return obj


def _yawed(objs, pivot, yaw_deg):
    """Turns already-placed objects about the vertical axis through `pivot`."""
    p = G(*pivot)
    rot = Matrix.Translation(p) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z") @ Matrix.Translation(-p)
    for o in objs:
        # matrix_basis, not matrix_world: the latter isn't updated from a
        # freshly set location until the scene is evaluated.
        o.matrix_basis = rot @ o.matrix_basis
    return objs


def _paint_flat(obj, colour):
    paint(obj, lambda co, n: (*colour, 1.0))
    return obj


# --- pictures ------------------------------------------------------------------

def _grid(h, w):
    ys, xs = np.mgrid[0:h, 0:w]
    return xs / w, ys / h  # 0..1, top-left origin


def _disc(xs, ys, cx, cy, r, aspect=1.0):
    return ((xs - cx) * aspect) ** 2 + (ys - cy) ** 2 < r * r


def _fish(img, xs, ys, cx, cy, s, aspect, body=(1.0, 0.5, 0.12), belly=(1.0, 0.78, 0.45)):
    """Tortellini, cartoon style, facing right."""
    ex, ey = (xs - cx) * aspect / s, (ys - cy) / s
    shape = (ex / 1.0) ** 2 + (ey / 0.62) ** 2 < 1
    tail = (ex < -0.75) & (ex > -1.55) & (np.abs(ey) < (-0.75 - ex) * 0.95 + 0.05) & ~((ex < -1.25) & (np.abs(ey) < (ex + 1.55) * 1.2))
    dorsal = (ey < -0.45) & (ey > -0.95) & (ex > -0.45) & (ex < 0.35) & (ey > -0.45 - (0.35 - ex) * 0.75)
    fin = ((ex + 0.05) ** 2 / 0.09 + (ey - 0.5) ** 2 / 0.03) < 1
    img[tail | dorsal | fin] = [c * 0.9 for c in body]
    img[shape] = body
    img[shape & (ey > 0.18)] = belly
    img[(ex - 0.5) ** 2 + (ey + 0.08) ** 2 < 0.19 ** 2] = (1, 1, 1)
    img[(ex - 0.55) ** 2 + (ey + 0.06) ** 2 < 0.1 ** 2] = (0.05, 0.05, 0.08)
    img[(ex - 0.58) ** 2 + (ey + 0.1) ** 2 < 0.035 ** 2] = (1, 1, 1)
    img[(ex - 0.42) ** 2 / 0.02 + (ey - 0.18) ** 2 / 0.005 < 1] = (1.0, 0.45, 0.45)  # blush
    smile = (np.abs(np.hypot(ex - 0.78, ey - 0.12) - 0.12) < 0.025) & (ey > 0.14)
    img[smile] = (0.35, 0.12, 0.05)


def _poster_tortellini():
    h, w = 512, 366
    xs, ys = _grid(h, w)
    img = np.zeros((h, w, 3))
    img[:] = (1 - ys[..., None]) * np.array([0.2, 0.55, 0.62]) + ys[..., None] * np.array([0.07, 0.24, 0.38])
    rays = (np.sin((xs - 0.3) / (ys + 0.3) * 18) > 0.6) & (ys < 0.7)
    img[rays] += np.array([0.06, 0.08, 0.06]) * (1 - ys[rays, None] / 0.7)
    r = np.random.default_rng(4)
    for _ in range(14):
        cx, cy, rad = r.uniform(0.05, 0.95), r.uniform(0.05, 0.75), r.uniform(0.01, 0.035)
        ring = np.abs(np.hypot((xs - cx) * w / h, ys - cy) - rad) < 0.004
        img[ring] = (0.75, 0.92, 0.95)
    _fish(img, xs, ys, 0.57, 0.42, 0.2, w / h)
    # A little crown: every fan's favourite.
    ex, ey = (xs - 0.6) * w / h, ys - 0.27
    crown = (ey < 0) & (ey > -0.07) & (np.abs(ex) < 0.07) & ((ey > -0.035) | (np.abs(((ex + 0.07) % 0.047) - 0.0235) < (ey + 0.07) * 0.5))
    img[crown] = (1.0, 0.82, 0.25)
    img[ys > 0.8] = (0.95, 0.5, 0.2)
    img[(ys > 0.8) & (ys < 0.81)] = (0.98, 0.9, 0.7)
    return image_np("PosterTortellini", np.clip(img, 0, 1))


def _poster_git_gud():
    h, w = 512, 366
    xs, ys = _grid(h, w)
    img = np.zeros((h, w, 3))
    sky = ys < 0.62
    t = (ys / 0.62)[..., None]
    img[:] = (1 - t) * np.array([0.12, 0.05, 0.25]) + t * np.array([0.85, 0.25, 0.55])
    # The sun, striped.
    sun = _disc(xs, ys, 0.5, 0.5, 0.26, w / h) & sky
    stripes = (ys > 0.48) & (((ys - 0.48) * 60) % 2 < ((ys - 0.48) * 12))
    img[sun] = (1 - t[sun]) * np.array([1.0, 0.85, 0.3]) + t[sun] * np.array([1.0, 0.35, 0.45])
    img[sun & stripes] = (1 - t[sun & stripes]) * np.array([0.12, 0.05, 0.25]) + t[sun & stripes] * np.array([0.85, 0.25, 0.55])
    # A perspective grid below the horizon.
    ground = ~sky
    img[ground] = (0.08, 0.02, 0.15)
    d = (ys - 0.62) + 0.02
    lines = (np.abs(((xs - 0.5) / d * 0.08 + 0.5) % 0.1 - 0.05) < 0.006 / d * 0.08) | (np.abs(((0.05 / d) % 1.0) - 0.5) < 0.06)
    img[ground & lines] = (0.95, 0.35, 0.85)
    # Tortellini leaping over the sun.
    _fish(img, xs, ys, 0.5, 0.36, 0.13, w / h)
    img[np.abs(ys - 0.62) < 0.003] = (1.0, 0.6, 0.9)
    return image_np("PosterGitGud", np.clip(img, 0, 1))


PIXEL_FISH = [
    "................",
    "......oooo......",
    ".....oOOOOo.....",
    "o...oOOOOOOoo...",
    "oo.oOOOOOOwkOo..",
    "oOoOOOOOOOwwOOo.",
    "oOOOOOOOOOOOOOr.",
    "oOoOOOOOyyyOOo..",
    "oo.oOOOyyyyOo...",
    "o...ooOOOOoo....",
    ".......oo.......",
    "................",
]


def _poster_pixel():
    n = 256
    img = np.zeros((n, n, 3))
    img[:] = (0.1, 0.12, 0.3)
    xs, ys = _grid(n, n)
    check = ((xs * 16).astype(int) + (ys * 16).astype(int)) % 2 == 0
    img[check] = (0.12, 0.15, 0.36)
    pal = {"o": (0.75, 0.3, 0.05), "O": (1.0, 0.55, 0.12), "w": (1, 1, 1), "k": (0.05, 0.05, 0.1),
           "r": (1.0, 0.35, 0.4), "y": (1.0, 0.82, 0.4)}
    cell = 10
    x0, y0 = (n - 16 * cell) // 2, 40
    for j, row in enumerate(PIXEL_FISH):
        for i, c in enumerate(row):
            if c in pal:
                img[y0 + j * cell:y0 + (j + 1) * cell, x0 + i * cell:x0 + (i + 1) * cell] = pal[c]
    # Hearts on either side.
    for hx in (0.15, 0.85):
        heart = (_disc(xs, ys, hx - 0.025, 0.2, 0.03) | _disc(xs, ys, hx + 0.025, 0.2, 0.03)
                 | ((ys > 0.2) & (ys < 0.27) & (np.abs(xs - hx) < (0.27 - ys) * 0.8)))
        img[heart] = (1.0, 0.4, 0.55)
    return image_np("PosterPixel", img)


def _chat_image():
    """The second monitor: a stream chat, faked with bars for words."""
    h, w = 500, 280
    img = np.zeros((h, w, 3))
    img[:] = (0.09, 0.09, 0.12)
    img[:34] = (0.2, 0.14, 0.34)
    img[12:22, 14:90] = (0.9, 0.88, 0.95)
    r = np.random.default_rng(9)
    names = [(0.55, 0.8, 1.0), (1.0, 0.6, 0.35), (0.6, 1.0, 0.6), (1.0, 0.5, 0.75), (1.0, 0.85, 0.4), (0.7, 0.6, 1.0)]
    y = 48
    while y < h - 60:
        x = 12
        colour = names[r.integers(len(names))]
        nw = int(r.integers(30, 70))
        img[y:y + 9, x:x + nw] = colour
        x += nw + 8
        lines = int(r.integers(1, 3))
        for _ in range(lines):
            while True:
                word = int(r.integers(10, 38))
                if x + word > w - 12:
                    break
                if r.random() < 0.08:
                    img[y - 2:y + 11, x:x + 13] = (1.0, 0.55, 0.15)  # a fish emote
                    img[y + 2:y + 5, x + 9:x + 11] = (0.05, 0.05, 0.05)
                    x += 19
                    continue
                img[y + 1:y + 8, x:x + word] = (0.78, 0.78, 0.82)
                x += word + 6
            y += 16
            x = 12
        y += 8
    img[h - 44:h - 12, 10:w - 10] = (0.16, 0.16, 0.2)
    img[h - 32:h - 24, 20:110] = (0.4, 0.4, 0.46)
    return image_np("ChatScreen", img)


# --- streamer gear -------------------------------------------------------------

def mic_arm(m):
    # Clamped beside the monitor and swung out to its right, clear of the
    # fish's view of the screen.
    pts = [G(2.07, 0.8, -0.58), G(2.05, 1.36, -0.58), G(1.76, 1.22, -0.62), G(1.74, 1.15, -0.62)]
    parts = [gbox("MicClamp", (0.05, 0.08, 0.05), (2.07, 0.75, -0.58), m["black"], 0.006),
             tube("MicRiser", [pts[0], pts[1]], 0.011, m["black"], sides=8),
             tube("MicArm", [pts[1], pts[2]], 0.011, m["black"], sides=8),
             tube("MicDrop", [pts[2], pts[3]], 0.008, m["black"], sides=8),
             _ball("MicSpring", (2.05, 1.36, -0.58), (0.02, 0.02, 0.02), m["metal"], 1)]
    parts.append(tube("Mic", [G(1.74, 1.15, -0.62), G(1.73, 0.99, -0.615)], 0.027, m["black"], sides=16,
                      radius_fn=lambda t: 1.0 if t < 0.55 else 0.85))
    parts.append(_ball("MicGrille", (1.74, 1.12, -0.62), (0.03, 0.045, 0.03), m["metal"], 2))
    return parts


def webcam(m):
    sx, sy, sz = L.SCREEN_CENTER
    top = sy + L.SCREEN_SIZE[1] / 2 + 0.015
    return [gbox("Webcam", (0.04, 0.035, 0.1), (sx + 0.01, top + 0.02, sz), m["black"], 0.01, 2),
            tube("WebcamLens", [G(sx - 0.01, top + 0.02, sz), G(sx - 0.016, top + 0.02, sz)], 0.012, m["metal"], sides=12)]


def ring_light(m):
    x, z = 1.88, 0.42
    y = 1.5
    facing = (-0.85, -0.53)
    parts = [_cylinder("RingFoot", (x, 0.012, z), 0.16, 0.024, m["black"], 16),
             tube("RingPole", [G(x, 0.02, z), G(x, y - 0.22, z)], 0.012, m["black"], sides=8)]
    ring = [Vector((math.cos(a) * 0.2, math.sin(a) * 0.2, 0)) for a in (math.tau * i / 36 for i in range(37))]
    band = tube("RingLight", ring, 0.018, m["ring"], sides=10, closed_ends=False)
    _face(band, (x, y, z), facing)
    parts.append(band)
    phone = bevelled_box("RingPhone", (0.075, 0.15, 0.008), 0.004, 1, m["black"], (0, 0, 0.005))
    _face(phone, (x, y, z), facing)
    parts.append(phone)
    return parts


def stream_deck(m):
    x, y, z = 1.6, L.DESK_MAX[1], -0.56
    parts = [gbox("StreamDeck", (0.085, 0.024, 0.13), (x, y + 0.012, z), m["black"], 0.006)]
    keys = []
    r = rng(5)
    colours = [(0.3, 0.7, 1.0), (1.0, 0.5, 0.2), (0.5, 1.0, 0.55), (1.0, 0.4, 0.7), (0.9, 0.9, 0.95), (1.0, 0.85, 0.3)]
    for i in range(3):
        for j in range(5):
            k = gbox("DeckKey", (0.017, 0.006, 0.017), (x - 0.025 + i * 0.025, y + 0.026, z - 0.05 + j * 0.025), m["books"], 0.002, 1)
            keys.append(_paint_flat(k, r.choice(colours)))
    return parts + keys


def chat_monitor(m):
    x, y, z = L.CHAT_SCREEN
    facing = (-0.9, -0.42)
    w, h = 0.28, 0.48
    parts = [bevelled_box("ChatBezel", (w + 0.024, h + 0.024, 0.024), 0.005, 1, m["black"], (0, 0, -0.013)),
             _quad("ChatScreen", w, h, m["chat"], 0.0008),
             bevelled_box("ChatBack", (0.12, 0.2, 0.04), 0.01, 2, m["black"], (0, 0, -0.04))]
    for p in parts:
        _face(p, (x, y, z), facing)
    parts += [tube("ChatNeck", [G(x + 0.05, L.DESK_MAX[1], z - 0.02), G(x + 0.04, y - 0.1, z - 0.02)], 0.018, m["black"], sides=10),
              _cylinder("ChatFoot", (x + 0.05, L.DESK_MAX[1] + 0.006, z - 0.02), 0.08, 0.012, m["black"])]
    return parts


def headphones(m):
    x, y, z = 1.93, L.DESK_MAX[1], -0.12
    top = y + 0.33
    parts = [_cylinder("HeadStandFoot", (x, y + 0.008, z), 0.06, 0.016, m["black"]),
             tube("HeadStandPole", [G(x, y + 0.01, z), G(x, top, z)], 0.01, m["black"], sides=8),
             gbox("HeadStandTop", (0.04, 0.02, 0.12), (x, top + 0.01, z), m["black"], 0.008)]
    arc = [G(x, top - 0.06 + math.sin(a) * 0.08, z + math.cos(a) * 0.09) for a in (math.pi * i / 16 for i in range(17))]
    parts.append(tube("HeadBand", arc, 0.012, m["black"], sides=8))
    for side in (-1, 1):
        cup = tube("EarCup", [G(x, top - 0.1, z + side * 0.078), G(x, top - 0.1, z + side * 0.112)], 0.045, m["fabric_teal"], sides=18)
        parts.append(cup)
    return parts


def rgb_strip(m):
    x, y, _ = L.RGB_STRIP
    return [gbox("RGBStrip", (0.012, 0.012, 3.0), (x + 0.035, y, -0.28), m["rgb"], 0.003, 1),
            # A backlight behind the monitor.
            gbox("BiasLight", (0.01, 0.34, 0.012), (L.BIAS_LIGHT[0] - 0.08, L.BIAS_LIGHT[1], L.BIAS_LIGHT[2] - 0.3), m["rgb"], 0.003, 1),
            gbox("BiasLight", (0.01, 0.34, 0.012), (L.BIAS_LIGHT[0] - 0.08, L.BIAS_LIGHT[1], L.BIAS_LIGHT[2] + 0.3), m["rgb"], 0.003, 1)]


def cables(m):
    """One neat cable run: desk to wall socket, clipped along the skirting."""
    pts = bezier(G(2.07, 0.74, -0.2), G(2.08, 0.4, -0.2), G(2.08, 0.15, -0.1), G(2.08, 0.12, 0.08), 12)
    return [tube("Cable", pts, 0.006, m["black"], sides=6),
            gbox("Socket", (0.012, 0.08, 0.08), (2.095, 0.3, 0.12), m["white"], 0.003)]


# --- tidy gamer bits -----------------------------------------------------------

def controller(m, center, yaw):
    x, y, z = center
    parts = [gbox("PadBody", (0.06, 0.03, 0.12), (x, y + 0.016, z), m["black"], 0.012, 3)]
    for side in (-1, 1):
        grip = _ball("PadGrip", (x - 0.03, y + 0.02, z + side * 0.055), (0.042, 0.022, 0.028), m["black"], 2)
        parts.append(grip)
        parts.append(_cylinder("PadStick", (x + 0.005 * side - 0.01, y + 0.035, z + side * 0.03), 0.011, 0.012, m["metal"], 10))
    for i, colour in enumerate([(0.3, 0.9, 0.4), (1.0, 0.35, 0.3), (0.35, 0.6, 1.0), (1.0, 0.85, 0.3)]):
        a = math.tau * i / 4
        b = _ball("PadButton", (x + 0.012 + math.cos(a) * 0.01, y + 0.034, z + 0.045 + math.sin(a) * 0.01), (0.005, 0.004, 0.005), m["books"], 1)
        parts.append(_paint_flat(b, colour))
    return _yawed(parts, center, yaw)


def game_shelf(m):
    """Game boxes, a trophy and the fish food on the shelf over the desk."""
    y = 1.66 + 0.0125
    r = rng(21)
    colours = [(0.15, 0.35, 0.8), (0.85, 0.15, 0.15), (0.1, 0.55, 0.3), (0.95, 0.95, 0.95), (0.1, 0.1, 0.12), (0.9, 0.6, 0.1)]
    parts = []
    z = -1.72
    for i in range(9):
        box = gbox("GameCase", (0.135, 0.17, 0.014), (1.99, y + 0.085, z), m["books"], 0.002, 1)
        parts.append(_paint_flat(box, r.choice(colours)))
        z += 0.017
    # A small lying stack.
    for i in range(3):
        box = gbox("GameCase", (0.135, 0.014, 0.17), (1.99, y + 0.007 + i * 0.0145, -1.4), m["books"], 0.002, 1)
        parts.append(_paint_flat(box, r.choice(colours)))
    # "Best Fish 2026": a trophy for being the best fish.
    parts.append(gbox("TrophyBase", (0.08, 0.04, 0.08), (1.99, y + 0.02, -0.82), m["wood_dark"], 0.004))
    parts.append(_lathe("Trophy", [(0.015, 0), (0.012, 0.05), (0.02, 0.07), (0.05, 0.1), (0.055, 0.15), (0.05, 0.155)],
                        (1.99, y + 0.04, -0.82), m["gold"]))
    for side in (-1, 1):
        handle = [G(1.99, y + 0.17 - math.sin(a) * 0.03, -0.82 + side * (0.05 + math.sin(a) * 0.025))
                  for a in (math.pi * i / 8 for i in range(9))]
        parts.append(tube("TrophyHandle", handle, 0.004, m["gold"], sides=6, closed_ends=False))
    plaque = _text("TrophyText", "#1 FISH", 0.012, m["gold"], 0, 0, 0.0)
    _face(plaque, (1.949, y + 0.02, -0.82), (-1, 0))
    parts.append(plaque)
    return parts


def fish_food(m):
    x, y, z = 1.68, L.DESK_MAX[1], -1.66
    return [_cylinder("FishFood", (x, y + 0.05, z), 0.035, 0.1, m["mug"], 20),
            _cylinder("FishFoodLid", (x, y + 0.105, z), 0.037, 0.014, m["orange"], 20),
            _cylinder("FishFoodLabel", (x, y + 0.05, z), 0.0355, 0.05, m["pot"], 20)]


def mug(m):
    x, y, z = 1.52, L.DESK_MAX[1], -1.55
    parts = [_lathe("Mug", [(0.034, 0), (0.037, 0.005), (0.038, 0.095), (0.034, 0.095), (0.033, 0.01), (0.001, 0.01)],
                    (x, y, z), m["mug"], 24)]
    handle = [G(x + 0.036 + math.sin(a) * 0.028, y + 0.05 + math.cos(a) * 0.028, z) for a in (math.pi * i / 10 for i in range(11))]
    parts.append(tube("MugHandle", handle, 0.006, m["mug"], sides=8, closed_ends=False))
    words = _text("MugText", "WORLD'S BEST\nFISH", 0.011, m["orange"], 0, 0, 0.0)
    _face(words, (x - 0.039, y + 0.05, z), (-1, 0))
    parts.append(words)
    return parts


# --- cosy touches --------------------------------------------------------------

def fairy_lights(m):
    parts = []
    x0, x1 = L.WINDOW_CENTER_X - L.WINDOW_WIDTH / 2 - 0.25, L.WINDOW_CENTER_X + L.WINDOW_WIDTH / 2 + 0.25
    z = L.ROOM_MIN[2] + 0.12
    y = L.FAIRY_WINDOW_Y
    swags = 5
    for s in range(swags):
        a, b = x0 + (x1 - x0) * s / swags, x0 + (x1 - x0) * (s + 1) / swags
        pts = [G(a + (b - a) * t, y - 0.09 * math.sin(math.pi * t), z) for t in (i / 12 for i in range(13))]
        parts.append(tube("FairyWire", pts, 0.0025, m["black"], sides=4, closed_ends=False))
        for i in range(1, 6):
            t = i / 6
            parts.append(_ball("FairyBulb", (a + (b - a) * t, y - 0.09 * math.sin(math.pi * t) - 0.012, z), (0.011, 0.014, 0.011), m["fairy"], 1))
    return parts


def trailing_plant(m, x, y, z, seed=8):
    """A pothos on the bookshelf, trailing over the front edge."""
    parts = [_cylinder("SmallPot", (x, y + 0.06, z), 0.08, 0.12, m["pot"], 20, 0.09)]
    r = rng(seed)
    for i in range(7):
        a = r.uniform(-1.2, 1.2)
        length = r.uniform(0.25, 0.7)
        start = G(x, y + 0.12, z)
        out = Vector((math.sin(a) * 0.5, -math.cos(a) * 0.1, 0))  # mostly along x, a little forward
        forward = G(0, 0, 1) * 0.16
        vine = bezier(start, start + forward + out * 0.12 + Vector((0, 0, 0.05)), start + forward * 1.2 + out * 0.2,
                      start + forward * 1.1 + out * 0.22 - Vector((0, 0, length)), 14)
        parts.append(tube("Vine", vine, 0.003, m["leaf"], sides=4, closed_ends=False))
        for k in range(3, 15, 2):
            p = vine[k]
            leaf = ribbon("PothosLeaf", [p, p + Vector((r.uniform(-0.03, 0.03), -0.035, -0.01)), p + Vector((0, -0.06, -0.02))],
                          [0.005, 0.045, 0.004], m["leaf"], normal_hint=Vector((0, 0, 1)))
            parts.append(leaf)
    return parts


def succulent(m, x, y, z, seed=2):
    parts = [_cylinder("Succulent", (x, y + 0.04, z), 0.045, 0.08, m["pot"], 16, 0.05)]
    r = rng(seed)
    for i in range(9):
        a = math.tau * i / 9 + r.uniform(0, 0.3)
        tip = G(x + math.cos(a) * 0.05, y + 0.12 + r.uniform(0, 0.03), z + math.sin(a) * 0.05)
        parts.append(ribbon("SucculentLeaf", [G(x, y + 0.08, z), (G(x, y + 0.08, z) + tip) / 2 + Vector((0, 0, 0.01)), tip],
                            [0.012, 0.028, 0.004], m["leaf"], normal_hint=Vector((math.cos(a), -math.sin(a), 0)), fold=0.2))
    return parts


def slippers(m):
    parts = []
    for i, (x, z, yaw) in enumerate(((-0.95, 0.42, 12), (-0.93, 0.58, 20))):
        body = gbox("Slipper", (0.26, 0.05, 0.1), (x, 0.037, z), m["fabric_rose"], 0.022, 3)
        parts += _yawed([body], (x, 0, z), yaw)
    return parts


# --- fish fandom ---------------------------------------------------------------

def posters(m):
    frame = m["black"]
    parts = _poster("PosterTortellini", 0.6, 0.84, m["poster_fish"], (L.ROOM_MIN[0] + 0.011, 1.55, 0.02), (1, 0), m["white"],
                    [("TORTELLINI", 0.075, m["ink_cream"], -0.34)])
    parts += _poster("PosterGitGud", 0.5, 0.7, m["poster_gud"], (0.3, 1.6, L.ROOM_MAX[2] - 0.011), (0, -1), frame,
                     [("GIT GUD", 0.1, m["ink_yellow"], 0.27)])
    parts += _poster("PosterPixel", 0.42, 0.42, m["poster_pixel"], (L.ROOM_MAX[0] - 0.011, 1.5, 0.9), (-1, 0), frame,
                     [("#1 FISH", 0.055, m["ink_yellow"], -0.14)])
    return parts


def plush(m):
    """A goldfish plush lying on the duvet, looking at the room."""
    x, y, z = -1.6, 0.64, -0.1
    o = m["orange"]
    parts = [_ball("PlushBody", (x, y, z), (0.08, 0.09, 0.13), o, 3),
             # A big soft fan tail, a dorsal fin and two little side fins.
             _ball("PlushTail", (x, y + 0.03, z - 0.17), (0.018, 0.08, 0.07), o, 2),
             _ball("PlushDorsal", (x, y + 0.09, z - 0.01), (0.014, 0.035, 0.06), o, 2)]
    for side in (-1, 1):
        parts.append(_ball("PlushFin", (x + side * 0.08, y - 0.03, z + 0.02), (0.012, 0.025, 0.045), o, 1))
        parts.append(_ball("PlushEye", (x + side * 0.058, y + 0.025, z + 0.07), (0.018, 0.018, 0.012), m["black"], 1))
    parts.append(_ball("PlushMouth", (x, y - 0.01, z + 0.128), (0.02, 0.012, 0.008), m["fabric_rose"], 1))
    return _yawed(parts, (x, y, z), 60)


def build(m):
    shelf_x = (-2.07 - 1.56) / 2
    parts = (mic_arm(m) + webcam(m) + ring_light(m) + stream_deck(m) + chat_monitor(m) + headphones(m) + rgb_strip(m)
             + cables(m) + controller(m, (1.6, L.DESK_MAX[1], -0.3), -20) + game_shelf(m) + fish_food(m) + mug(m)
             + fairy_lights(m) + trailing_plant(m, shelf_x, 1.8, -1.66) + succulent(m, -1.66, 0.4 + 0.011, -1.66)
             + slippers(m) + posters(m) + plush(m)
             + furniture.houseplant(m, 0.62, 1.55, 1.15, seed=11))
    for p in parts:
        if "Col" not in p.data.color_attributes:
            fill_colour(p)
    return parts
