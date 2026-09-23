"""An air stone: a small porous disc that bubbles (bubbles are Godot particles
from its top centre). Material "Primary"."""

import bmesh
from mathutils import noise

from lib.common import mesh_object, paint, shade_smooth
from lib.decor import mats, still

RENDER_VIEWS = [(30, 25)]


def build():
    m = mats(Primary=((0.8, 0.8, 0.8), 0.9))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=0.022, radius2=0.018, depth=0.014)
    for v in bm.verts:
        v.co.z += 0.007
    obj = mesh_object("AirStone", bm, [m["Primary"]])
    shade_smooth(obj, 50)
    paint(obj, lambda co, n: tuple([0.8 + 0.2 * noise.noise(co * 900.0)] * 3) + (1.0,))
    still(obj)
    return [obj]
