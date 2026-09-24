"""Cars: bodies lofted through cross-sections along their length, so they have
rounded sides, shoulders, a glass band with pillars, a sloped windscreen and
rear window, wheels in dark wells, lights, bumpers, mirrors and plates.

A car is built in its own space (x forward from the rear bumper, y up from
the road, z to its left) in a scratch Builder, then placed with merge().
"""

import math

from builder import Builder, V, lin

# Stations along the car: (x, belt height, top height, width factor, glass).
# Where top == belt there's no cabin (bonnet, boot). `glass` marks stations
# whose side window band to the next station is glass (False: a pillar).
TYPES = {
    "sedan": {
        "length": 4.7, "width": 1.8, "clear": 0.22, "r": 0.33, "wheels": (0.95, 3.75),
        "stations": [(0.0, 0.78, 0.78, 0.9, False), (0.12, 0.92, 0.92, 0.97, False), (0.9, 0.96, 0.96, 1.0, False),
                     (1.5, 0.96, 1.4, 1.0, True), (2.2, 0.95, 1.43, 1.0, False), (2.3, 0.95, 1.43, 1.0, True),
                     (3.0, 0.94, 1.41, 1.0, True), (3.65, 0.92, 0.92, 1.0, False), (4.5, 0.8, 0.8, 0.97, False),
                     (4.7, 0.62, 0.62, 0.88, False)],
    },
    "hatch": {
        "length": 4.1, "width": 1.76, "clear": 0.2, "r": 0.31, "wheels": (0.72, 3.3),
        "stations": [(0.0, 0.9, 0.9, 0.9, False), (0.1, 0.95, 1.38, 0.96, False), (0.35, 0.95, 1.47, 1.0, True),
                     (1.8, 0.95, 1.48, 1.0, False), (1.9, 0.95, 1.48, 1.0, True), (2.55, 0.94, 1.45, 1.0, True),
                     (3.25, 0.92, 0.92, 1.0, False), (3.95, 0.8, 0.8, 0.96, False), (4.1, 0.62, 0.62, 0.86, False)],
    },
    "suv": {
        "length": 4.8, "width": 1.9, "clear": 0.32, "r": 0.38, "wheels": (0.95, 3.85),
        "stations": [(0.0, 1.05, 1.05, 0.92, False), (0.1, 1.1, 1.66, 0.97, False), (0.3, 1.1, 1.74, 1.0, True),
                     (2.2, 1.1, 1.76, 1.0, False), (2.3, 1.1, 1.76, 1.0, True), (3.15, 1.09, 1.74, 1.0, True),
                     (3.85, 1.07, 1.07, 1.0, False), (4.65, 0.98, 0.98, 0.97, False), (4.8, 0.75, 0.75, 0.9, False)],
    },
    "van": {
        "length": 5.2, "width": 1.95, "clear": 0.3, "r": 0.36, "wheels": (0.9, 4.15),
        "stations": [(0.0, 1.1, 1.98, 0.97, False), (0.05, 1.1, 2.05, 1.0, False), (3.2, 1.1, 2.05, 1.0, False),
                     (3.3, 1.1, 2.05, 1.0, True), (3.95, 1.1, 2.0, 1.0, True), (4.5, 1.08, 1.08, 1.0, False),
                     (5.1, 0.98, 0.98, 0.97, False), (5.2, 0.75, 0.75, 0.9, False)],
    },
}

GLASS = (0.06, 0.08, 0.1)


def _ring(x, belt, top, wf, t, clear):
    """A cross-section at x as a closed loop of (y, z) points, right side
    (z < 0) first from the bottom centre, over the roof, down the left."""
    hw = t["width"] / 2 * wf
    cabin = top > belt + 0.05
    roof_hw = hw * 0.78 if cabin else hw * 0.92
    shoulder = belt + 0.04 if cabin else belt
    half = [(clear, 0.0), (clear, -hw * 0.9), (clear + 0.12, -hw), (belt - 0.12, -hw),
            (shoulder, -hw * 0.93), (top, -roof_hw), (top + (0.03 if cabin else 0.0), 0.0)]
    left = [(y, -z) for y, z in reversed(half[1:-1])]
    return half + left


