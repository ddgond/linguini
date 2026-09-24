"""Downtown in the distance: towers a few hundred metres off, over the roofs.
They're plain boxes with setbacks and crowns; the "Skyline" shader draws their
window grid (UV in metres, Col.r a seed, Col.g the window style)."""

import math

from builder import V, lin

TONES = [(0.55, 0.57, 0.6), (0.5, 0.52, 0.56), (0.62, 0.6, 0.56), (0.44, 0.47, 0.52), (0.58, 0.55, 0.5)]


def tower(b, x, z, w, d, h, rng, layout):
    col = lin(rng.choice(TONES))
    seed = rng.random()
    style = rng.choice([0.0, 0.25, 0.5, 0.75])
    data = (seed, style)
    y = -6.4
    tiers = rng.choice([1, 1, 2, 3])
    ww, dd, yy = w, d, y
    for t in range(tiers):
        th = h * ([1.0], [0.7, 0.3], [0.55, 0.28, 0.17])[tiers - 1][t]
        b.box((x - ww / 2, yy, z - dd / 2), (x + ww / 2, yy + th, z + dd / 2), "Skyline", col=col, skip=("bottom",),
              uv2=data)
        yy += th
        ww *= rng.uniform(0.6, 0.8)
        dd *= rng.uniform(0.6, 0.8)
    crown = rng.random()
    if crown < 0.25:
        b.cylinder((x, yy, z), h * 0.12, 0.8, "Metal", col=lin((0.6, 0.6, 0.6)), sides=6, radius_top=0.05)
        layout["beacons"].append([round(x, 2), round(yy + h * 0.12, 2), round(z, 2)])
    elif crown < 0.45:
        # A pyramid cap.
        b.cylinder((x, yy, z), min(ww, dd) * 0.6, max(ww, dd) * 0.7, "Skyline", col=col, sides=4, radius_top=0.3,
                   uv2=(seed, 1.0))
    elif crown < 0.7:
        b.box((x - ww * 0.3, yy, z - dd * 0.3), (x + ww * 0.3, yy + 4.0, z + dd * 0.3), "Metal", col=lin((0.35, 0.35, 0.36)),
              skip=("bottom",))
        layout["beacons"].append([round(x, 2), round(yy + 4.2, 2), round(z, 2)])
    return yy


def build(b, rng, layout):
    # A scatter of towers across a wide arc behind the neighbourhood, taller
    # toward the middle-right (downtown), shorter and hazier at the sides.
    placed = []
    for i in range(70):
        for _ in range(20):
            x = rng.uniform(-700, 800)
            z = rng.uniform(-900, -260)
            if all((x - px) ** 2 + (z - pz) ** 2 > 60 ** 2 for px, pz in placed):
                break
        placed.append((x, z))
        core = math.exp(-((x - 120) / 380) ** 2)
        h = rng.uniform(35, 70) + core * rng.uniform(40, 170)
        w = rng.uniform(22, 45)
        d = rng.uniform(22, 45)
        tower(b, x, z, w, d, h, rng, layout)
    # Low sprawl in between, so the towers don't stand on nothing.
    for i in range(160):
        x = rng.uniform(-800, 900)
        z = rng.uniform(-240, -120)
        if -40 < x < 60 and z > -200:
            continue
        w, d, h = rng.uniform(15, 40), rng.uniform(15, 40), rng.uniform(12, 30)
        b.box((x - w / 2, -6.4, z - d / 2), (x + w / 2, -6.4 + h, z + d / 2), "Skyline", col=lin(rng.choice(TONES)),
              skip=("bottom",), uv2=(rng.random(), 0.0))
