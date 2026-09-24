"""Street furniture and life: lamps, trees, parked cars (and the car templates
the game drives past), the traffic signals, utility poles and their wires,
hydrants, bins, a mailbox, a bike rack, café tables and street signs."""

import math

from mathutils import Vector

from builder import V, lin
import cars
import street_layout as S

IRON = lin((0.06, 0.07, 0.07))
LAMP_GREEN = lin((0.1, 0.16, 0.13))


# --- lamps -----------------------------------------------------------------------

def street_lamp(b, x, z, facing, layout):
    """A cast-iron post with a curved arm and a hanging lantern. `facing` is the
    (x, z) direction the arm reaches, out over the road."""
    fx, fz = facing
    y = S.WALK_Y
    col = LAMP_GREEN
    # Fluted base, post and a collar.
    b.cylinder((x, y, z), 0.9, 0.2, "Iron", col=col, sides=10, radius_top=0.1)
    b.cylinder((x, y + 0.9, z), 0.1, 0.13, "Iron", col=col, sides=10)
    b.cylinder((x, y + 1.0, z), 4.2, 0.075, "Iron", col=col, sides=8, radius_top=0.055)
    top = y + 5.2
    b.cylinder((x, top - 0.05, z), 0.12, 0.09, "Iron", col=col, sides=8)
    # The arm: up and over in a curve.
    reach = 1.3
    pts = []
    for i in range(10):
        t = i / 9
        a = t * math.pi * 0.62
        out = (1 - math.cos(a)) * reach * 0.7 + t * reach * 0.3
        pts.append(V(x + fx * out, top + math.sin(a) * 0.45, z + fz * out))
    b.tube(pts, 0.035, "Iron", col=col, sides=6)
    end = pts[-1]
    # Lantern: a cap, glass, a finial and a bottom.
    lx, ly, lz = end.x, end.y - 0.12, end.z
    b.cylinder((lx, ly - 0.02, lz), 0.14, 0.24, "Iron", col=col, sides=8, radius_top=0.04)
    b.cylinder((lx, ly - 0.5, lz), 0.48, 0.14, "Lamp", col=lin((1.0, 0.86, 0.62)), sides=8, radius_top=0.2)
    b.cylinder((lx, ly - 0.56, lz), 0.06, 0.08, "Iron", col=col, sides=8, radius_top=0.14, bottom=True)
    layout["lamps"].append([round(lx, 3), round(ly - 0.3, 3), round(lz, 3)])


# --- trees -----------------------------------------------------------------------