def body(b, kind, paint):
    """The lofted body into Builder b, in the car's own space."""
    t = TYPES[kind]
    col = lin(paint)
    dark = lin((0.05, 0.05, 0.055))
    glass = lin(GLASS)
    st = t["stations"]
    rings = [[V(x, y, z) for y, z in _ring(x, belt, top, wf, t, t["clear"])] for x, belt, top, wf, _ in st]
    n = len(rings[0])
    # Band index k joins point k and k+1 of the ring. Bands 4 and 7 (right and
    # left window lines) and 5, 6 (the roof) depend on the cabin.
    right_window, left_window = 4, n - 6
    for i in range(len(rings) - 1):
        a, c = rings[i], rings[i + 1]
        cab_a = st[i][2] > st[i][1] + 0.05
        cab_c = st[i + 1][2] > st[i + 1][1] + 0.05
        for k in range(n):
            k2 = (k + 1) % n
            mat, cc = "CarPaint", col
            if k == 0 or k == n - 1:
                mat, cc = "Rubber", dark      # underside
            elif k in (right_window, left_window) and cab_a and cab_c and st[i][4]:
                mat, cc = "CarGlass", glass   # side windows
            elif k in (5, 6) and cab_a != cab_c:
                mat, cc = "CarGlass", glass   # windscreen and rear window
            elif k in (right_window, left_window) and cab_a != cab_c:
                mat, cc = "CarGlass", glass   # the windscreen's corners
            b.face([a[k], a[k2], c[k2], c[k]], mat, col=cc)
    # Caps.
    b.face(list(reversed(rings[0])), "CarPaint", col=col)
    b.face(rings[-1], "CarPaint", col=col)

    L, W, r = t["length"], t["width"], t["r"]
    # Wheels in dark wells.
    for wx in t["wheels"]:
        for side in (-1, 1):
            _well(b, wx, r, side * (W / 2 + 0.004), side)
            _wheel(b, wx, r, side * (W / 2 - 0.22), side * (W / 2 + 0.01))
    # Lights, grille, bumpers, plates.
    front = st[-1]
    rear = st[0]
    fy = front[1] - 0.08
    for side in (-1, 1):
        _lens(b, V(L + 0.004, fy, side * (W / 2 - 0.28)), 1, 0.17, 0.06, "Headlight", (1.0, 0.96, 0.88))
        _lens(b, V(-0.004, rear[1] - 0.06, side * (W / 2 - 0.2)), -1, 0.14, 0.07, "Taillight", (0.85, 0.06, 0.05))
    _lens(b, V(L + 0.003, fy - 0.05, 0.0), 1, 0.34, 0.07, "Rubber", (0.06, 0.06, 0.06))
    for x0, x1 in ((-0.05, 0.08), (L - 0.08, L + 0.05)):
        b.box((x0, 0.3, -W / 2 * 0.92), (x1, 0.46, W / 2 * 0.92), "Rubber", col=dark)
    for x, d in ((-0.052, -1), (L + 0.052, 1)):
        _lens(b, V(x, 0.38, 0.0), d, 0.25, 0.06, "Plate", (0.92, 0.9, 0.82))
    # Mirrors at the base of the windscreen.
    ws = next(s for s in st[::-1] if s[2] > s[1] + 0.05)
    for side in (-1, 1):
        z = side * (W / 2 + 0.08)
        b.box((ws[0] - 0.02, ws[1] + 0.05, min(z, z - side * 0.14)), (ws[0] + 0.1, ws[1] + 0.16, max(z, z - side * 0.14)),
              "CarPaint", col=col)


def _well(b, wx, r, z, side):
    """The dark arch of the wheel well around the top of the tyre, on the
    body's side."""
    n = 12
    outer = [V(wx + math.cos(math.pi * i / n) * (r + 0.09), r + math.sin(math.pi * i / n) * (r + 0.09), z) for i in range(n + 1)]
    inner = [V(wx + math.cos(math.pi * i / n) * (r + 0.01), r + math.sin(math.pi * i / n) * (r + 0.01), z) for i in range(n + 1)]
    dark = lin((0.03, 0.03, 0.03))
    for i in range(n):
        q = [inner[i], outer[i], outer[i + 1], inner[i + 1]]
        b.face(q if side > 0 else list(reversed(q)), "Rubber", col=dark)


def _wheel(b, wx, r, z0, z1):
    """A tyre from z0 to z1 (outer), with a hubcap on its outer face."""
    n = 14
    tyre = lin((0.035, 0.035, 0.035))
    ring = lambda z, rr: [V(wx + math.cos(2 * math.pi * i / n) * rr, r + math.sin(2 * math.pi * i / n) * rr, z)
                          for i in range(n)]
    a, c = ring(z0, r), ring(z1, r)
    out = 1 if z1 > z0 else -1
    for i in range(n):
        j = (i + 1) % n
        q = [a[i], a[j], c[j], c[i]]
        b.face(q if out > 0 else list(reversed(q)), "Rubber", col=tyre)
    face = ring(z1, r)
    b.face(face if out > 0 else list(reversed(face)), "Rubber", col=tyre)
    hub = ring(z1 + out * 0.004, r * 0.62)
    b.face(hub if out > 0 else list(reversed(hub)), "Chrome", col=lin((0.62, 0.63, 0.65)))


def _lens(b, p, facing, w, h, mat, colour):
    """A rectangle on the front (facing +1) or back (-1) of the car."""
    q = [V(p.x, p.y - h, p.z - w / 2 * facing), V(p.x, p.y - h, p.z + w / 2 * facing),
         V(p.x, p.y + h, p.z + w / 2 * facing), V(p.x, p.y + h, p.z - w / 2 * facing)]
    b.face(q, mat, col=lin(colour))


def place(b, kind, x, z, yaw, paint, taxi=False, y=0.0):
    """Builds a car and merges it into b, centred at (x, z) on a road at
    height y, facing yaw (0 = +x)."""
    t = TYPES[kind]
    scratch = Builder()
    body(scratch, kind, paint)
    if taxi:
        top = max(s[2] for s in t["stations"])
        mid = sum(s[0] for s in t["stations"] if s[2] > s[1] + 0.05) / max(1, sum(1 for s in t["stations"] if s[2] > s[1] + 0.05))
        scratch.box((mid - 0.3, top, -0.12), (mid + 0.3, top + 0.2, 0.12), "Lamp", col=lin((1.0, 0.92, 0.7)))
    c, s = math.cos(yaw), math.sin(yaw)
    half = t["length"] / 2

    def xf(v):
        lx = v.x - half
        return V(x + lx * c + v.z * s, y + v.y, z - lx * s + v.z * c)

    b.merge(scratch, xf)
