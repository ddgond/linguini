"""The ground: road, curbs, sidewalks, markings, crossings, manholes and
drains, tree pits, and the outside of our own window."""

import math

from builder import V, lin
import street_layout as S

ASPHALT = lin((0.2, 0.2, 0.21))
CONCRETE = lin((0.62, 0.61, 0.58))
CURB = lin((0.58, 0.57, 0.55))
PAINT_WHITE = lin((0.88, 0.88, 0.84))
PAINT_YELLOW = lin((0.9, 0.7, 0.2))


def _walk(b, x0, x1, z0, z1):
    """A sidewalk slab (top face plus the curb face toward the road is separate)."""
    y = S.WALK_Y
    b.quad(V(x0, y, z1), V(x1, y, z1), V(x1, y, z0), V(x0, y, z0), "Concrete", col=CONCRETE)


def _curb_x(b, x0, x1, z, facing):
    """A curb along x at z; `facing` = +1 if the road is toward +z."""
    y0, y1 = S.ROAD_Y, S.WALK_Y
    t = 0.18
    if facing > 0:
        b.box((x0, y0 - 0.1, z - t), (x1, y1 + 0.004, z), "Curb", col=CURB, skip=("bottom", "back"))
    else:
        b.box((x0, y0 - 0.1, z), (x1, y1 + 0.004, z + t), "Curb", col=CURB, skip=("bottom", "front"))


def _curb_z(b, z0, z1, x, facing):
    """A curb along z at x; `facing` = +1 if the road is toward +x."""
    t = 0.18
    if facing > 0:
        b.box((x - t, S.ROAD_Y - 0.1, z0), (x, S.WALK_Y + 0.004, z1), "Curb", col=CURB, skip=("bottom", "left"))
    else:
        b.box((x, S.ROAD_Y - 0.1, z0), (x + t, S.WALK_Y + 0.004, z1), "Curb", col=CURB, skip=("bottom", "right"))


def _stripe(b, x0, x1, z0, z1, col=PAINT_WHITE):
    y = S.ROAD_Y + 0.004
    b.quad(V(x0, y, z1), V(x1, y, z1), V(x1, y, z0), V(x0, y, z0), "RoadPaint", col=col)


def _disc(b, x, z, r, mat, col, y=None, sides=16):
    y = (S.ROAD_Y + 0.003) if y is None else y
    pts = [V(x + math.cos(-2 * math.pi * i / sides) * r, y, z + math.sin(-2 * math.pi * i / sides) * r) for i in range(sides)]
    b.face(pts, mat, col=col)


