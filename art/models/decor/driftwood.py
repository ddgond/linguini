"""Driftwood: a gnarled branch arching over the gravel, big enough for
Linguini to swim under, with a couple of stubby side branches.
Material "Primary" (wood colour variants)."""

import math

from mathutils import Vector, noise

from lib.common import join, paint
from lib.decor import bezier, mats, still, tube, tube_colliders

RENDER_VIEWS = [(25, 12), (90, 5)]


def build():
    m = mats(Primary=((0.8, 0.8, 0.8), 0.85))
    arch = bezier(Vector((-0.14, 0.02, -0.005)), Vector((-0.1, 0.0, 0.16)), Vector((0.08, -0.02, 0.17)),
                  Vector((0.15, 0.01, -0.005)), steps=28)
    # Knobbly: thicker at the roots, bulging along the way.
    # Its ends are buried in the gravel, so they're left open.
    main = tube("Arch", arch, 0.017, m["Primary"], sides=12, closed_ends=False,
                radius_fn=lambda t: 1.25 - 0.45 * math.sin(math.pi * t) + 0.18 * noise.noise(Vector((t * 9, 1.3, 0))))
    branch1 = tube("Branch", bezier(arch[9], arch[9] + Vector((-0.03, 0.02, 0.05)), arch[9] + Vector((-0.06, 0.03, 0.08)),
                                    arch[9] + Vector((-0.07, 0.05, 0.1)), 10), 0.008, m["Primary"], sides=8,
                   radius_fn=lambda t: 1.0 - 0.7 * t)
    branch2 = tube("Branch", bezier(arch[20], arch[20] + Vector((0.02, -0.03, 0.03)), arch[20] + Vector((0.05, -0.04, 0.05)),
                                    arch[20] + Vector((0.08, -0.05, 0.05)), 10), 0.007, m["Primary"], sides=8,
                   radius_fn=lambda t: 1.0 - 0.75 * t)
    obj = join([main, branch1, branch2], "Driftwood")

    def colour(co, n):
        grain = 0.82 + 0.12 * math.sin(co.x * 180 + noise.noise(co * 60) * 4) + 0.08 * noise.noise(co * 120)
        top = 0.1 * max(n.z, 0.0)
        k = grain + top
        return (k, k * 0.97, k * 0.93, 1.0)

    paint(obj, colour)
    still(obj)
    # Collide along the arch itself, so the fish can swim under it.
    return [obj] + tube_colliders("Arch", arch, 0.02)
