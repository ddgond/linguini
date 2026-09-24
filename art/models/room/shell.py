"""The room's shell: floor, ceiling, walls with a window opening in the back
wall and a door in the front wall, skirting, window frame, sill, curtains, and
the ceiling light."""

import math

import bmesh
from mathutils import Vector, noise

from lib.common import G, fill_colour, gbox, image_np, material, mesh_object, paint, shade_smooth

import layout as L


def _floor_texture():
    import numpy as np

    h, w = 512, 512
    y, x = np.mgrid[0:h, 0:w] / np.array([h, w])[:, None, None]
    # Planks along X, 8 across the texture, each a slightly different tone.
    plank = np.floor(y * 8)
    rng = np.random.default_rng(3)
    tones = rng.uniform(0.88, 1.08, 64)
    offsets = rng.uniform(0, 1, 64)
    tone = tones[plank.astype(int) % 64]
    shift = offsets[plank.astype(int) % 64]
    grain = 0.94 + 0.06 * np.sin((x * 3 + shift) * 40 + np.sin(y * 90) * 1.5)
    seam = np.minimum(np.abs((y * 8) % 1 - 0.0), np.abs((y * 8) % 1 - 1.0)) < 0.025
    end = np.abs(((x + shift * 0.7) * 2) % 1) < 0.006
    base = np.array([0.62, 0.44, 0.3])
    k = tone * grain * np.where(seam | end, 0.72, 1.0)
    return image_np("FloorPlanks", base[None, None, :] * k[..., None])


def _wall_with_window(mat):
    """The back wall as four boxes around the window opening."""
    x0, _, z = L.ROOM_MIN[0], 0, L.ROOM_MIN[2]
    x1 = L.ROOM_MAX[0]
    h = L.ROOM_MAX[1]
    t = L.WALL
    wz = z - t / 2
    # The opening's edges stop inside the window frame (0.06 thick) and the
    # sill, so no wall face is coplanar with theirs.
    wl = L.WINDOW_CENTER_X - L.WINDOW_WIDTH / 2 - 0.03
    wr = L.WINDOW_CENTER_X + L.WINDOW_WIDTH / 2 + 0.03
    low = L.WINDOW_SILL - 0.0175
    top = L.WINDOW_TOP + 0.03
    parts = [
        # The ends run on past the side walls' thickness, closing the corners
        # (an open corner column let the sun and sky leak into the bake).
        gbox("BackWallL", (wl - x0 + t, h, t), ((x0 - t + wl) / 2, h / 2, wz), mat, 0.0),
        gbox("BackWallR", (x1 + t - wr, h, t), ((wr + x1 + t) / 2, h / 2, wz), mat, 0.0),
        gbox("BackWallLow", (wr - wl, low, t), (L.WINDOW_CENTER_X, low / 2, wz), mat, 0.0),
        gbox("BackWallHigh", (wr - wl, h - top, t), (L.WINDOW_CENTER_X, (h + top) / 2, wz), mat, 0.0),
    ]
    return parts


def _front_wall_with_door(mat):
    x0, x1 = L.ROOM_MIN[0], L.ROOM_MAX[0]
    h = L.ROOM_MAX[1]
    t = L.WALL
    wz = L.ROOM_MAX[2] + t / 2
    dl = L.DOOR_CENTER_X - L.DOOR_WIDTH / 2
    dr = L.DOOR_CENTER_X + L.DOOR_WIDTH / 2
    return [
        gbox("FrontWallL", (dl - x0 + t, h, t), ((x0 - t + dl) / 2, h / 2, wz), mat, 0.0),
        gbox("FrontWallR", (x1 + t - dr, h, t), ((dr + x1 + t) / 2, h / 2, wz), mat, 0.0),
        gbox("FrontWallHigh", (dr - dl, h - L.DOOR_HEIGHT, t), (L.DOOR_CENTER_X, (h + L.DOOR_HEIGHT) / 2, wz), mat, 0.0),
    ]


