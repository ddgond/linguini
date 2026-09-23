"""A broad-leaf rosette (like an Amazon sword): leaves on curving stems,
fanning out from a crown. Material "Plant"; Anim UV u = sway weight."""

import math

from mathutils import Vector

from lib.common import join, paint
from lib.decor import bezier, mats, rng, ribbon, sway_by_height

RENDER_VIEWS = [(30, 18)]
HEIGHT = 0.2


def build():
    m = mats(Plant=((0.8, 0.8, 0.8), 0.5))
    r = rng(8)
    leaves = []
    count = 10
    for i in range(count):
        a = math.tau * i / count + r.uniform(-0.2, 0.2)
        out = Vector((math.cos(a), math.sin(a), 0))
        h = r.uniform(0.12, HEIGHT)
        reach = r.uniform(0.05, 0.1)
        spine = bezier(Vector((0, 0, 0.005)), out * 0.01 + Vector((0, 0, h * 0.45)),
                       out * reach * 0.7 + Vector((0, 0, h * 0.95)), out * reach + Vector((0, 0, h * 0.8)), 16)
        # A thin stem, then a lance-shaped blade.
        widths = []
        for k in range(17):
            t = k / 16
            if t < 0.35:
                widths.append(0.004)
            else:
                u = (t - 0.35) / 0.65
                widths.append(0.004 + 0.034 * math.sin(math.pi * u) ** 0.8 * (1 - 0.3 * u))
        leaves.append(ribbon("Leaf", spine, widths, m["Plant"], normal_hint=Vector((-math.sin(a), math.cos(a), 0)), fold=0.12))
    obj = join(leaves, "Broadleaf")
    paint(obj, lambda co, n: (0.6 + 0.4 * min(co.z / HEIGHT, 1.0), 0.7 + 0.3 * min(co.z / HEIGHT, 1.0), 0.6 + 0.3 * min(co.z / HEIGHT, 1.0), 1.0))
    sway_by_height(obj, HEIGHT)
    return [obj]
