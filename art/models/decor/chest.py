"""A treasure chest with its lid ajar, spilling gold (bubbles escape from the
gap in Godot). Materials "Primary" (wood), "Secondary" (iron bands), "Accent" (gold)."""

import math

import bmesh
from mathutils import Matrix, Vector, noise

from lib.common import bevelled_box, join, mesh_object, paint, shade_smooth
from lib.decor import mats, rng, still

RENDER_VIEWS = [(30, 22)]
W, D, H = 0.09, 0.06, 0.045


def _lid(mat):
    # A half-cylinder lid, hinged at the back and tipped open.
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=D / 2, radius2=D / 2, depth=W)
    geom = bm.verts[:]
    bmesh.ops.rotate(bm, verts=geom, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    # Keep the upper half only.
    for v in [v for v in bm.verts if v.co.z < -0.001]:
        v.co.z = 0.0
    obj = mesh_object("Lid", bm, [mat])
    shade_smooth(obj, 40)
    hinge = Vector((0, D / 2, H))
    obj.data.transform(Matrix.Translation(Vector((0, 0, H))))
    obj.data.transform(Matrix.Translation(-hinge))
    obj.data.transform(Matrix.Rotation(math.radians(-28), 4, "X"))
    obj.data.transform(Matrix.Translation(hinge))
    return obj


def build():
    m = mats(Primary=((0.8, 0.8, 0.8), 0.8), Secondary=((0.8, 0.8, 0.8), 0.45), Accent=((0.8, 0.8, 0.8), 0.25))
    parts = [bevelled_box("Box", (W, D, H), 0.003, 2, m["Primary"], (0, 0, H / 2)), _lid(m["Primary"])]
    for x in (-W / 2 + 0.012, W / 2 - 0.012):
        parts.append(bevelled_box("Band", (0.007, D + 0.003, H + 0.002), 0.001, 1, m["Secondary"], (x, 0, H / 2)))
    parts.append(bevelled_box("Lock", (0.014, 0.004, 0.016), 0.002, 1, m["Secondary"], (0, -D / 2 - 0.002, H - 0.006)))
    r = rng(2)
    for i in range(14):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.006, radius2=0.006, depth=0.0015)
        coin = mesh_object("Coin", bm, [m["Accent"]])
        coin.data.transform(Matrix.Rotation(r.uniform(-0.5, 0.5), 4, "X") @ Matrix.Rotation(r.uniform(-0.5, 0.5), 4, "Y"))
        coin.data.transform(Matrix.Translation((r.uniform(-W / 2 + 0.01, W / 2 - 0.01), r.uniform(-D / 2 + 0.01, D / 2 - 0.01), H + r.uniform(-0.002, 0.004))))
        parts.append(coin)
    obj = join(parts, "Chest")
    paint(obj, lambda co, n: tuple([0.82 + 0.12 * math.sin(co.x * 400 + noise.noise(co * 90) * 3)] * 3) + (1.0,))
    still(obj)
    return [obj]