def _curtain(name, x_center, width, mat):
    """A gathered curtain: a vertical sheet with soft folds."""
    bm = bmesh.new()
    cols, rows = 24, 10
    top, bottom = L.WINDOW_TOP + 0.12, 0.9
    z = L.ROOM_MIN[2] + 0.07
    grid = []
    for i in range(cols + 1):
        s = i / cols
        x = x_center - width / 2 + width * s
        row = []
        for j in range(rows + 1):
            t = j / rows
            y = top + (bottom - top) * t
            fold = 0.035 * math.sin(s * math.pi * 7) * (0.6 + 0.4 * t)
            row.append(bm.verts.new(G(x, y, z + fold)))
        grid.append(row)
    for i in range(cols):
        for j in range(rows):
            bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))  # facing the room
    obj = mesh_object(name, bm, [mat])
    shade_smooth(obj)
    fill_colour(obj)
    return obj


def build():
    walls = material("Wall", (0.42, 0.5, 0.6), roughness=0.9)
    ceiling = material("Ceiling", (0.92, 0.9, 0.86), roughness=0.95)
    trim = material("Trim", (0.93, 0.92, 0.88), roughness=0.5)
    floor = material("Floor", roughness=0.6, image=_floor_texture())
    curtain_mat = material("Curtain", (0.86, 0.72, 0.52), roughness=0.95)
    door_mat = material("Door", (0.9, 0.88, 0.83), roughness=0.55)
    brass = material("Brass", (0.85, 0.65, 0.3), roughness=0.3, metallic=1.0)
    glow = material("GlowCeiling", (1.0, 0.95, 0.85), roughness=0.5)

    (x0, y0, z0), (x1, y1, z1) = L.ROOM_MIN, L.ROOM_MAX
    w, d, h, t = x1 - x0, z1 - z0, y1 - y0, L.WALL
    parts = [
        gbox("Floor", (w + 2 * t, 0.04, d + 2 * t), (0, -0.02, 0), floor, 0.0),
        gbox("Ceiling", (w + 2 * t, 0.04, d + 2 * t), (0, h + 0.02, 0), ceiling, 0.0),
        gbox("LeftWall", (t, h, d), (x0 - t / 2, h / 2, 0), walls, 0.0),
        gbox("RightWall", (t, h, d), (x1 + t / 2, h / 2, 0), walls, 0.0),
    ]
    parts += _wall_with_window(walls) + _front_wall_with_door(walls)

    # Skirting all round (with a gap at the door).
    sk_h, sk_t = 0.09, 0.015
    parts += [
        gbox("SkirtBack", (w, sk_h, sk_t), (0, sk_h / 2, z0 + sk_t / 2), trim, 0.003, 1),
        gbox("SkirtLeft", (sk_t, sk_h, d), (x0 + sk_t / 2, sk_h / 2, 0), trim, 0.003, 1),
        gbox("SkirtRight", (sk_t, sk_h, d), (x1 - sk_t / 2, sk_h / 2, 0), trim, 0.003, 1),
        gbox("SkirtFrontR", (x1 - (L.DOOR_CENTER_X + L.DOOR_WIDTH / 2 + 0.06), sk_h, sk_t),
             ((x1 + L.DOOR_CENTER_X + L.DOOR_WIDTH / 2 + 0.06) / 2, sk_h / 2, z1 - sk_t / 2), trim, 0.003, 1),
    ]

    # Window: frame, a mullion, a deep sill.
    wl = L.WINDOW_CENTER_X - L.WINDOW_WIDTH / 2
    wr = L.WINDOW_CENTER_X + L.WINDOW_WIDTH / 2
    fz = z0 - t / 2
    ft = 0.06
    parts += [
        gbox("FrameTop", (L.WINDOW_WIDTH + 2 * ft, ft, t + 0.02), (L.WINDOW_CENTER_X, L.WINDOW_TOP + ft / 2, fz), trim, 0.006),
        gbox("FrameLeft", (ft, L.WINDOW_TOP - L.WINDOW_SILL, t + 0.02), (wl - ft / 2, (L.WINDOW_TOP + L.WINDOW_SILL) / 2, fz), trim, 0.006),
        gbox("FrameRight", (ft, L.WINDOW_TOP - L.WINDOW_SILL, t + 0.02), (wr + ft / 2, (L.WINDOW_TOP + L.WINDOW_SILL) / 2, fz), trim, 0.006),
        gbox("Mullion", (0.04, L.WINDOW_TOP - L.WINDOW_SILL, 0.05), (L.WINDOW_CENTER_X, (L.WINDOW_TOP + L.WINDOW_SILL) / 2, fz - 0.02), trim, 0.004),
        gbox("TransomBar", (L.WINDOW_WIDTH, 0.035, 0.05), (L.WINDOW_CENTER_X, L.WINDOW_SILL + (L.WINDOW_TOP - L.WINDOW_SILL) * 0.72, fz - 0.02), trim, 0.004),
        # The sill stops just short of the tank's back glass.
        gbox("Sill", (L.WINDOW_WIDTH + 0.2, 0.035, t + 0.03), (L.WINDOW_CENTER_X, L.WINDOW_SILL - 0.0175, fz + 0.005), trim, 0.008),
        # Curtain rail.
        gbox("Rail", (L.WINDOW_WIDTH + 0.9, 0.025, 0.025), (L.WINDOW_CENTER_X, L.WINDOW_TOP + 0.14, z0 + 0.06), brass, 0.01, 3),
    ]
    parts += [_curtain("CurtainL", wl - 0.2, 0.45, curtain_mat), _curtain("CurtainR", wr + 0.2, 0.45, curtain_mat)]

    # Door: slab, frame, handle.
    dz = z1 - 0.02
    parts += [
        gbox("DoorSlab", (L.DOOR_WIDTH - 0.02, L.DOOR_HEIGHT - 0.01, 0.04), (L.DOOR_CENTER_X, L.DOOR_HEIGHT / 2, dz), door_mat, 0.004),
        gbox("DoorFrameL", (0.06, L.DOOR_HEIGHT + 0.05, 0.03), (L.DOOR_CENTER_X - L.DOOR_WIDTH / 2 - 0.02, (L.DOOR_HEIGHT + 0.05) / 2, z1 - 0.012), trim, 0.004),
        gbox("DoorFrameR", (0.06, L.DOOR_HEIGHT + 0.05, 0.03), (L.DOOR_CENTER_X + L.DOOR_WIDTH / 2 + 0.02, (L.DOOR_HEIGHT + 0.05) / 2, z1 - 0.012), trim, 0.004),
        gbox("DoorFrameTop", (L.DOOR_WIDTH + 0.1, 0.06, 0.03), (L.DOOR_CENTER_X, L.DOOR_HEIGHT + 0.03, z1 - 0.012), trim, 0.004),
        gbox("Handle", (0.12, 0.022, 0.03), (L.DOOR_CENTER_X + L.DOOR_WIDTH / 2 - 0.1, 1.0, dz - 0.04), brass, 0.009, 3),
    ]
    # Panels on the door.
    for py in (0.55, 1.45):
        parts.append(gbox("DoorPanel", (L.DOOR_WIDTH - 0.24, 0.7, 0.012), (L.DOOR_CENTER_X, py, dz - 0.024), door_mat, 0.004))

    # Ceiling light: a flush dome.
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=8, radius=0.22)
    for v in bm.verts:
        v.co.z = min(v.co.z, 0.0) * 0.35
    dome = mesh_object("CeilingLight", bm, [glow])
    dome.location = G(*L.CEILING_LIGHT[:1], L.ROOM_MAX[1] - 0.001, L.CEILING_LIGHT[2])
    shade_smooth(dome)
    parts.append(dome)

    for p in parts:
        if "Col" not in p.data.color_attributes:
            fill_colour(p)
    return parts