def build(b, rng, layout):
    x0, x1 = S.STREET_X
    rx0 = S.CROSS_X0 + S.CROSS_WALK   # the cross street's road
    rx1 = S.CROSS_X1 - S.CROSS_WALK
    # Road: the main street and the cross street's roadway.
    y = S.ROAD_Y
    b.quad(V(x0, y, S.NEAR_CURB_Z), V(x1, y, S.NEAR_CURB_Z), V(x1, y, S.FAR_CURB_Z), V(x0, y, S.FAR_CURB_Z), "Asphalt", col=ASPHALT)
    b.quad(V(rx0, y, S.FAR_CURB_Z), V(rx1, y, S.FAR_CURB_Z), V(rx1, y, S.CROSS_END_Z), V(rx0, y, S.CROSS_END_Z), "Asphalt", col=ASPHALT)
    # Beyond the ends of the street: more ground, so nothing shows through at a glance.
    b.quad(V(x0 - 300, y - 0.05, 40), V(x1 + 300, y - 0.05, 40), V(x1 + 300, y - 0.05, -900), V(x0 - 300, y - 0.05, -900),
           "Asphalt", col=lin((0.16, 0.16, 0.17)))

    # Our sidewalk and the far one (broken by the cross street).
    _walk(b, x0, x1, S.NEAR_CURB_Z, S.OUR_FACADE_Z)
    _curb_x(b, x0, x1, S.NEAR_CURB_Z, -1)
    _walk(b, x0, rx0, S.FAR_FACADE_Z, S.FAR_CURB_Z)
    _walk(b, rx1, x1, S.FAR_FACADE_Z, S.FAR_CURB_Z)
    _curb_x(b, x0, rx0, S.FAR_CURB_Z, 1)
    _curb_x(b, rx1, x1, S.FAR_CURB_Z, 1)
    # The cross street's sidewalks.
    _walk(b, S.CROSS_X0, rx0, S.CROSS_END_Z, S.FAR_FACADE_Z)
    _walk(b, rx1, S.CROSS_X1, S.CROSS_END_Z, S.FAR_FACADE_Z)
    _curb_z(b, S.CROSS_END_Z, S.FAR_CURB_Z, rx0, 1)
    _curb_z(b, S.CROSS_END_Z, S.FAR_CURB_Z, rx1, -1)

    # Markings: a double yellow centre line, parking lane edges, the crossing.
    zc = S.CENTRE_Z
    _stripe(b, x0, x1, zc - 0.16, zc - 0.06, PAINT_YELLOW)
    _stripe(b, x0, x1, zc + 0.06, zc + 0.16, PAINT_YELLOW)
    for z in (S.NEAR_CURB_Z - S.PARKING, S.FAR_CURB_Z + S.PARKING):
        x = x0
        while x < x1:
            # Short ticks marking out the parking spaces.
            _stripe(b, x, x + 0.1, min(z, z + (0.9 if z > zc else -0.9)), max(z, z + (0.9 if z > zc else -0.9)))
            x += 6.2
        _stripe(b, x0, x1, z - 0.05, z + 0.05)
    # Zebra crossing over the main street, lined up with the cross street.
    for k in range(9):
        z = S.NEAR_CURB_Z - 0.6 - k * 1.15
        _stripe(b, rx0 + 0.3, rx1 - 0.3, z - 0.55, z)
    # And across the mouth of the cross street, with a stop line.
    for k in range(int((rx1 - rx0 - 0.6) / 0.9)):
        x = rx0 + 0.3 + k * 0.9
        _stripe(b, x, x + 0.5, S.FAR_FACADE_Z - 3.2, S.FAR_FACADE_Z - 0.4)
    _stripe(b, (rx0 + rx1) / 2, rx1 - 0.2, S.FAR_FACADE_Z - 4.2, S.FAR_FACADE_Z - 3.8)
    _stripe(b, (rx0 + rx1) / 2 - 0.08, (rx0 + rx1) / 2 + 0.08, S.CROSS_END_Z, S.FAR_FACADE_Z - 4.2, PAINT_YELLOW)

    # Manholes and drains.
    iron = lin((0.12, 0.12, 0.12))
    for x, z in ((-7.5, zc + 1.6), (6.0, zc - 1.8), (-31.0, zc + 1.4), (27.0, zc - 1.2), (14.0, -45.0)):
        _disc(b, x, z, 0.33, "Grate", iron)
    for x in range(int(x0), int(x1), 23):
        for z, d in ((S.NEAR_CURB_Z - 0.02, -1), (S.FAR_CURB_Z + 0.02, 1)):
            b.box((x, S.ROAD_Y + 0.001, min(z, z + d * 0.4)), (x + 0.9, S.ROAD_Y + 0.006, max(z, z + d * 0.4)), "Grate",
                  col=iron, skip=("bottom",))

    # Tree pits in our sidewalk and the far one (trees themselves are props).
    soil = lin((0.18, 0.13, 0.1))
    for (x, z) in layout["trees"]:
        b.box((x - 0.7, S.WALK_Y - 0.08, z - 0.6), (x + 0.7, S.WALK_Y + 0.004, z + 0.6), "Soil", col=soil,
              skip=("bottom",))
        # A little fence around it.
        iron2 = lin((0.07, 0.07, 0.08))
        hx, hz = 0.74, 0.64
        for (ax, az, bx, bz) in ((x - hx, z - hz, x + hx, z - hz), (x + hx, z - hz, x + hx, z + hz),
                                 (x + hx, z + hz, x - hx, z + hz), (x - hx, z + hz, x - hx, z - hz)):
            b.tube([V(ax, S.WALK_Y + 0.42, az), V(bx, S.WALK_Y + 0.42, bz)], 0.012, "Iron", col=iron2, sides=4)
        for (px, pz) in ((x - hx, z - hz), (x + hx, z - hz), (x + hx, z + hz), (x - hx, z + hz)):
            b.box((px - 0.015, S.WALK_Y, pz - 0.015), (px + 0.015, S.WALK_Y + 0.45, pz + 0.015), "Iron", col=iron2)

    # Outside our window: the stone sill and the brick around the opening.
    sill = lin((0.74, 0.7, 0.62))
    wl, wr = -0.15 - 0.95, -0.15 + 0.95
    b.box((wl - 0.12, 0.83, S.OUR_FACADE_Z - 0.1), (wr + 0.12, 0.93, S.OUR_FACADE_Z + 0.001), "Stone", col=sill,
          skip=("back",))
