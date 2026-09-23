"""The bedroom's furniture. Everything is placed from layout.py in Godot
coordinates (see G() and gbox() in lib/common.py)."""

import math

import bmesh
from mathutils import Matrix, Vector, noise

from lib.common import G, fill_colour, gbox, image_np, material, mesh_object, paint, shade_smooth, smoothstep
from lib.decor import bezier, ribbon, rng, tube

import layout as L


def mats():
    return {
        "wood": material("WoodLight", (0.72, 0.55, 0.38), roughness=0.55),
        "wood_dark": material("WoodDark", (0.42, 0.28, 0.18), roughness=0.6),
        "white": material("Furniture", (0.9, 0.89, 0.85), roughness=0.5),
        "black": material("Plastic", (0.08, 0.085, 0.09), roughness=0.45),
        "metal": material("Metal", (0.6, 0.62, 0.65), roughness=0.35, metallic=1.0),
        "fabric_teal": material("FabricTeal", (0.24, 0.52, 0.55), roughness=0.95),
        "fabric_cream": material("FabricCream", (0.93, 0.89, 0.8), roughness=0.95),
        "fabric_mustard": material("FabricMustard", (0.86, 0.64, 0.24), roughness=0.95),
        "fabric_rose": material("FabricRose", (0.82, 0.5, 0.52), roughness=0.95),
        "books": material("Books", roughness=0.7, vertex_color=True),
        "leaf": material("Leaf", (0.3, 0.58, 0.3), roughness=0.55),
        "pot": material("Pot", (0.8, 0.5, 0.36), roughness=0.8),
        "glow_warm": material("GlowWarm", (1.0, 0.86, 0.62), roughness=0.6),
        "screen_off": material("ScreenOff", (0.02, 0.02, 0.025), roughness=0.2),
        "rug": material("Rug", roughness=0.95, image=_rug_texture()),
        "hoodie": material("Hoodie", (0.36, 0.34, 0.55), roughness=0.95),
    }


def _rug_texture():
    import numpy as np

    h, w = 256, 384
    y, x = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    cream = np.array([0.9, 0.84, 0.72])
    terracotta = np.array([0.78, 0.42, 0.3])
    teal = np.array([0.24, 0.5, 0.52])
    img = np.ones((h, w, 3)) * cream
    border = (x < 0.06) | (x > 0.94) | (y < 0.09) | (y > 0.91)
    img[border] = terracotta
    inner = (np.abs(x - 0.5) < 0.38) & (np.abs(y - 0.5) < 0.33)
    diamond = (np.abs((x - 0.5) * 2.2) + np.abs((y - 0.5) * 3.0)) % 0.5 < 0.08
    img[inner & diamond] = teal
    img *= (0.95 + 0.05 * np.sin(x * 900) * np.sin(y * 700))[..., None]
    return image_np("RugPattern", img)


def _ybox(name, size, center, mat, bevel=0.006, segments=2, yaw=0.0, pivot=None):
    """gbox, optionally turned `yaw` degrees about the vertical axis at `pivot`."""
    obj = gbox(name, size, center, mat, bevel, segments)
    if yaw:
        p = G(*(pivot or center))
        obj.data.transform(Matrix.Translation(obj.location - p))
        obj.location = p
        obj.rotation_euler.z = math.radians(yaw)
    return obj


def desk(m):
    (x0, _, z0), (x1, top, z1) = L.DESK_MIN, L.DESK_MAX
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    parts = [gbox("DeskTop", (x1 - x0, 0.035, z1 - z0), (cx, top - 0.0175, cz), m["wood"], 0.008, 3)]
    for z in (z0 + 0.05, z1 - 0.05):
        parts.append(gbox("DeskSide", (x1 - x0 - 0.06, top - 0.035, 0.035), (cx + 0.02, (top - 0.035) / 2, z), m["white"], 0.006))
    # A drawer unit on the front end.
    parts.append(gbox("Drawers", (0.5, 0.55, 0.4), (cx + 0.05, 0.3, z1 - 0.3), m["white"], 0.008))
    for i, y in enumerate((0.44, 0.17)):
        parts.append(gbox("DrawerFront", (0.012, 0.22, 0.34), (cx - 0.205, y, z1 - 0.3), m["white"], 0.004))
        parts.append(gbox("DrawerPull", (0.02, 0.018, 0.12), (cx - 0.218, y + 0.06, z1 - 0.3), m["metal"], 0.006, 2))
    # A shelf on the wall above the monitor.
    parts.append(gbox("WallShelf", (0.24, 0.025, 1.1), (x1 - 0.12, 1.66, -1.2), m["wood"], 0.006))
    for z in (-1.65, -0.75):
        parts.append(gbox("ShelfBracket", (0.18, 0.12, 0.02), (x1 - 0.1, 1.6, z), m["black"], 0.004))
    return parts


