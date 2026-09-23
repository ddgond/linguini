"""A marimo moss ball: a fuzzy green sphere that bobs gently mid-water.
Material "Primary" (moss colour variants). Origin at its centre."""

import bmesh
from mathutils import Vector, noise

from lib.common import mesh_object, paint, shade_smooth
from lib.decor import mats, still

RENDER_VIEWS = [(30, 20)]


def build():
    m = mats(Primary=((0.8, 0.8, 0.8), 0.95))
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=4, radius=0.026)
    for v in bm.verts:
        fuzz = noise.noise(v.co * 900.0) * 0.0018 + noise.fractal(v.co * 80.0, 0.5, 2.0, 3) * 0.0015
        v.co += v.co.normalized() * fuzz
    obj = mesh_object("MossBall", bm, [m["Primary"]])
    shade_smooth(obj)
    paint(obj, lambda co, n: tuple([0.7 + 0.3 * (0.5 + 0.5 * noise.noise(co * 700.0))] * 3) + (1.0,))
    still(obj)
    return [obj]
