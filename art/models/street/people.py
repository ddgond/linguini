"""People on the sidewalks: a few simple figures the game walks up and down,
and an umbrella for the rain. Built at the origin facing +x, feet at y = 0.

For the walker shader (godot/shaders/street_walker.gdshader):
  Col.r   which part: 0.1 skin, 0.35 top, 0.6 bottom, 0.85 shoes, 1.0 hair
          (the game picks each person's colours)
  UV2.x   which limb swings: 0 none, 0.2 left leg, 0.4 right leg,
          0.6 left arm, 0.8 right arm
  UV2.y   the height it swings about (hip or shoulder), in metres
"""

import math

from builder import Builder, V

SKIN, TOP, BOTTOM, SHOES, HAIR = 0.1, 0.35, 0.6, 0.85, 1.0
NONE, LEFT_LEG, RIGHT_LEG, LEFT_ARM, RIGHT_ARM = 0.0, 0.2, 0.4, 0.6, 0.8

FIGURES = {
    # height scale, build (width), coat (how far the top reaches down), skirt, hair
    "coat": {"scale": 1.0, "wide": 1.05, "coat": 0.55, "skirt": False, "hair": "short"},
    "jacket": {"scale": 1.02, "wide": 1.0, "coat": 0.88, "skirt": False, "hair": "short"},
    "dress": {"scale": 0.96, "wide": 0.92, "coat": 0.9, "skirt": True, "hair": "long"},
    "kid": {"scale": 0.72, "wide": 0.95, "coat": 0.85, "skirt": False, "hair": "short"},
}


def _part(p):
    return (p, 0.0, 0.0, 1.0)


def _limb(b, a, c, ra, rc, part, limb, sides=6, pivot=0.0):
    """A tapered tube from a to c (both Vectors), radius ra to rc."""
    b.tube([a, c], [ra, rc], "Walker", col=_part(part), sides=sides, uv2=(limb, pivot))
    # Caps so the ends aren't open (both ways round: limbs point up or down).
    for p, r in ((a, ra), (c, rc)):
        ring = [p + V(math.cos(2 * math.pi * k / sides) * r, 0, math.sin(2 * math.pi * k / sides) * r)
                for k in range(sides)]
        for loop in (ring, list(reversed(ring))):
            b.face(loop, "Walker", col=_part(part), uv2=[(limb, pivot)] * sides)


def _blob(b, centre, radii, part, limb=NONE, rings=6, sides=10, y_min=-1.0, pivot=0.0):
    """An ellipsoid (optionally cut off below y_min, as a fraction of its height)."""
    pts = []
    for i in range(rings + 1):
        t = -1 + 2 * i / rings
        t = max(t, y_min)
        rr = math.sqrt(max(0.0, 1 - t * t))
        pts.append([centre + V(math.cos(2 * math.pi * k / sides) * rr * radii[0], t * radii[1],
                               math.sin(2 * math.pi * k / sides) * rr * radii[2]) for k in range(sides)])
    for i in range(rings):
        for k in range(sides):
            k2 = (k + 1) % sides
            q = [pts[i][k], pts[i][k2], pts[i + 1][k2], pts[i + 1][k]]
            b.face(list(reversed(q)), "Walker", col=_part(part), uv2=[(limb, pivot)] * 4)


