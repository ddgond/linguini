"""A little bonfire with a coiled sword planted in it, for Tortellini: a ring of
stones, charred logs, glowing embers ("Ember", emissive in Godot) and a
twisted blade ("Secondary"). Stones are "Primary"."""

import math

import bmesh
from mathutils import Matrix, Vector, noise

from lib.common import join, mesh_object, paint, shade_smooth
from lib.decor import bezier, mats, rng, rock, still, tube

RENDER_VIEWS = [(30, 20)]


def _blade(mat):
    # A long narrow blade twisted into a coil, point down into the embers.
    bm = bmesh.new()
    steps = 30
    rows = []
    for i in range(steps + 1):
        t = i / steps
        z = 0.005 + 0.1 * t
        twist = t * math.tau * 1.25
        width = 0.009 * (1.0 - 0.6 * (1 - t) ** 6)
        c = Vector((0.003 * math.sin(twist * 2), 0.003 * math.cos(twist * 2), z))
        d = Vector((math.cos(twist), math.sin(twist), 0)) * width / 2
        rows.append((bm.verts.new(c - d), bm.verts.new(c + d)))
    for i in range(steps):
        bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
    blade = mesh_object("Blade", bm, [mat])
    shade_smooth(blade)
    grip = tube("Grip", [Vector((0.003 * math.sin(math.tau * 2.5), 0.003 * math.cos(math.tau * 2.5), 0.105 + 0.03 * k / 6)) for k in range(7)],
                0.004, mat, sides=8)
    guard = tube("Guard", [Vector((-0.016, 0, 0.106)), Vector((0.016, 0, 0.106))], 0.0025, mat, sides=8)
    return [blade, grip, guard]


def build():
    m = mats(Primary=((0.8, 0.8, 0.8), 0.9), Secondary=((0.8, 0.8, 0.8), 0.35), Ember=((0.8, 0.8, 0.8), 0.6))
    r = rng(6)
    parts = []
    for i in range(9):
        a = math.tau * i / 9 + r.uniform(-0.15, 0.15)
        stone = rock("Stone", (0.022, 0.018, 0.014), 40 + i, m["Primary"], roughness=0.5, subdivisions=2)
        stone.data.transform(Matrix.Translation((math.cos(a) * 0.045, math.sin(a) * 0.045, 0)))
        parts.append(stone)
    for i in range(4):
        a = math.tau * i / 4 + 0.4
        d = Vector((math.cos(a), math.sin(a), 0))
        parts.append(tube("Log", [d * 0.035 + Vector((0, 0, 0.004)), Vector((0, 0, 0.025))], 0.0055, m["Primary"], sides=8))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.028)
    for v in bm.verts:
        v.co.z = max(0.0, v.co.z) * 0.35 + 0.001
        v.co += v.co.normalized() * 0.002 * noise.noise(v.co * 400)
    embers = mesh_object("Embers", bm, [m["Ember"]])
    shade_smooth(embers)
    parts.append(embers)
    parts += _blade(m["Secondary"])
    obj = join(parts, "Bonfire")

    def colour(co, n):
        k = 0.75 + 0.2 * noise.noise(co * 300.0)
        return (k, k, k, 1.0)

    paint(obj, colour)
    still(obj)
    return [obj]
