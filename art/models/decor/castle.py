"""A little castle: two round towers with cone roofs, a crenellated wall and a
gate. Materials "Primary" (stone), "Secondary" (roofs), dark windows painted in."""

import math

import bmesh
from mathutils import Vector, noise

from lib.common import bevelled_box, join, mesh_object, paint, shade_smooth
from lib.decor import mats, still

RENDER_VIEWS = [(28, 15)]


def _cylinder(name, radius, height, mat, x, y, segments=20, cap=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, segments=segments, radius1=radius, radius2=radius * 0.94, depth=height)
    for v in bm.verts:
        v.co += Vector((x, y, height / 2))
    obj = mesh_object(name, bm, [mat])
    shade_smooth(obj, 40)
    return obj


def _cone(name, radius, height, mat, x, y, z):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=radius, radius2=0.0, depth=height)
    for v in bm.verts:
        v.co += Vector((x, y, z + height / 2))
    obj = mesh_object(name, bm, [mat])
    shade_smooth(obj, 40)
    return obj


def build():
    m = mats(Primary=((0.8, 0.8, 0.8), 0.85), Secondary=((0.8, 0.8, 0.8), 0.6))
    stone, roof = m["Primary"], m["Secondary"]
    parts = []
    for sx in (-1, 1):
        parts.append(_cylinder("Tower", 0.026, 0.12, stone, sx * 0.055, 0.01))
        # Crenellations around the tower top.
        for i in range(8):
            a = math.tau * i / 8
            parts.append(bevelled_box("Merlon", (0.009, 0.009, 0.01), 0.001, 1, stone,
                                      (sx * 0.055 + math.cos(a) * 0.022, 0.01 + math.sin(a) * 0.022, 0.123)))
        parts.append(_cone("Roof", 0.03, 0.05, roof, sx * 0.055, 0.01, 0.13))
    parts.append(bevelled_box("Wall", (0.1, 0.03, 0.075), 0.002, 1, stone, (0, 0.015, 0.0375)))
    for i in range(5):
        parts.append(bevelled_box("Merlon", (0.011, 0.028, 0.012), 0.001, 1, stone, (-0.036 + i * 0.018, 0.015, 0.081)))
    obj = join(parts, "Castle")

    def colour(co, n):
        k = 0.8 + 0.15 * noise.noise(co * 180.0)
        # Brick courses.
        if abs(math.sin(co.z * 260.0)) < 0.12:
            k *= 0.8
        # Dark gate and windows (on the front, -Y).
        gate = abs(co.x) < 0.017 and co.z < 0.045 and n.y < -0.5 and (co.z < 0.03 or math.hypot(co.x, co.z - 0.03) < 0.017)
        window = n.y < -0.2 and abs(abs(co.x) - 0.055) < 0.006 and 0.07 < co.z < 0.095
        if gate or window:
            return (0.08, 0.07, 0.07, 1.0)
        return (k, k, k, 1.0)

    paint(obj, colour)
    still(obj)
    return [obj]