def figure(kind):
    f = FIGURES[kind]
    s = f["scale"]
    w = f["wide"]
    b = Builder()
    hip = 0.92 * s
    shoulder = 1.44 * s
    # Legs and shoes.
    for side, limb in ((1, LEFT_LEG), (-1, RIGHT_LEG)):
        z = side * 0.095 * w
        _limb(b, V(0, hip, z), V(0, 0.09 * s, z), 0.075 * w, 0.05 * w, BOTTOM, limb, pivot=hip)
        b.box((-0.06 * s, 0.0, z - 0.05), (0.17 * s, 0.09 * s, z + 0.05), "Walker", col=_part(SHOES), uv2=(limb, hip))
    # Torso, and a coat or skirt flaring below the hips.
    # f["coat"]: how far down the top reaches, as a share of the hip height.
    torso_low = min(hip + 0.02, hip * f["coat"])
    b.tube([V(0, torso_low, 0), V(0, hip + 0.1 * s, 0), V(0, shoulder - 0.05 * s, 0)],
           [0.17 * w if f["coat"] < 0.8 or f["skirt"] else 0.15 * w, 0.15 * w, 0.2 * w], "Walker", col=_part(TOP),
           sides=10, uv2=[(NONE, 0.0), (NONE, 0.0)])
    if f["skirt"]:
        b.tube([V(0, hip + 0.05, 0), V(0, 0.5 * s, 0)], [0.15 * w, 0.24 * w], "Walker", col=_part(BOTTOM), sides=10,
               uv2=(NONE, 0.0))
    # Shoulders: a flattened cap on top of the torso.
    _blob(b, V(0, shoulder - 0.05 * s, 0), (0.12 * w, 0.06 * s, 0.22 * w), TOP)
    # Arms.
    for side, limb in ((1, LEFT_ARM), (-1, RIGHT_ARM)):
        z = side * 0.22 * w
        arm = shoulder - 0.04 * s
        _limb(b, V(0, arm, z), V(0.02, hip - 0.1 * s, z * 1.05), 0.055 * w, 0.045 * w, TOP, limb, pivot=arm)
        _blob(b, V(0.02, hip - 0.14 * s, z * 1.05), (0.045, 0.06, 0.04), SKIN, limb, pivot=arm)
    # Neck, head and hair.
    _limb(b, V(0, shoulder - 0.02, 0), V(0, shoulder + 0.09 * s, 0), 0.05, 0.05, SKIN, NONE)
    head = V(0.01, shoulder + 0.2 * s, 0)
    _blob(b, head, (0.1 * s, 0.12 * s, 0.09 * s), SKIN)
    _blob(b, head + V(-0.01, 0.03 * s, 0), (0.108 * s, 0.11 * s, 0.098 * s), HAIR, y_min=-0.1)
    if f["hair"] == "long":
        _blob(b, head + V(-0.05, -0.08 * s, 0), (0.07 * s, 0.14 * s, 0.1 * s), HAIR)
    return b


def umbrella():
    """An open umbrella, its handle at the origin (the game holds it up)."""
    b = Builder()
    n = 8
    top = V(0, 0.95, 0)
    rim = [V(math.cos(2 * math.pi * k / n) * 0.52, 0.7, math.sin(2 * math.pi * k / n) * 0.52) for k in range(n)]
    for k in range(n):
        tri = [top, rim[(k + 1) % n], rim[k]]
        b.face(tri, "Umbrella", col=(1.0, 1.0, 1.0, 1.0))
        b.face(list(reversed(tri)), "Umbrella", col=(0.7, 0.7, 0.7, 1.0))
    b.tube([V(0, 0.0, 0), V(0, 1.0, 0)], 0.01, "Walker", col=_part(SHOES), sides=4)
    return b


def bird():
    """A pigeon in flight, for the flocks: a body and two wings. UV2.x is how
    far out along a wing a vertex is (the shader flaps them)."""
    b = Builder()
    grey = (0.1, 0.0, 0.0, 1.0)
    _blob(b, V(0, 0, 0), (0.17, 0.055, 0.06), SKIN, rings=4, sides=6)
    _blob(b, V(0.15, 0.03, 0), (0.05, 0.045, 0.045), SKIN, rings=3, sides=6)
    # A fanned tail.
    b.face([V(-0.14, 0.0, 0.0), V(-0.28, 0.01, -0.06), V(-0.28, 0.01, 0.06)], "Bird", col=grey, uv2=[(0.0, 0.0)] * 3)
    b.face([V(-0.14, 0.0, 0.0), V(-0.28, 0.01, 0.06), V(-0.28, 0.01, -0.06)], "Bird", col=grey, uv2=[(0.0, 0.0)] * 3)
    for side in (1, -1):
        root_f, root_b = V(0.07, 0.02, side * 0.04), V(-0.06, 0.02, side * 0.04)
        mid_f, mid_b = V(0.05, 0.02, side * 0.2), V(-0.09, 0.02, side * 0.2)
        tip = V(-0.08, 0.02, side * 0.34)
        quads = [([root_f, mid_f, mid_b, root_b], [0.0, 0.5, 0.5, 0.0]), ([mid_f, tip, mid_b, mid_b], [0.5, 1.0, 0.5, 0.5])]
        for pts, w in quads:
            for loop, ws in ((pts, w), (list(reversed(pts)), list(reversed(w)))):
                b.face(loop, "Bird", col=grey, uv2=[(x, 0.0) for x in ws])
    for f in range(len(b.faces)):
        b.mats[f] = b._mat("Bird")
    return b