def tree(b, leaves, x, z, rng, height=9.5, spread=3.0, tint=(1.0, 1.0, 1.0)):
    """A street tree: a trunk forking into limbs, twigs, and clusters of leaf
    cards. Leaf cards carry UV2 = (sway weight, phase) for the shader."""
    y0 = S.WALK_Y
    bark = lin((0.3, 0.26, 0.22))
    trunk_h = height * 0.32
    lean = V(rng.uniform(-0.2, 0.2), 1.0, rng.uniform(-0.2, 0.2)).normalized()
    top = V(x, y0, z) + lean * trunk_h
    b.tube([V(x, y0 - 0.05, z), V(x, y0 + trunk_h * 0.5, z) + lean * 0.05, top], [0.2, 0.17, 0.14], "Bark", col=bark,
           sides=9, uv2=[(0.0, 0.0), (0.0, 0.0)])
    clusters = []

    def limb(start, direction, length, radius, depth):
        pts = [start]
        d = direction.normalized()
        p = start
        n = 4
        for i in range(n):
            d = (d + V(rng.uniform(-0.25, 0.25), rng.uniform(-0.05, 0.2), rng.uniform(-0.25, 0.25))).normalized()
            p = p + d * (length / n)
            pts.append(p)
        radii = [radius * (1.0 - 0.6 * i / n) for i in range(n + 1)]
        sway = [((pt.y - y0) / height * 0.4, 0.0) for pt in pts[:-1]]
        b.tube(pts, radii, "Bark", col=bark, sides=6 if depth == 0 else 4, uv2=sway)
        if depth < 2:
            for k in range(rng.randint(2, 3)):
                i = rng.randint(2, n)
                nd = (d + V(rng.uniform(-1, 1), rng.uniform(0.1, 0.8), rng.uniform(-1, 1)) * 0.9).normalized()
                limb(pts[i], nd, length * rng.uniform(0.5, 0.7), radii[i] * 0.7, depth + 1)
        else:
            clusters.append(pts[-1])
            clusters.append(pts[len(pts) // 2])

    for k in range(rng.randint(4, 6)):
        a = 2 * math.pi * k / 5 + rng.uniform(-0.4, 0.4)
        d = V(math.cos(a) * 0.8, 1.0, math.sin(a) * 0.8)
        limb(top, d, spread * rng.uniform(0.75, 1.0), 0.1, 0)
    # Fill the crown's gaps with a few extra clusters inside it.
    centre = top + V(0, (height - trunk_h) * 0.45, 0)
    for _ in range(8):
        clusters.append(centre + V(rng.uniform(-1, 1) * spread * 0.6, rng.uniform(-0.6, 1.0) * spread * 0.45,
                                   rng.uniform(-1, 1) * spread * 0.6))
    for c in clusters:
        leaf_cluster(leaves, c, rng, (c.y - y0) / height, tint)


def leaf_cluster(b, centre, rng, weight, tint, cards=7, size=0.9):
    """Leaf cards scattered around a point, facing every which way. The texture
    holds a spray of leaves; alpha cuts them out."""
    for _ in range(cards):
        off = V(rng.uniform(-1, 1), rng.uniform(-0.6, 0.8), rng.uniform(-1, 1)) * 0.7
        c = centre + off
        # A random orientation.
        n = V(rng.uniform(-1, 1), rng.uniform(-0.4, 1), rng.uniform(-1, 1)).normalized()
        t = n.cross(V(0, 1, 0) if abs(n.y) < 0.9 else V(1, 0, 0)).normalized()
        bt = n.cross(t).normalized()
        a = rng.uniform(0, math.pi * 2)
        t, bt = t * math.cos(a) + bt * math.sin(a), bt * math.cos(a) - t * math.sin(a)
        h = size * rng.uniform(0.75, 1.2) / 2
        pts = [c - t * h - bt * h, c + t * h - bt * h, c + t * h + bt * h, c - t * h + bt * h]
        shade = rng.uniform(0.75, 1.1)
        col = (tint[0] * shade, tint[1] * shade, tint[2] * shade, 1.0)
        # Each card picks one quarter of the 2x2 leaf atlas.
        qu, qv = rng.randint(0, 1) * 0.5, rng.randint(0, 1) * 0.5
        uv = [(qu, qv), (qu + 0.5, qv), (qu + 0.5, qv + 0.5), (qu, qv + 0.5)]
        phase = rng.random()
        b.face(pts, "LeafCards", col=col, uv=uv, uv2=[(weight, phase)] * 4)


def leaf_texture():
    """A 2x2 atlas of leaf sprays (RGBA, alpha = leaf), drawn with numpy."""
    import numpy as np

    size = 512
    img = np.zeros((size, size, 4), np.float32)
    rng = np.random.default_rng(7)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    for q in range(4):
        ox, oy = (q % 2) * 256, (q // 2) * 256
        for _ in range(26):
            cx, cy = ox + rng.uniform(40, 216), oy + rng.uniform(40, 216)
            ang = rng.uniform(0, math.pi * 2)
            ln, wd = rng.uniform(30, 48), rng.uniform(13, 20)
            dx, dy = xx - cx, yy - cy
            u = dx * math.cos(ang) + dy * math.sin(ang)
            v = -dx * math.sin(ang) + dy * math.cos(ang)
            # A pointed leaf: an ellipse pinched toward its tip.
            t = np.clip(u / ln, -1, 1)
            half = wd * np.sqrt(np.clip(1 - t * t, 0, 1)) * (1 - 0.35 * np.clip(t, 0, 1))
            inside = (np.abs(u) < ln) & (np.abs(v) < half)
            vein = np.exp(-(v / 1.3) ** 2) * (np.abs(u) < ln * 0.9)
            g = rng.uniform(0.75, 1.0)
            base = np.array([0.22, 0.42, 0.14]) * g
            light = 0.8 + 0.3 * (v / (wd + 1e-3))
            colour = base[None, None, :] * light[..., None] * (1 + 0.35 * vein[..., None])
            img[..., :3] = np.where(inside[..., None], colour, img[..., :3])
            img[..., 3] = np.where(inside, 1.0, img[..., 3])
        # A few twigs.
        for _ in range(3):
            x0, y0 = ox + rng.uniform(60, 196), oy + rng.uniform(60, 196)
            x1, y1 = ox + 128, oy + 128
            d = np.abs((y1 - y0) * xx - (x1 - x0) * yy + x1 * y0 - y1 * x0) / math.hypot(x1 - x0, y1 - y0)
            on = (d < 1.6) & (xx >= min(x0, x1)) & (xx <= max(x0, x1)) & (yy >= min(y0, y1) - 1) & (yy <= max(y0, y1) + 1)
            img[on] = (0.25, 0.2, 0.15, 1.0)
    # Bleed colour into the transparent parts, so mipmaps don't go dark at the edges.
    avg = img[..., :3][img[..., 3] > 0.5].mean(axis=0)
    img[..., :3] = np.where(img[..., 3:4] > 0.5, img[..., :3], avg)
    return img


# --- cars ------------------------------------------------------------------------

CAR_COLOURS = [(0.86, 0.86, 0.85), (0.62, 0.64, 0.66), (0.07, 0.07, 0.08), (0.28, 0.3, 0.32), (0.13, 0.2, 0.36),
               (0.55, 0.1, 0.09), (0.16, 0.27, 0.2), (0.7, 0.62, 0.5), (0.45, 0.6, 0.72), (0.9, 0.9, 0.9)]


def parked_cars(b, rng, layout):
    """Rows of parked cars on both parking lanes, with gaps and a driveway."""
    near_z = S.NEAR_CURB_Z - 1.05
    far_z = S.FAR_CURB_Z + 1.05
    skip = [(S.CROSS_X0 - 2.0, S.CROSS_X1 + 8.0)]  # the crossing and the hydrant
    for z, yaw in ((near_z, 0.0), (far_z, math.pi)):
        x = S.STREET_X[0] + 5
        while x < S.STREET_X[1] - 6:
            kind = rng.choice(["sedan", "sedan", "hatch", "suv", "van", "hatch", "suv"])
            L = cars.TYPES[kind]["length"]
            if any(a - L < x < c for a, c in skip) or (z == near_z and -3.5 < x < 1.8):
                x += 1.0
                continue
            if rng.random() < 0.18:
                x += rng.uniform(4, 7)  # an empty space
                continue
            taxi = kind == "sedan" and rng.random() < 0.15
            paint = (0.95, 0.72, 0.1) if taxi else rng.choice(CAR_COLOURS)
            cars.place(b, kind, x + L / 2, z + rng.uniform(-0.1, 0.1), yaw + rng.uniform(-0.02, 0.02), paint, taxi,
                       y=S.ROAD_Y)
            x += L + rng.uniform(0.7, 1.6)


# --- signals, poles, wires ---------------------------------------------------------

def traffic_signal(b, x, z, faces, layout):
    """A signal pole at the corner with heads facing along `faces` (unit x/z
    vectors). Lens colours are in Col.r (0 red, 0.5 amber, 1 green); Col.g
    says which road the head serves (0 main street, 1 cross street)."""
    y = S.WALK_Y
    pole = lin((0.18, 0.18, 0.18))
    b.cylinder((x, y, z), 4.2, 0.09, "Metal", col=pole, sides=8)
    b.cylinder((x, y, z), 0.5, 0.16, "Metal", col=pole, sides=8)
    for k, (dx, dz, road) in enumerate(faces):
        hy = y + 3.1 + 0.02 * k
        centre = V(x + dx * 0.25, hy, z + dz * 0.25)
        yaw = math.atan2(dx, dz)
        b.oriented_box((centre.x, centre.y, centre.z), (0.32, 0.95, 0.24), yaw, "SignalHousing", col=lin((0.14, 0.14, 0.1)))
        for i, lamp in enumerate((0.0, 0.5, 1.0)):
            ly = hy + 0.3 - i * 0.3
            p = V(centre.x + dx * 0.125, ly, centre.z + dz * 0.125)
            n = V(dx, 0, dz)
            side = V(0, 1, 0).cross(n).normalized()
            ring = [p + (side * math.cos(2 * math.pi * j / 10) + V(0, 1, 0) * math.sin(2 * math.pi * j / 10)) * 0.11
                    for j in range(10)]
            b.face(ring if (side.cross(V(0, 1, 0))).dot(n) < 0 else list(reversed(ring)), "Signal",
                   col=(lamp, float(road), 0.0, 1.0))
            # A visor over each lens.
            b.oriented_box((p.x + dx * 0.08, ly + 0.11, p.z + dz * 0.08), (0.26, 0.02, 0.16), yaw, "SignalHousing",
                           col=lin((0.14, 0.14, 0.1)))
        layout["signals"].append({"pos": [round(centre.x + dx * 0.3, 3), round(hy, 3), round(centre.z + dz * 0.3, 3)],
                                  "road": road})
    # Pedestrian button box and a street name sign on top.
    b.cbox((x, y + 1.1, z), (0.1, 0.16, 0.1), "SignalHousing", col=lin((0.7, 0.62, 0.2)))


def street_sign(b, x, z, texts):
    """The green corner signs: the main street along x, the cross street along z."""
    y = S.WALK_Y + 4.4
    green = lin((0.05, 0.36, 0.2))
    b.cylinder((x, S.WALK_Y, z), 4.6, 0.04, "Metal", col=lin((0.5, 0.5, 0.5)), sides=6)
    b.cbox((x, y, z), (1.4, 0.26, 0.03), "Metal", col=green)
    b.cbox((x, y + 0.3, z), (0.03, 0.26, 1.4), "Metal", col=green)
    from facades import Frame
    texts.append({"text": "LINGUINI ST", "frame": Frame((x, 0, z + 0.016), (1, 0, 0), (0, 0, 1)), "u": 0, "y": y - 0.08,
                  "w": 0.0, "size": 0.17, "mat": "SignPaint", "col": lin((0.95, 0.95, 0.92))})
    texts.append({"text": "TORTELLINI AVE", "frame": Frame((x + 0.016, 0, z), (0, 0, -1), (1, 0, 0)), "u": 0,
                  "y": y + 0.22, "w": 0.0, "size": 0.15, "mat": "SignPaint", "col": lin((0.95, 0.95, 0.92))})


def catenary(a, c, sag, n=16):
    return [a.lerp(c, i / n) - V(0, sag * 4 * (i / n) * (1 - i / n), 0) for i in range(n + 1)]


def utility_poles(b, rng, layout):
    """Wooden poles along the far curb, wires between them and service drops to
    the buildings; one drop crosses the street to our building, just left of
    the window."""
    wood = lin((0.33, 0.25, 0.19))
    wire = lin((0.03, 0.03, 0.03))
    z = S.FAR_CURB_Z - 0.45
    xs = [-58.0, -30.0, -2.5, 25.0, 52.0, 80.0]
    tops = []
    for x in xs:
        y = S.WALK_Y
        b.cylinder((x, y, z), 10.5, 0.15, "Wood", col=wood, sides=8, radius_top=0.11)
        top = y + 10.5
        # Cross arm with insulators.
        b.cbox((x, top - 0.5, z), (2.2, 0.1, 0.1), "Wood", col=wood)
        for dx in (-0.9, -0.3, 0.3, 0.9):
            b.cylinder((x + dx, top - 0.45, z), 0.14, 0.035, "Stone", col=lin((0.6, 0.62, 0.6)), sides=6)
        # A transformer on some.
        if x in (-2.5, 52.0):
            b.cylinder((x + 0.35, top - 2.4, z - 0.1), 1.0, 0.28, "Metal", col=lin((0.45, 0.47, 0.46)), sides=10)
        tops.append((x, top))
    wires = []
    for (x0, t0), (x1, t1) in zip(tops, tops[1:]):
        for dx in (-0.9, -0.3, 0.3, 0.9):
            wires.append(catenary(V(x0 + dx, t0 - 0.36, z), V(x1 + dx, t1 - 0.36, z), rng.uniform(0.35, 0.55)))
        # Lower telephone/cable lines.
        for dy in (2.3, 2.7):
            wires.append(catenary(V(x0, t0 - dy, z), V(x1, t1 - dy, z), rng.uniform(0.5, 0.8)))
    # Drops across the street to our building: two from the pole nearest the window.
    x0, t0 = tops[2]
    for (tx, ty, sag) in ((-3.2, 2.35, 0.55), (-3.3, 1.9, 0.75)):
        wires.append(catenary(V(x0, t0 - 2.5, z), V(tx, ty, S.OUR_FACADE_Z - 0.05), sag, 24))
    # Drops to the far row.
    for x, t in tops:
        for dx in (-4.5, 3.5):
            wires.append(catenary(V(x, t - 2.6, z), V(x + dx, t - 3.4 + rng.uniform(-0.5, 0.5), S.FAR_FACADE_Z + 0.05),
                                  0.25, 10))
    for w in wires:
        b.tube(w, 0.011, "Wire", col=wire, sides=4)


# --- small things --------------------------------------------------------------------

def hydrant(b, x, z):
    red = lin((0.72, 0.12, 0.08))
    y = S.WALK_Y
    b.cylinder((x, y, z), 0.08, 0.17, "MetalPaint", col=red, sides=10)
    b.cylinder((x, y + 0.08, z), 0.5, 0.12, "MetalPaint", col=red, sides=10)
    b.cylinder((x, y + 0.58, z), 0.06, 0.15, "MetalPaint", col=red, sides=10)
    b.cylinder((x, y + 0.64, z), 0.12, 0.11, "MetalPaint", col=red, sides=10, radius_top=0.03)
    for d in (-1, 1):
        b.cylinder((x, y + 0.38, z), 0.12 * d, 0.045, "MetalPaint", col=red, sides=6, axis="x")
    b.cylinder((x, y + 0.36, z), 0.13, 0.06, "MetalPaint", col=red, sides=6, axis="z")


def bin_(b, x, z):
    green = lin((0.12, 0.25, 0.16))
    y = S.WALK_Y
    b.cylinder((x, y, z), 0.9, 0.3, "MetalPaint", col=green, sides=12, top=False, radius_top=0.33)
    b.cylinder((x, y + 0.88, z), 0.05, 0.34, "MetalPaint", col=green, sides=12)
    b.cylinder((x, y + 0.9, z), 0.03, 0.24, "Rubber", col=lin((0.05, 0.05, 0.05)), sides=12)


def mailbox(b, x, z):
    blue = lin((0.1, 0.2, 0.45))
    y = S.WALK_Y
    for dx in (-0.2, 0.2):
        for dz in (-0.18, 0.18):
            b.cbox((x + dx, y + 0.12, z + dz), (0.05, 0.24, 0.05), "MetalPaint", col=blue)
    b.cbox((x, y + 0.72, z), (0.5, 0.96, 0.45), "MetalPaint", col=blue)
    b.cylinder((x - 0.25, y + 1.2, z), 0.5, 0.225, "MetalPaint", col=blue, sides=12, axis="x")


def bike_rack(b, x, z, rng, with_bike=True):
    steel = lin((0.6, 0.6, 0.62))
    y = S.WALK_Y
    for k in range(3):
        xx = x + k * 0.8
        pts = [V(xx, y, z - 0.35)] + [V(xx, y + 0.6 + 0.3 * math.sin(math.pi * i / 8), z - 0.35 * math.cos(math.pi * i / 8))
                                       for i in range(9)] + [V(xx, y, z + 0.35)]
        b.tube(pts, 0.025, "Metal", col=steel, sides=5)
    if with_bike:
        frame = lin(rng.choice([(0.7, 0.15, 0.1), (0.1, 0.4, 0.6), (0.15, 0.15, 0.15)]))
        bx = x + 0.4
        for dz in (-0.55, 0.52):
            pts = [V(bx + 0.02 * math.cos(2 * math.pi * i / 16), y + 0.34 + 0.34 * math.sin(2 * math.pi * i / 16),
                     z + dz + 0.34 * math.cos(2 * math.pi * i / 16)) for i in range(17)]
            b.tube(pts, 0.018, "Rubber", col=lin((0.03, 0.03, 0.03)), sides=4)
        a, c_, s_, h = V(bx, y + 0.34, z - 0.55), V(bx, y + 0.34, z + 0.52), V(bx, y + 0.85, z - 0.2), V(bx, y + 0.9, z + 0.35)
        bb = V(bx, y + 0.34, z - 0.05)
        for p0, p1 in ((a, bb), (bb, s_), (s_, a), (s_, h), (h, bb), (h, c_)):
            b.tube([p0, p1], 0.02, "MetalPaint", col=frame, sides=4)
        b.tube([h + V(-0.25, 0.1, 0), h + V(0.25, 0.1, 0)], 0.015, "Rubber", col=lin((0.05, 0.05, 0.05)), sides=4)
        b.cbox((bx, y + 0.93, z - 0.2), (0.1, 0.04, 0.24), "Rubber", col=lin((0.05, 0.05, 0.05)))


def cafe_tables(b, fr, u0, u1, rng):
    """Bistro tables and chairs on the sidewalk under the café awning."""
    y = S.WALK_Y
    metal = lin((0.1, 0.1, 0.1))
    top = lin((0.8, 0.78, 0.72))
    for k in range(3):
        u = u0 + 1.0 + k * (u1 - u0 - 2.0) / 2
        p = fr.p(u, y, 1.1)
        b.cylinder((p.x, y, p.z), 0.72, 0.03, "Metal", col=metal, sides=6)
        b.cylinder((p.x, y, p.z), 0.03, 0.22, "Metal", col=metal, sides=8)
        b.cylinder((p.x, y + 0.72, p.z), 0.03, 0.32, "Stone", col=top, sides=14)
        for side in (-1, 1):
            c = fr.p(u + side * 0.55, y, 1.1 + rng.uniform(-0.15, 0.15))
            b.cbox((c.x, y + 0.45, c.z), (0.4, 0.03, 0.4), "Metal", col=metal)
            for dx in (-0.17, 0.17):
                for dz in (-0.17, 0.17):
                    b.cbox((c.x + dx, y + 0.22, c.z + dz), (0.025, 0.45, 0.025), "Metal", col=metal)
            back = fr.p(u + side * 0.75, y, 1.1)
            b.cbox((back.x, y + 0.7, back.z), (0.025 if abs(fr.r.x) > 0.5 else 0.4, 0.5, 0.4 if abs(fr.r.x) > 0.5 else 0.025),
                   "Metal", col=metal)


def aframe_sign(b, x, z, texts, text):
    board = lin((0.1, 0.1, 0.1))
    y = S.WALK_Y
    for dz, tilt in ((-0.14, 1), (0.14, -1)):
        b.face([V(x - 0.3, y, z + dz * 1.4), V(x + 0.3, y, z + dz * 1.4), V(x + 0.3, y + 0.9, z), V(x - 0.3, y + 0.9, z)]
               if tilt < 0 else
               [V(x + 0.3, y, z + dz * 1.4), V(x - 0.3, y, z + dz * 1.4), V(x - 0.3, y + 0.9, z), V(x + 0.3, y + 0.9, z)],
               "Wood", col=board)
    from facades import Frame
    fr = Frame((x, 0, z + 0.1), (1, 0, 0), (0, 0, 1))
    fr.n = V(0, 0.15, 1).normalized()
    texts.append({"text": text, "frame": fr, "u": 0, "y": y + 0.5, "w": 0.0, "size": 0.1, "mat": "SignPaint",
                  "col": lin((0.95, 0.95, 0.9))})


def planter(b, x, z, rng):
    y = S.WALK_Y
    b.cbox((x, y + 0.3, z), (0.9, 0.6, 0.5), "Wood", col=lin((0.35, 0.24, 0.16)))
    for _ in range(9):
        b.cbox((x + rng.uniform(-0.35, 0.35), y + 0.65 + rng.uniform(0, 0.25), z + rng.uniform(-0.18, 0.18)),
               (0.18, 0.2, 0.18), "Foliage", col=lin(rng.choice([(0.25, 0.45, 0.2), (0.3, 0.52, 0.24), (0.9, 0.4, 0.5)])))