def monitor(m):
    sx, sy, sz = L.SCREEN_CENTER
    w, h = L.SCREEN_SIZE
    parts = [
        gbox("MonitorBezel", (0.028, h + 0.03, w + 0.03), (sx + 0.016, sy, sz), m["black"], 0.006),
        gbox("MonitorScreen", (0.002, h, w), (sx + 0.001, sy, sz), m["screen_off"], 0.0),
        gbox("MonitorBack", (0.05, h * 0.6, w * 0.5), (sx + 0.05, sy, sz), m["black"], 0.02, 3),
        gbox("MonitorNeck", (0.04, 0.3, 0.06), (sx + 0.08, sy - 0.2, sz), m["black"], 0.01),
        gbox("MonitorFoot", (0.2, 0.014, 0.28), (sx + 0.06, L.DESK_MAX[1] + 0.007, sz), m["black"], 0.006),
    ]
    # Speakers either side, with round cones facing the room.
    for i, (x, y, z) in enumerate(L.SPEAKERS):
        parts.append(gbox("Speaker", (0.14, 0.25, 0.13), (x, y, z), m["black"], 0.01, 3))
        for dy, r in ((0.05, 0.04), (-0.06, 0.028)):
            bm = bmesh.new()
            bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=r, radius2=r * 0.6, depth=0.01)
            cone = mesh_object("Cone", bm, [m["metal"]])
            cone.data.transform(Matrix.Rotation(math.radians(90), 4, "Y"))
            cone.location = G(x - 0.072, y + dy, z)
            shade_smooth(cone, 40)
            parts.append(cone)
    # Keyboard and mouse in front of the monitor.
    parts.append(_ybox("Keyboard", (0.15, 0.02, 0.44), (1.58, L.DESK_MAX[1] + 0.01, -1.22), m["black"], 0.005, 2, yaw=0))
    parts.append(gbox("Mouse", (0.1, 0.03, 0.06), (1.58, L.DESK_MAX[1] + 0.015, -0.9), m["black"], 0.014, 3))
    parts.append(gbox("MousePad", (0.3, 0.003, 0.38), (1.6, L.DESK_MAX[1] + 0.0015, -0.9), m["fabric_teal"], 0.0))
    return parts


def chair(m):
    """A gaming chair rolled aside (out of the fish's view of the monitor),
    with a hoodie over its back."""
    cx, cz, yaw = 0.98, -0.32, 35.0  # its widest reach stays short of the desk at x 1.4
    parts = [
        _ybox("ChairSeat", (0.5, 0.1, 0.5), (cx, 0.5, cz), m["fabric_teal"], 0.04, 3, yaw, (cx, 0, cz)),
        _ybox("ChairBack", (0.1, 0.75, 0.48), (cx + 0.24, 0.93, cz), m["fabric_teal"], 0.05, 3, yaw, (cx, 0, cz)),
        _ybox("ChairArmL", (0.34, 0.04, 0.07), (cx, 0.72, cz - 0.27), m["black"], 0.015, 2, yaw, (cx, 0, cz)),
        _ybox("ChairArmR", (0.34, 0.04, 0.07), (cx, 0.72, cz + 0.27), m["black"], 0.015, 2, yaw, (cx, 0, cz)),
        gbox("ChairLift", (0.05, 0.36, 0.05), (cx, 0.26, cz), m["metal"], 0.02, 2),
    ]
    for i in range(5):
        a = math.tau * i / 5
        d = Vector((math.cos(a), math.sin(a), 0))
        leg = tube("ChairLeg", [G(cx, 0.08, cz), G(cx, 0.08, cz) + d * 0.3], 0.018, m["black"], sides=8)
        wheel = tube("Wheel", [G(cx, 0.03, cz) + d * 0.3 + Vector((0, 0.012, 0)), G(cx, 0.03, cz) + d * 0.3 - Vector((0, 0.012, 0))],
                     0.028, m["black"], sides=10)
        parts += [leg, wheel]
    # The hoodie: a soft sheet draped over the back, arms hanging.
    bm = bmesh.new()
    cols, rows = 10, 12
    grid = []
    for i in range(cols + 1):
        s = i / cols
        row = []
        for j in range(rows + 1):
            t = j / rows
            # Over the top, then down the front and back of the chair.
            ang = math.pi * t
            local = Vector((0.1 * math.cos(ang) + 0.03 * math.sin(s * 9), (s - 0.5) * 0.46, 1.33 - 0.25 * math.sin(ang) * 0 - 0.32 * (1 - math.sin(ang)) + 0.02 * math.sin(s * 7 + t * 5)))
            row.append(local)
        grid.append(row)
    verts = [[bm.verts.new(v) for v in row] for row in grid]
    for i in range(cols):
        for j in range(rows):
            bm.faces.new((verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]))
    hoodie = mesh_object("Hoodie", bm, [m["hoodie"]])
    # Local x is the chair's depth axis; put it over the back rest and turn with the chair.
    hoodie.data.transform(Matrix.Translation(Vector((0.24, 0, 0))))
    hoodie.location = G(cx, 0, cz)
    hoodie.rotation_euler.z = math.radians(yaw)
    shade_smooth(hoodie)
    parts.append(hoodie)
    return parts


