"""A lily pad floating on the surface, with a small flower. Origin at the
water line. Materials "Plant" (the pad, gently bobbing) and "Accent" (petals)."""

import math

import bmesh
from mathutils import Vector

from lib.common import join, mesh_object, paint, shade_smooth
from lib.decor import mats, rng, still, sway_by_height

RENDER_VIEWS = [(30, 40)]


def build():
    m = mats(Plant=((0.8, 0.8, 0.8), 0.35), Accent=((0.8, 0.8, 0.8), 0.5))
    bm = bmesh.new()
    center = bm.verts.new((0, 0, 0.002))
    ring = []
    steps = 40
    for i in range(steps + 1):
        # A round pad with its characteristic notch.
        a = math.radians(12) + (math.tau - math.radians(24)) * i / steps
        r = 0.055 * (1.0 + 0.03 * math.sin(a * 5))
        ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, 0.0015 * math.sin(a * 3))))
    for i in range(steps):
        bm.faces.new((center, ring[i], ring[i + 1]))
    pad = mesh_object("Pad", bm, [m["Plant"]])
    shade_smooth(pad)
    paint(pad, lambda co, n: (0.7 + 3.0 * math.hypot(co.x, co.y), 0.85 + 2.0 * math.hypot(co.x, co.y), 0.7, 1.0))
    sway_by_height(pad, 0.004)

    petals = []
    r = rng(3)
    for layer, (count, length, lift) in enumerate(((8, 0.02, 0.35), (6, 0.015, 0.8))):
        for i in range(count):
            a = math.tau * (i + 0.5 * layer) / count
            d = Vector((math.cos(a), math.sin(a), 0))
            bm = bmesh.new()
            base = Vector((-0.02, 0.01, 0.004))
            tip = base + d * length * math.cos(lift) + Vector((0, 0, length * math.sin(lift)))
            side = d.cross(Vector((0, 0, 1))).normalized() * 0.0065
            vs = [bm.verts.new(base), bm.verts.new(base + (tip - base) * 0.5 + side), bm.verts.new(tip),
                  bm.verts.new(base + (tip - base) * 0.5 - side)]
            bm.faces.new(vs)
            petal = mesh_object("Petal", bm, [m["Accent"]])
            paint(petal, lambda co, n: (1.0, 0.95, 0.97, 1.0))
            still(petal)
            petals.append(petal)
    obj = join([pad] + petals, "LilyPad")
    return [obj]
