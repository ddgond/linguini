"""A clump of tall grass (like vallisneria): long thin ribbons that sway.
Material "Plant"; Anim UV u = sway weight (roots still, tips free)."""

import math

from mathutils import Vector

from lib.common import join, paint
from lib.decor import bezier, mats, rng, ribbon, sway_by_height

RENDER_VIEWS = [(30, 10)]
HEIGHT = 0.3


def build():
    m = mats(Plant=((0.8, 0.8, 0.8), 0.55))
    r = rng(5)
    blades = []
    for i in range(16):
        a = r.uniform(0, math.tau)
        base = Vector((math.cos(a), math.sin(a), 0)) * r.uniform(0.0, 0.025)
        h = r.uniform(0.13, HEIGHT)
        lean = Vector((math.cos(a), math.sin(a), 0)) * r.uniform(0.02, 0.07)
        spine = bezier(base, base + Vector((0, 0, h * 0.4)), base + lean * 0.6 + Vector((0, 0, h * 0.8)),
                       base + lean + Vector((r.uniform(-0.01, 0.01), 0, h)), 12)
        widths = [0.009 * (1.0 - 0.75 * (k / 12) ** 2) for k in range(13)]
        blades.append(ribbon("Blade", spine, widths, m["Plant"], normal_hint=Vector((math.sin(a), -math.cos(a), 0)), fold=0.15))
    obj = join(blades, "Grass")
    paint(obj, lambda co, n: (0.55 + 0.45 * min(co.z / HEIGHT, 1.0), 0.6 + 0.4 * min(co.z / HEIGHT, 1.0), 0.55 + 0.4 * min(co.z / HEIGHT, 1.0), 1.0))
    sway_by_height(obj, HEIGHT)
    return [obj]