def bed(m):
    (x0, _, z0), (x1, top, z1) = L.BED_MIN, L.BED_MAX
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    w, d = x1 - x0, z1 - z0
    parts = [
        gbox("BedFrame", (w, 0.28, d), (cx, 0.14, cz), m["wood"], 0.012, 2),
        gbox("Mattress", (w - 0.06, 0.18, d - 0.08), (cx, 0.37, cz + 0.02), m["fabric_cream"], 0.05, 4),
        gbox("Headboard", (w, 0.95, 0.06), (cx, 0.475, z0 - 0.03), m["wood"], 0.02, 3),
    ]
    # Duvet: a soft lumpy slab over the lower two-thirds.
    bm = bmesh.new()
    nx, nz = 14, 20
    grid = []
    for i in range(nx + 1):
        for_i = []
        for j in range(nz + 1):
            u, v = i / nx, j / nz
            x = x0 + 0.01 + (w - 0.02) * u
            z = z0 + 0.55 + (d - 0.55) * v
            edge = min(u, 1 - u) * 5
            y = top - 0.02 + 0.07 * min(edge, 1.0) ** 0.6 + 0.012 * noise.noise(Vector((u * 5, v * 7, 0.2)))
            if edge < 0.2:
                y -= 0.18 * (1 - edge / 0.2)  # hang over the sides
            for_i.append(bm.verts.new(G(x, y, z)))
        grid.append(for_i)
    for i in range(nx):
        for j in range(nz):
            bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))  # facing up
    duvet = mesh_object("Duvet", bm, [m["fabric_teal"]])
    shade_smooth(duvet)
    parts.append(duvet)
    # Pillows and a folded blanket at the foot.
    for x in (cx - 0.2, cx + 0.2):
        parts.append(gbox("Pillow", (0.36, 0.1, 0.24), (x, top + 0.05, z0 + 0.2), m["white"], 0.045, 4))
    parts.append(gbox("Blanket", (w - 0.02, 0.05, 0.32), (cx, top + 0.1, z1 - 0.25), m["fabric_mustard"], 0.02, 3))
    parts.append(gbox("BlanketFold", (w - 0.06, 0.04, 0.3), (cx, top + 0.145, z1 - 0.26), m["fabric_mustard"], 0.02, 3))
    return parts


def nightstand(m):
    x, y, z = L.BEDSIDE_LAMP
    parts = [
        gbox("Nightstand", (0.42, 0.5, 0.4), (x, 0.25, z), m["wood"], 0.01, 2),
        gbox("NightDrawer", (0.012, 0.16, 0.32), (x + 0.21, 0.36, z), m["wood_dark"], 0.004),
        gbox("LampBase", (0.1, 0.12, 0.1), (x, 0.56, z), m["pot"], 0.04, 3),
    ]
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=0.13, radius2=0.09, depth=0.16)
    shade = mesh_object("LampShade", bm, [m["glow_warm"]])
    shade.location = G(x, y, z)
    shade_smooth(shade, 40)
    parts.append(shade)
    return parts


def bookshelf(m):
    x0, x1, z0 = -2.07, -1.56, -1.78  # clear of the left curtain
    zc = z0 + 0.15
    cx = (x0 + x1) / 2
    parts = [gbox("ShelfSideL", (0.025, 1.8, 0.3), (x0 + 0.0125, 0.9, zc), m["white"], 0.004),
             gbox("ShelfSideR", (0.025, 1.8, 0.3), (x1 - 0.0125, 0.9, zc), m["white"], 0.004),
             gbox("ShelfBack", (x1 - x0, 1.8, 0.01), (cx, 0.9, z0 + 0.005), m["white"], 0.0)]
    levels = [0.02, 0.4, 0.78, 1.16, 1.54, 1.79]
    for y in levels:
        parts.append(gbox("Shelf", (x1 - x0 - 0.05, 0.022, 0.29), (cx, y, zc), m["white"], 0.004))
    # Books, leaning a little now and then.
    r = rng(12)
    colours = [(0.8, 0.3, 0.25), (0.25, 0.45, 0.7), (0.9, 0.75, 0.3), (0.3, 0.55, 0.4), (0.55, 0.35, 0.6),
               (0.92, 0.9, 0.85), (0.2, 0.22, 0.28), (0.85, 0.5, 0.3)]
    books = []
    for shelf in range(4):
        y = levels[shelf] + 0.011
        x = x0 + 0.04
        end = x1 - 0.04 - (0.18 if shelf in (1, 3) else 0.02)
        while x < end:
            t = r.uniform(0.02, 0.045)
            h = r.uniform(0.22, 0.32)
            if x + t > end:
                break
            b = gbox("Book", (t, h, r.uniform(0.17, 0.23)), (x + t / 2, y + h / 2, zc + 0.02), m["books"], 0.003, 1)
            col = r.choice(colours)
            paint(b, lambda co, n, col=col: (*col, 1.0))
            books.append(b)
            x += t + 0.002
    return parts + books


def beanbag(m):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=4, radius=0.42)
    for v in bm.verts:
        v.co.z *= 0.62
        if v.co.z < -0.15:
            v.co.z = -0.15 + (v.co.z + 0.15) * 0.2
        v.co += v.co.normalized() * 0.02 * noise.noise(v.co * 6.0)
        # A dent where someone sits.
        if v.co.z > 0.1 and v.co.x < 0.05:
            v.co.z -= 0.08 * smoothstep(0.1, 0.25, v.co.z)
    obj = mesh_object("Beanbag", bm, [m["fabric_mustard"]])
    obj.location = G(1.05, 0.17, 0.95)
    shade_smooth(obj)
    return [obj]


def rug(m):
    obj = gbox("Rug", (2.2, 0.012, 1.6), (-0.15, 0.006, 0.0), m["rug"], 0.004, 1)
    me = obj.data
    uv = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (co.x / 2.2 + 0.5, co.y / 1.6 + 0.5)
    return [obj]


def floor_lamp(m):
    x, y, z = L.FLOOR_LAMP
    parts = [gbox("LampFoot", (0.28, 0.02, 0.28), (x, 0.01, z), m["black"], 0.01, 2),
             tube("LampPole", [G(x, 0.02, z), G(x, y - 0.1, z)], 0.012, m["black"], sides=10)]
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=0.2, radius2=0.14, depth=0.26)
    shade = mesh_object("FloorLampShade", bm, [m["glow_warm"]])
    shade.location = G(x, y, z)
    shade_smooth(shade, 40)
    parts.append(shade)
    return parts


def houseplant(m, x, z, scale=1.0, seed=3):
    parts = []
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.12 * scale, radius2=0.16 * scale, depth=0.3 * scale)
    pot = mesh_object("PlantPot", bm, [m["pot"]])
    pot.location = G(x, 0.15 * scale, z)
    shade_smooth(pot, 40)
    parts.append(pot)
    r = rng(seed)
    for i in range(11):
        a = r.uniform(0, math.tau)
        out = Vector((math.cos(a), math.sin(a), 0))
        h = r.uniform(0.35, 0.8) * scale
        reach = r.uniform(0.12, 0.3) * scale
        base = G(x, 0.29 * scale, z)
        spine = bezier(base, base + Vector((0, 0, h * 0.6)), base + out * reach * 0.8 + Vector((0, 0, h)),
                       base + out * reach + Vector((0, 0, h * 0.85)), 14)
        widths = [0.006 * scale if k < 7 else 0.12 * scale * math.sin(math.pi * (k - 7) / 7) ** 0.7 + 0.004 for k in range(15)]
        leaf = ribbon("Leaf", spine, widths, m["leaf"], normal_hint=Vector((-math.sin(a), math.cos(a), 0)), fold=0.1)
        parts.append(leaf)
    return parts


def tripod(m):
    """The room camera on its tripod (the view the tank cam window shows)."""
    x, y, z = L.ROOM_CAMERA
    base = G(x, y - 0.06, z + 0.17)
    parts = []
    for i in range(3):
        a = math.tau * i / 3 + 0.5
        foot = G(x + math.cos(a) * 0.3, 0.0, z + 0.17 + math.sin(a) * 0.3)
        parts.append(tube("TripodLeg", [foot, base], 0.009, m["metal"], sides=8))
    parts += [
        gbox("CamBody", (0.12, 0.09, 0.16), (x, y, z + 0.17), m["black"], 0.012, 2),
        gbox("CamTally", (0.015, 0.015, 0.008), (x + 0.04, y + 0.035, z + 0.09), material("GlowTally", (1.0, 0.1, 0.1)), 0.004, 1),
    ]
    lens = tube("Lens", [G(x, y, z + 0.09), G(x, y, z + 0.02)], 0.036, m["metal"], sides=16)
    parts.append(lens)
    return parts


def build(m):
    parts = (desk(m) + monitor(m) + chair(m) + bed(m) + nightstand(m) + bookshelf(m) + beanbag(m) + rug(m)
             + floor_lamp(m) + houseplant(m, 0.92, -1.58) + tripod(m))
    for p in parts:
        if "Col" not in p.data.color_attributes:
            fill_colour(p)
    return parts
