"""The buildings: brick rowhouses with stoops, shops with awnings, a painted
row, a taller walk-up with fire escapes, a low laundromat, and the plainer
blocks behind them.

Each building is drawn in a Frame: u runs along the facade (to the right, seen
from the street), y is up, and w points out of the facade toward the street
(w < 0 is inside). Frames are right-angle turns, so boxes stay axis-aligned.

Windows are holes in the facade with a reveal, a frame and a glass pane the
Godot shader fills with a room ("Window": UV 0..1 across the pane, UV2 = the
pane's size in metres, Col = seeds: r room, g light, b kind).
"""

import math
import random

from mathutils import Vector

from builder import V, lin
import street_layout as S

WALL_D = 0.3        # facade thickness at openings (reveal depth)

BRICKS = {
    "red": (0.56, 0.24, 0.18), "brown": (0.44, 0.28, 0.21), "oxblood": (0.4, 0.17, 0.14),
    "tan": (0.74, 0.62, 0.45), "brownstone": (0.45, 0.32, 0.26), "grey": (0.5, 0.48, 0.46),
    "orange": (0.62, 0.34, 0.22),
}
PAINTS = {
    "cream": (0.86, 0.8, 0.68), "white": (0.86, 0.86, 0.83), "sage": (0.56, 0.63, 0.53),
    "blush": (0.8, 0.6, 0.55), "navy": (0.26, 0.31, 0.41), "mustard": (0.8, 0.64, 0.33),
    "teal": (0.3, 0.5, 0.52), "lilac": (0.62, 0.58, 0.7),
}
TRIMS = {
    "white": (0.9, 0.9, 0.86), "cream": (0.88, 0.84, 0.74), "black": (0.07, 0.07, 0.08),
    "green": (0.12, 0.24, 0.18), "oxblood": (0.33, 0.1, 0.09), "grey": (0.42, 0.43, 0.44),
    "navy": (0.13, 0.17, 0.26),
}
STONE = (0.76, 0.72, 0.64)


class Frame:
    def __init__(self, origin, right, out):
        self.o = V(*origin)
        self.r = V(*right)
        self.n = V(*out)
        self.up = V(0, 1, 0)

    def p(self, u, y, w):
        return self.o + self.r * u + self.up * y + self.n * w

    def box(self, b, u0, u1, y0, y1, w0, w1, mat, col, skip=(), uv2=None):
        a = self.p(u0, y0, w0)
        c = self.p(u1, y1, w1)
        lo = (min(a.x, c.x), min(a.y, c.y), min(a.z, c.z))
        hi = (max(a.x, c.x), max(a.y, c.y), max(a.z, c.z))
        b.box(lo, hi, mat, col=col, skip=[self._world_side(s) for s in skip], uv2=uv2)

    def _world_side(self, local):
        d = {"front": self.n, "back": -self.n, "right": self.r, "left": -self.r,
             "top": self.up, "bottom": -self.up}[local]
        if d.y > 0.5:
            return "top"
        if d.y < -0.5:
            return "bottom"
        if abs(d.z) > 0.5:
            return "front" if d.z > 0 else "back"
        return "right" if d.x > 0 else "left"

    def quad(self, b, pts, mat, **kw):
        b.face([self.p(*q) for q in pts], mat, **kw)

    def tube(self, b, pts, radius, mat, col, sides=6):
        b.tube([self.p(*q) for q in pts], radius, mat, col=col, sides=sides)


# --- walls with holes --------------------------------------------------------

def wall(b, fr, u0, u1, y0, y1, holes, mat, col, w=0.0):
    """The facade plane u0..u1 x y0..y1 at depth w, minus rectangular holes
    (u0, u1, y0, y1): split into bands at every hole edge, and each band into
    the runs between holes."""
    ys = sorted({y0, y1, *[h[2] for h in holes], *[h[3] for h in holes]})
    ys = [y for y in ys if y0 <= y <= y1]
    for ya, yb in zip(ys, ys[1:]):
        if yb - ya < 1e-4:
            continue
        mid = (ya + yb) / 2
        cuts = sorted((h[0], h[1]) for h in holes if h[2] < mid < h[3])
        u = u0
        for ha, hb in cuts + [(u1, u1)]:
            if ha - u > 1e-4:
                fr.quad(b, [(u, ya, w), (ha, ya, w), (ha, yb, w), (u, yb, w)], mat, col=col)
            u = max(u, hb)


def railing(b, fr, pts, col):
    """A panel of iron bars: one quad the "Railing" shader cuts into vertical
    bars (UV in metres), so a fence costs two triangles, not hundreds."""
    fr.quad(b, pts, "Railing", col=col)


def reveal(b, fr, u0, u1, y0, y1, depth, mat, col, sill=True):
    """The inside faces of an opening, from the facade back to `depth`."""
    d = -depth
    fr.quad(b, [(u0, y0, d), (u0, y0, 0), (u0, y1, 0), (u0, y1, d)], mat, col=col)      # left jamb, faces +u
    fr.quad(b, [(u1, y0, 0), (u1, y0, d), (u1, y1, d), (u1, y1, 0)], mat, col=col)      # right jamb
    fr.quad(b, [(u0, y1, d), (u0, y1, 0), (u1, y1, 0), (u1, y1, d)], mat, col=col)      # head, faces down
    if sill:
        fr.quad(b, [(u0, y0, 0), (u0, y0, d), (u1, y0, d), (u1, y0, 0)], mat, col=col)  # sill, faces up


# --- windows -------------------------------------------------------------------

def pane(b, fr, u0, u1, y0, y1, w, rng, kind=0.0, lit=None):
    """A glass pane the Godot window shader puts a room behind."""
    seed = rng.random()
    light = rng.random() if lit is None else lit
    col = (seed, light, kind, 1.0)
    fr.quad(b, [(u0, y0, w), (u1, y0, w), (u1, y1, w), (u0, y1, w)], "Window",
            col=col, uv=[(0, 0), (1, 0), (1, 1), (0, 1)], uv2=[(u1 - u0, y1 - y0)] * 4)


def window(b, fr, u0, u1, y0, y1, st, rng, depth=WALL_D, wall_mat="Brick", wall_col=None):
    """A sash window in a hole u0..u1 x y0..y1: reveal, frame, meeting rail,
    muntins, glass, a stone sill and a lintel."""
    trim = lin(st["trim"])
    reveal(b, fr, u0, u1, y0, y1, depth, wall_mat, wall_col, sill=False)
    back = -depth
    f = 0.06
    fd = 0.07
    # Frame.
    # (Faces against the reveal or each other are left out.)
    fr.box(b, u0, u1, y1 - f, y1, back, back + fd, "Trim", trim, skip=("back", "left", "right", "top"))
    fr.box(b, u0, u1, y0, y0 + f, back, back + fd, "Trim", trim, skip=("back", "left", "right", "bottom"))
    fr.box(b, u0, u0 + f, y0 + f, y1 - f, back, back + fd, "Trim", trim, skip=("back", "top", "bottom", "left"))
    fr.box(b, u1 - f, u1, y0 + f, y1 - f, back, back + fd, "Trim", trim, skip=("back", "top", "bottom", "right"))
    lod = st.get("lod", 0)
    mid = y0 + (y1 - y0) * st.get("rail", 0.5)
    # Sash rails: the lower sash sits a little proud of the upper one.
    fr.box(b, u0 + f, u1 - f, mid - 0.025, mid + 0.025, back + 0.01, back + fd + 0.02, "Trim", trim,
           skip=("back", "left", "right"))
    for k in range(1, st.get("muntins", 1) if lod == 0 else 1):
        uu = u0 + (u1 - u0) * k / st.get("muntins", 1)
        fr.box(b, uu - 0.012, uu + 0.012, mid, y1 - f, back + 0.01, back + fd - 0.01, "Trim", trim, skip=("back",))
        if st.get("lower_muntins"):
            fr.box(b, uu - 0.012, uu + 0.012, y0 + f, mid, back + 0.03, back + fd + 0.01, "Trim", trim, skip=("back",))
    pane(b, fr, u0 + f, u1 - f, y0 + f, y1 - f, back + 0.035, rng)
    # Stone sill and lintel.
    stone = lin(st.get("stone", STONE))
    fr.box(b, u0 - 0.07, u1 + 0.07, y0 - 0.09, y0, back + 0.02, 0.07, "Stone", stone, skip=("back",))
    lintel = st.get("lintel", "flat")
    if lintel == "flat":
        fr.box(b, u0 - 0.1, u1 + 0.1, y1, y1 + 0.24, -0.02, 0.03, "Stone", stone, skip=("back",))
    elif lintel == "hood":
        # A projecting hood with a little cornice.
        fr.box(b, u0 - 0.12, u1 + 0.12, y1, y1 + 0.22, -0.02, 0.05, "Stone", stone, skip=("back",))
        fr.box(b, u0 - 0.18, u1 + 0.18, y1 + 0.22, y1 + 0.3, -0.02, 0.12, "Stone", stone, skip=("back",))
    elif lintel == "soldier":
        # A soldier course: bricks on end, a shade darker.
        dark = tuple(c * 0.82 for c in wall_col[:3]) + (1.0,)
        fr.box(b, u0 - 0.06, u1 + 0.06, y1, y1 + 0.23, -0.02, 0.015, "Brick", dark, skip=("back",))
    # Now and then something in the window: an air conditioner or a flower box.
    extra = rng.random()
    if lod > 0:
        return
    if extra < st.get("ac", 0.1):
        a = u0 + (u1 - u0) * 0.5
        ac = lin((0.82, 0.82, 0.8))
        fr.box(b, a - 0.33, a + 0.33, y0 + f, y0 + f + 0.38, back - 0.2, back + 0.34, "Metal", ac)
        fr.box(b, a - 0.36, a + 0.36, y0 - 0.02, y0 + f, back, back + 0.4, "Metal", lin((0.3, 0.3, 0.3)))
    elif extra > 1.0 - st.get("flowers", 0.08):
        box_col = lin(rng.choice([(0.35, 0.22, 0.14), (0.2, 0.3, 0.22), (0.7, 0.3, 0.2)]))
        fr.box(b, u0 + 0.02, u1 - 0.02, y0 + 0.0, y0 + 0.2, 0.07, 0.3, "Wood", box_col)
        for i in range(int((u1 - u0) / 0.12)):
            uu = u0 + 0.08 + i * 0.12 + rng.uniform(-0.02, 0.02)
            leaf = lin(rng.choice([(0.25, 0.45, 0.2), (0.3, 0.5, 0.22), (0.85, 0.3, 0.35), (0.9, 0.75, 0.3)]))
            h = rng.uniform(0.1, 0.22)
            fr.box(b, uu - 0.05, uu + 0.05, y0 + 0.2, y0 + 0.2 + h, 0.12, 0.25, "Foliage", leaf)


def door(b, fr, u0, u1, y0, y1, st, rng, depth=0.35, transom=True, wall_mat="Brick", wall_col=None):
    """A panelled front door in a recessed opening, with a transom light."""
    reveal(b, fr, u0, u1, y0, y1, depth, wall_mat, wall_col, sill=False)
    back = -depth
    dcol = lin(st.get("door", (0.2, 0.12, 0.08)))
    trim = lin(st["trim"])
    top = y1 - 0.45 if transom else y1
    fr.box(b, u0, u1, y0, top, back, back + 0.05, "Wood", dcol, skip=("back",))
    # Panels.
    w = u1 - u0
    for row in ((0.12, 0.45), (0.55, 0.92)):
        for col_ in ((0.12, 0.46), (0.54, 0.88)) if w > 0.9 else ((0.15, 0.85),):
            fr.box(b, u0 + w * col_[0], u0 + w * col_[1], y0 + (top - y0) * row[0], y0 + (top - y0) * row[1],
                   back + 0.05, back + 0.07, "Wood", tuple(c * 0.85 for c in dcol[:3]) + (1.0,), skip=("back",))
    # Knob.
    fr.box(b, u1 - 0.12, u1 - 0.08, y0 + 1.0, y0 + 1.05, back + 0.05, back + 0.1, "Brass", lin((0.8, 0.62, 0.3)))
    if transom:
        fr.box(b, u0, u1, top, top + 0.05, back, back + 0.08, "Trim", trim, skip=("back",))
        pane(b, fr, u0 + 0.04, u1 - 0.04, top + 0.05, y1 - 0.04, back + 0.03, rng, kind=0.25)
        fr.box(b, u0, u1, y1 - 0.04, y1, back, back + 0.08, "Trim", trim, skip=("back",))


# --- building parts ------------------------------------------------------------

def cornice(b, fr, u0, u1, y, st, rng, depth=0.5):
    """A bracketed cornice along the top of the facade."""
    c = lin(st.get("cornice_col", st["trim"]))
    dark = tuple(x * 0.75 for x in c[:3]) + (1.0,)
    fr.box(b, u0, u1, y - 0.55, y - 0.2, 0.0, 0.08, "Trim", c)                    # frieze
    fr.box(b, u0 - 0.1, u1 + 0.1, y - 0.2, y, -0.2, depth, "Trim", c)              # corona
    fr.box(b, u0 - 0.12, u1 + 0.12, y, y + 0.08, -0.2, depth + 0.05, "Trim", c)    # crown
    n = max(2, int((u1 - u0) / 0.8))
    for i in range(n + 1):
        uu = u0 + 0.15 + (u1 - u0 - 0.3) * i / n
        fr.box(b, uu - 0.07, uu + 0.07, y - 0.55, y - 0.2, 0.08, depth - 0.05, "Trim", dark, skip=("back", "top"))
    if st.get("lod", 0) == 0:
        # Dentils.
        n = int((u1 - u0) / 0.16)
        for i in range(n):
            uu = u0 + 0.08 + i * (u1 - u0 - 0.16) / max(1, n - 1)
            fr.box(b, uu - 0.035, uu + 0.035, y - 0.3, y - 0.2, 0.08, 0.16, "Trim", c, skip=("back", "top"))


def parapet(b, fr, u0, u1, y, st, height=0.9):
    """A plain parapet with stone coping."""
    fr.box(b, u0, u1, y, y + height, -0.3, 0.0, st["wall_mat"], st["wall_col"], skip=("bottom",))
    fr.box(b, u0 - 0.04, u1 + 0.04, y + height, y + height + 0.08, -0.34, 0.05, "Stone", lin(STONE))


def stoop(b, fr, u0, u1, top_y, out, st):
    """Stone steps up to a raised front door, with iron railings."""
    stone = lin(st.get("stoop_col", (0.5, 0.4, 0.34)))
    iron = lin((0.05, 0.05, 0.06))
    base = S.WALK_Y
    steps = max(3, int(round((top_y - base) / 0.18)))
    rise = (top_y - base) / steps
    run = (out - 1.0) / steps
    # Landing.
    fr.box(b, u0, u1, base, top_y, 0.0, 1.0, "Stone", stone, skip=("back", "bottom"))
    for i in range(steps):
        y1 = top_y - rise * i
        w0 = 1.0 + run * i
        fr.box(b, u0, u1, base, y1 - rise, w0, w0 + run, "Stone", stone, skip=("back", "bottom"))
        fr.box(b, u0 - 0.01, u1 + 0.01, y1 - rise, y1 - rise + 0.03, w0 - 0.02, w0 + run + 0.02, "Stone", stone,
               skip=("back", "bottom"))
    # Cheek walls and railings.
    for uu in (u0 - 0.12, u1 + 0.12):
        fr.box(b, uu - 0.12, uu + 0.12, base, base + 0.6, out - 0.3, out + 0.02, "Stone", stone, skip=("bottom",))
        pts = [(uu, top_y + 0.9, 0.05), (uu, top_y + 0.9, 1.0), (uu, base + 1.35, out - 0.15)]
        fr.tube(b, pts, 0.022, "Iron", iron, sides=5)
        fr.box(b, uu - 0.04, uu + 0.04, base + 0.6, base + 1.4, out - 0.19, out - 0.11, "Iron", iron)
        # Balusters: along the landing, then down the steps.
        railing(b, fr, [(uu, top_y, 0.05), (uu, top_y, 1.0), (uu, top_y + 0.9, 1.0), (uu, top_y + 0.9, 0.05)], iron)
        railing(b, fr, [(uu, top_y, 1.0), (uu, base + 0.6, out - 0.15), (uu, base + 1.35, out - 0.15),
                        (uu, top_y + 0.9, 1.0)], iron)


def areaway_fence(b, fr, u0, u1, out, st):
    """The low iron fence around a garden-level areaway."""
    iron = lin((0.05, 0.05, 0.06))
    y0 = S.WALK_Y
    fr.tube(b, [(u0, y0 + 0.95, 0.02), (u0, y0 + 0.95, out), (u1, y0 + 0.95, out), (u1, y0 + 0.95, 0.02)], 0.018,
            "Iron", iron, sides=4)
    fr.tube(b, [(u0, y0 + 0.12, out), (u1, y0 + 0.12, out)], 0.015, "Iron", iron, sides=4)
    railing(b, fr, [(u0, y0, out), (u1, y0, out), (u1, y0 + 0.95, out), (u0, y0 + 0.95, out)], iron)
    for uu in (u0, u1):
        railing(b, fr, [(uu, y0, 0.02), (uu, y0, out), (uu, y0 + 0.95, out), (uu, y0 + 0.95, 0.02)], iron)


def fire_escape(b, fr, u0, u1, floors, st):
    """Platforms with railings at each upper floor, linked by stair runs, and a
    drop ladder above the street."""
    iron = lin(st.get("escape_col", (0.1, 0.1, 0.11)))
    depth = 1.25
    for i, y in enumerate(floors):
        # The platform: a frame round a grating you can see through from below.
        fr.box(b, u0, u1, y - 0.1, y, depth - 0.05, depth, "Iron", iron, skip=("back",))
        for uu in (u0, u1 - 0.05):
            fr.box(b, uu, uu + 0.05, y - 0.1, y, 0.0, depth - 0.05, "Iron", iron, skip=("back",))
        grate = [(u0, y - 0.02, 0.0), (u0, y - 0.02, depth), (u1, y - 0.02, depth), (u1, y - 0.02, 0.0)]
        railing(b, fr, grate, iron)
        top = y + 0.95
        fr.tube(b, [(u0, top, 0.0), (u0, top, depth), (u1, top, depth), (u1, top, 0.0)], 0.02, "Iron", iron, sides=4)
        railing(b, fr, [(u0, y, depth), (u1, y, depth), (u1, top, depth), (u0, top, depth)], iron)
        for uu in (u0, u1):
            railing(b, fr, [(uu, y, 0.0), (uu, y, depth), (uu, top, depth), (uu, top, 0.0)], iron)
        # Brackets into the wall.
        for uu in (u0 + 0.2, u1 - 0.2):
            fr.tube(b, [(uu, y - 0.9, 0.0), (uu, y - 0.08, depth - 0.1)], 0.02, "Iron", iron, sides=4)
        if i + 1 < len(floors):
            # A stair run from this platform to the next, along the facade.
            ny = floors[i + 1]
            a, c = (u0 + 0.3, y, depth * 0.55), (u1 - 0.5, ny, depth * 0.55)
            for side in (-0.3, 0.3):
                fr.tube(b, [(a[0], a[1], a[2] + side), (c[0], c[1], c[2] + side)], 0.025, "Iron", iron, sides=4)
                fr.tube(b, [(a[0], a[1] + 0.9, a[2] + side), (c[0], c[1] + 0.9, c[2] + side)], 0.015, "Iron", iron, sides=4)
            steps = 12
            for k in range(1, steps):
                t = k / steps
                uu = a[0] + (c[0] - a[0]) * t
                yy = a[1] + (c[1] - a[1]) * t
                fr.box(b, uu - 0.1, uu + 0.1, yy - 0.02, yy, a[2] - 0.3, a[2] + 0.3, "Iron", iron,
                       skip=("left", "right", "bottom"))
    # Drop ladder under the lowest platform.
    y = floors[0]
    for side in (u1 - 0.7, u1 - 0.3):
        fr.box(b, side - 0.015, side + 0.015, y - 2.2, y, depth - 0.1, depth - 0.07, "Iron", iron)
    for k in range(9):
        fr.box(b, u1 - 0.7, u1 - 0.3, y - 2.1 + k * 0.25, y - 2.08 + k * 0.25, depth - 0.1, depth - 0.07, "Iron", iron,
               skip=("left", "right", "back"))


def awning(b, fr, u0, u1, y, st, rng, out=1.6, drop=0.7, valance=0.28):
    """A fabric awning: a sloped sheet, side cheeks and a valance. UV2.x runs
    across it in metres (for stripes), UV2.y = 1 on the fabric."""
    col = lin(st["awning"])
    stripes = 1.0 if st.get("stripes") else 0.0
    y_top, y_low = y, y - drop

    def cloth(pts):
        uv2 = [(p[0] - u0, stripes) for p in pts]
        fr.quad(b, pts, "Awning", col=col, uv2=uv2)
        fr.quad(b, list(reversed(pts)), "Awning", col=col, uv2=list(reversed(uv2)))

    cloth([(u0, y_low, out), (u1, y_low, out), (u1, y_top, 0.02), (u0, y_top, 0.02)])
    cloth([(u0, y_low - valance, out), (u1, y_low - valance, out), (u1, y_low, out), (u0, y_low, out)])
    for uu in (u0, u1):
        tri = [(uu, y_low, out), (uu, y_top, 0.02), (uu, y_low, 0.02)]
        b.face([fr.p(*q) for q in tri], "Awning", col=col, uv2=[(0.0, stripes)] * 3)
        b.face([fr.p(*q) for q in reversed(tri)], "Awning", col=col, uv2=[(0.0, stripes)] * 3)
    iron = lin((0.08, 0.08, 0.08))
    fr.tube(b, [(u0, y_low, out), (u1, y_low, out)], 0.015, "Iron", iron, sides=4)


# --- whole buildings -------------------------------------------------------------

def _bays(width, n):
    """Centres of n window bays across a facade `width` wide."""
    margin = width / n / 2
    return [margin + i * (width - 2 * margin) / max(1, n - 1) for i in range(n)] if n > 1 else [width / 2]


def building(b, fr, u0, u1, st, rng, lights, texts):
    """One building from style `st`. Returns its height above the sidewalk."""
    width = u1 - u0
    base = S.WALK_Y
    floors = st["floors"]
    ground = st.get("ground", "stoop")
    gh = S.GROUND_H if ground in ("shop", "laundromat") else S.FLOOR_H
    if ground == "stoop":
        gh = 1.3 + S.FLOOR_H          # garden level below, parlour floor up the stoop
    floor_y = [base + gh + i * S.FLOOR_H for i in range(floors - 1)]
    top = base + gh + (floors - 1) * S.FLOOR_H + 0.6
    wall_mat = st["wall_mat"]
    wall_col = st["wall_col"]
    deep = st.get("depth", 14.0)

    holes = []
    bays = _bays(width, st["bays"])
    ww, wh = st.get("win", (1.0, 1.75))
    # Upper floors.
    for fy in floor_y:
        for c in bays:
            holes.append((u0 + c - ww / 2, u0 + c + ww / 2, fy + 0.8, fy + 0.8 + wh))
    # Ground floor.
    ground_holes = []
    if ground == "stoop":
        door_bay = bays[0] if st.get("door_left", True) else bays[-1]
        # Parlour floor (up the stoop): tall windows and the door.
        py = base + 1.3
        for c in bays:
            if c == door_bay:
                ground_holes.append(("door", u0 + c - 0.55, u0 + c + 0.55, py, py + 2.75))
            else:
                ground_holes.append(("win", u0 + c - ww / 2, u0 + c + ww / 2, py + 0.55, py + 0.55 + wh + 0.3))
        # Garden level, half below the stoop.
        for c in bays:
            if c != door_bay:
                ground_holes.append(("win", u0 + c - ww / 2, u0 + c + ww / 2, base + 0.25, base + 1.1))
        ground_holes.append(("door", u0 + door_bay - 0.45, u0 + door_bay + 0.45, base, base + 1.05))
    elif ground == "house":
        door_bay = bays[0]
        for c in bays:
            if c == door_bay:
                ground_holes.append(("door", u0 + c - 0.5, u0 + c + 0.5, base + 0.3, base + 2.7))
            else:
                ground_holes.append(("win", u0 + c - ww / 2, u0 + c + ww / 2, base + 0.95, base + 0.95 + wh))
    elif ground in ("shop", "laundromat"):
        ground_holes.append(("shop", u0 + 0.35, u1 - 0.35, base + 0.45, base + 2.95))
    holes += [h[1:] for h in ground_holes]

    # The facade, with a band of stone at the ground floor for the shops.
    wall(b, fr, u0, u1, base, top, holes, wall_mat, wall_col)
    # Sides and roof (the sides show where neighbours are lower).
    fr.box(b, u0, u1, base, top, -deep, 0.0, wall_mat, wall_col, skip=("front", "bottom"))
    fr.box(b, u0, u1, top - 0.02, top, -deep, 0.0, "Roof", lin((0.2, 0.2, 0.21)), skip=("front", "bottom"))

    for (a, c_, y0, y1) in holes[:len(floor_y) * len(bays)]:
        window(b, fr, a, c_, y0, y1, st, rng, wall_mat=wall_mat, wall_col=wall_col)

    for kind, a, c_, y0, y1 in ground_holes:
        if kind == "win":
            window(b, fr, a, c_, y0, y1, st, rng, wall_mat=wall_mat, wall_col=wall_col)
        elif kind == "door":
            door(b, fr, a, c_, y0, y1, st, rng, wall_mat=wall_mat, wall_col=wall_col, transom=(y1 - y0) > 2.0)
            if y1 - y0 > 2.0:
                lamp = fr.p(c_ + 0.25, y0 + 2.1, 0.12)
                fr.box(b, c_ + 0.19, c_ + 0.31, y0 + 1.98, y0 + 2.24, 0.02, 0.16, "Lamp", lin((1.0, 0.85, 0.6)))
                lights["porch"].append([round(lamp.x, 3), round(lamp.y, 3), round(lamp.z, 3)])
        elif kind == "shop":
            shopfront(b, fr, a, c_, y0, y1, st, rng, lights, texts)

    if ground == "stoop":
        c = door_bay
        stoop(b, fr, u0 + c - 0.75, u0 + c + 0.75, base + 1.3, 3.2, st)
        fence_u = (u0 + 0.15, u0 + c - 1.0) if st.get("door_left", True) is False else (u0 + c + 1.0, u1 - 0.15)
        if fence_u[1] - fence_u[0] > 0.8:
            areaway_fence(b, fr, fence_u[0], fence_u[1], 1.3, st)
        # A stone band at the parlour floor line.
        fr.box(b, u0, u1, base + 1.2, base + 1.3, 0.0, 0.05, "Stone", lin(STONE), skip=("back",))
    if st.get("belt", True):
        for fy in floor_y:
            fr.box(b, u0, u1, fy - 0.08, fy + 0.04, 0.0, 0.04, "Stone", lin(st.get("stone", STONE)), skip=("back",))

    if st.get("fire_escape"):
        c = bays[len(bays) // 2]
        fire_escape(b, fr, u0 + c - 1.4, u0 + c + 1.4, floor_y, st)

    if st.get("top") == "cornice":
        cornice(b, fr, u0, u1, top, st, rng)
    else:
        parapet(b, fr, u0, u1, top, st)
    roof_things(b, fr, u0, u1, top, deep, st, rng)
    return top - base


def roof_things(b, fr, u0, u1, top, deep, st, rng):
    """Chimneys, vents, a bulkhead, a water tower: what sticks up above the roofline."""
    width = u1 - u0
    for _ in range(rng.randint(0, 2)):
        uu = rng.uniform(u0 + 0.5, u1 - 0.9)
        dd = -rng.uniform(1.5, deep - 2)
        h = rng.uniform(1.0, 2.2)
        col = st["wall_col"] if st["wall_mat"] == "Brick" else lin(BRICKS["red"])
        fr.box(b, uu, uu + 0.6, top, top + h, dd - 0.45, dd, "Brick", col, skip=("bottom",))
        fr.box(b, uu - 0.04, uu + 0.64, top + h, top + h + 0.08, dd - 0.49, dd + 0.04, "Stone", lin(STONE), skip=("bottom",))
    if rng.random() < 0.45:
        uu = rng.uniform(u0 + 0.5, u1 - 2.5)
        dd = -rng.uniform(3, deep - 4)
        grey = lin((0.55, 0.55, 0.55))
        fr.box(b, uu, uu + 2.0, top, top + 2.4, dd - 2.2, dd, "Stucco", grey, skip=("bottom",))
    if rng.random() < 0.5:
        uu = rng.uniform(u0 + 0.5, u1 - 1.5)
        dd = -rng.uniform(2, deep - 3)
        fr.box(b, uu, uu + 1.0, top, top + 0.8, dd - 0.8, dd, "Metal", lin((0.72, 0.72, 0.7)), skip=("bottom",))
    if st.get("water_tower"):
        water_tower(b, fr.p(u0 + width * 0.6, top, -deep * 0.45), rng)
    for _ in range(rng.randint(0, 3)):
        p = fr.p(rng.uniform(u0 + 0.3, u1 - 0.3), top, -rng.uniform(0.8, deep - 1))
        b.cylinder((p.x, p.y, p.z), rng.uniform(0.4, 1.0), 0.06, "Metal", col=lin((0.4, 0.4, 0.42)), sides=6)


def water_tower(b, p, rng):
    """The wooden water tank on steel legs that tops a taller building."""
    wood = lin((0.42, 0.31, 0.22))
    steel = lin((0.13, 0.13, 0.14))
    r = rng.uniform(1.8, 2.3)
    legs_h = 3.2
    for k in range(6):
        a = 2 * math.pi * k / 6
        x, z = p.x + math.cos(a) * r * 0.8, p.z + math.sin(a) * r * 0.8
        b.cylinder((x, p.y, z), legs_h, 0.1, "Iron", col=steel, sides=5)
    for yy in (1.2, 2.4):
        b.cylinder((p.x, p.y + yy, p.z), 0.08, r * 0.82, "Iron", col=steel, sides=12, top=False)
    b.cylinder((p.x, p.y + legs_h, p.z), 0.15, r + 0.2, "Iron", col=steel, sides=16)
    h = rng.uniform(3.8, 4.8)
    b.cylinder((p.x, p.y + legs_h + 0.15, p.z), h, r, "Wood", col=wood, sides=20, top=False)
    for k in range(4):
        b.cylinder((p.x, p.y + legs_h + 0.6 + k * h / 4, p.z), 0.06, r + 0.03, "Iron", col=steel, sides=20, top=False)
    b.cylinder((p.x, p.y + legs_h + 0.15 + h, p.z), 1.4, r + 0.12, "Roof", col=lin((0.18, 0.17, 0.17)), sides=20,
               radius_top=0.05)


def shopfront(b, fr, u0, u1, y0, y1, st, rng, lights, texts):
    """A shop window with a glass door, a bulkhead, a sign band and an awning."""
    base = S.WALK_Y
    trim = lin(st["shop_trim"])
    # Bulkhead under the window.
    fr.box(b, u0, u1, base, y0, -0.25, 0.0, "Wood", trim)
    reveal(b, fr, u0, u1, y0, y1, 0.25, "Wood", trim, sill=True)
    width = u1 - u0
    door_u = (u1 - 1.1, u1 - 0.1) if st.get("shop_door_right", True) else (u0 + 0.1, u0 + 1.1)
    # Glass: the shop behind (kind 0.5 = shop), split by mullions.
    mullions = [u0 + width * k / 3 for k in range(1, 3)]
    fr.box(b, u0, u1, y0, y0 + 0.08, -0.25, -0.12, "Wood", trim)
    fr.box(b, u0, u1, y1 - 0.08, y1, -0.25, -0.12, "Wood", trim)
    lit = 0.97 if st.get("shop_open", True) else 0.05
    pane(b, fr, u0 + 0.04, u1 - 0.04, y0 + 0.08, y1 - 0.08, -0.2, rng, kind=0.5 if st.get("ground") == "shop" else 0.75,
         lit=lit)
    for m in mullions:
        fr.box(b, m - 0.04, m + 0.04, y0, y1, -0.25, -0.12, "Wood", trim)
    # Sign band above, and lettering.
    sy0, sy1 = y1 + 0.08, y1 + 0.75
    sign_col = lin(st.get("sign_col", (0.1, 0.12, 0.1)))
    fr.box(b, u0 - 0.3, u1 + 0.3, sy0, sy1, 0.0, 0.12, "Wood", sign_col)
    fr.box(b, u0 - 0.35, u1 + 0.35, sy1, sy1 + 0.08, 0.0, 0.18, "Wood", trim)
    if st.get("sign"):
        texts.append({"text": st["sign"], "frame": fr, "u": (u0 + u1) / 2, "y": (sy0 + sy1) / 2 - 0.2,
                      "w": 0.12, "size": 0.42, "mat": "SignPaint", "col": lin(st.get("letter_col", (0.92, 0.82, 0.55)))})
    if st.get("awning"):
        awning(b, fr, u0 - 0.1, u1 + 0.1, sy0 - 0.02, st, rng)
    if st.get("neon"):
        # A neon sign hanging inside the shop window.
        text, colour = st["neon"]
        texts.append({"text": text, "frame": fr, "u": (u0 + u1) / 2 + width * 0.18, "y": y0 + 1.25, "w": -0.17,
                      "size": 0.32, "mat": "Neon", "col": (*colour, 1.0), "tube": True})
        p = fr.p((u0 + u1) / 2 + width * 0.18, y0 + 1.3, 0.3)
        lights["neon"].append({"pos": [round(p.x, 3), round(p.y, 3), round(p.z, 3)], "color": list(colour)})
    p = fr.p((u0 + u1) / 2, y0 + 1.4, 0.6)
    if st.get("shop_open", True):
        lights["shops"].append([round(p.x, 3), round(p.y, 3), round(p.z, 3)])


# --- the rows -------------------------------------------------------------------

def _style(rng, kind):
    brick = rng.choice(list(BRICKS))
    st = {
        "floors": rng.choice([3, 4, 4]), "bays": 3, "trim": TRIMS[rng.choice(["white", "cream", "black", "green", "oxblood"])],
        "wall_mat": "Brick", "wall_col": lin(BRICKS[brick]), "ground": "stoop", "top": "cornice",
        "lintel": rng.choice(["flat", "hood", "soldier"]), "muntins": rng.choice([1, 1, 2]), "ac": 0.14, "flowers": 0.1,
        "door": rng.choice([(0.2, 0.12, 0.08), (0.08, 0.1, 0.09), (0.3, 0.08, 0.07), (0.12, 0.2, 0.15), (0.12, 0.15, 0.25)]),
        "door_left": rng.random() < 0.5,
    }
    if brick == "brownstone":
        st["stone"] = (0.5, 0.36, 0.3)
        st["stoop_col"] = (0.45, 0.32, 0.26)
        st["lintel"] = "hood"
    if kind == "painted":
        paint_name = rng.choice(list(PAINTS))
        st.update(wall_mat="Stucco", wall_col=lin(PAINTS[paint_name]), ground="house", floors=rng.choice([2, 3]),
                  lintel="flat", top=rng.choice(["cornice", "parapet"]), trim=TRIMS[rng.choice(["white", "cream", "black"])])
    return st


# The far row, left to right: (width, overrides). Built from x = -72 up to the
# cross street at CROSS_X0, then from CROSS_X1 on.
FAR_LEFT = [
    (7.0, {"kind": "brick"}), (6.2, {"kind": "painted"}), (6.5, {"kind": "brick"}),
    (9.5, {"kind": "walkup"}), (6.0, {"kind": "brick"}), (6.3, {"kind": "painted"}),
    (6.8, {"kind": "brick"}), (7.5, {"kind": "shop", "sign": "LAUNDROMAT", "ground": "laundromat", "floors": 2,
                                      "awning": (0.2, 0.42, 0.62), "stripes": False, "neon": ("OPEN 24H", (0.3, 0.8, 1.0))}),
    (6.4, {"kind": "brick"}), (6.6, {"kind": "painted"}),
    (6.0, {"kind": "brick"}), (8.4, {"kind": "shop", "sign": "RAVIOLI DELI", "awning": (0.12, 0.38, 0.22), "stripes": True,
                                      "neon": ("OPEN", (1.0, 0.25, 0.3)), "floors": 4, "fire_escape": True}),
]
FAR_RIGHT = [
    (8.5, {"kind": "shop", "sign": "CAFE FARFALLE", "awning": (0.6, 0.16, 0.14), "stripes": True,
           "neon": ("ESPRESSO", (1.0, 0.55, 0.2)), "floors": 3}),
    (6.5, {"kind": "brick"}), (6.2, {"kind": "painted"}), (10.0, {"kind": "walkup", "water_tower": True}),
    (6.4, {"kind": "brick"}), (6.8, {"kind": "painted"}), (7.4, {"kind": "shop", "sign": "NOODLE BAR", "awning": (0.9, 0.62, 0.2),
                                                                  "stripes": False, "neon": ("NOODLES", (1.0, 0.3, 0.55)), "floors": 3}),
    (6.2, {"kind": "brick"}), (6.6, {"kind": "brick"}), (7.0, {"kind": "painted"}),
]


def _make_style(rng, spec):
    kind = spec.get("kind", "brick")
    st = _style(rng, "painted" if kind == "painted" else "brick")
    if kind == "walkup":
        st.update(floors=5, bays=4, ground="shop" if rng.random() < 0.3 else "house", fire_escape=True,
                  top="cornice", lintel="flat", win=(0.95, 1.7), ac=0.2)
        st["wall_col"] = lin(BRICKS[rng.choice(["red", "tan", "orange", "brown"])])
    if kind == "shop":
        st.update(ground="shop", bays=3, shop_trim=TRIMS[rng.choice(["black", "green", "oxblood", "navy"])],
                  sign_col=(0.08, 0.1, 0.09), awning=spec.get("awning"))
    for k, v in spec.items():
        if k not in ("kind",):
            st[k] = v
    if "awning" in st and st["awning"] is not None and "shop_trim" not in st:
        st["shop_trim"] = TRIMS["black"]
    if st.get("ground") in ("shop", "laundromat") and "shop_trim" not in st:
        st["shop_trim"] = TRIMS["black"]
    return st


def far_row(b, rng, lights, texts):
    fr = Frame((0, 0, S.FAR_FACADE_Z), (1, 0, 0), (0, 0, 1))
    heights = []
    x = S.CROSS_X0
    for width, spec in reversed(FAR_LEFT):
        x0 = x - width
        st = _make_style(rng, spec)
        h = building(b, fr, x0, x, st, rng, lights, texts)
        heights.append((x0, x, h))
        x = x0
    # Fill on out to the end of the street with simpler houses.
    while x > S.STREET_X[0]:
        width = rng.uniform(5.8, 7.5)
        st = _make_style(rng, {"kind": rng.choice(["brick", "brick", "painted"])})
        st["lod"] = 1 if x < -45.0 else 0
        building(b, fr, x - width, x, st, rng, lights, texts)
        x -= width
    x = S.CROSS_X1
    for width, spec in FAR_RIGHT:
        st = _make_style(rng, spec)
        h = building(b, fr, x, x + width, st, rng, lights, texts)
        heights.append((x, x + width, h))
        x += width
    while x < S.STREET_X[1]:
        width = rng.uniform(5.8, 7.5)
        st = _make_style(rng, {"kind": rng.choice(["brick", "brick", "painted"])})
        st["lod"] = 1 if x > 60.0 else 0
        building(b, fr, x, x + width, st, rng, lights, texts)
        x += width
    return heights


def cross_street(b, rng, lights, texts):
    """Both sides of the cross street, facing each other, running away from us."""
    left = Frame((S.CROSS_X0, 0, 0), (0, 0, -1), (1, 0, 0))     # u = -z, faces +x
    right = Frame((S.CROSS_X1, 0, 0), (0, 0, 1), (-1, 0, 0))    # u = z, faces -x
    # The corner buildings' side walls face the cross street: start behind them.
    u = -S.FAR_FACADE_Z + 14.0
    while u < -S.CROSS_END_Z:
        width = rng.uniform(5.8, 8.0)
        st = _make_style(rng, {"kind": rng.choice(["brick", "brick", "painted", "walkup"])})
        st["lod"] = 1 if u > 50.0 else 0
        building(b, left, u, u + width, st, rng, lights, texts)
        u += width
    u = S.CROSS_END_Z
    end = S.FAR_FACADE_Z - 14.0
    while u < end - 5.8:
        width = min(rng.uniform(5.8, 8.0), end - u)
        st = _make_style(rng, {"kind": rng.choice(["brick", "brick", "painted", "walkup"])})
        st["lod"] = 1 if u < -50.0 else 0
        building(b, right, u, u + width, st, rng, lights, texts)
        u += width
    # Closing the view down the street: a taller block across its far end.
    end_fr = Frame((0, 0, S.CROSS_END_Z - 2), (1, 0, 0), (0, 0, 1))
    st = _make_style(rng, {"kind": "walkup"})
    st.update(floors=7, bays=6, fire_escape=False, water_tower=True, lod=1)
    building(b, end_fr, S.CROSS_X0 - 6, S.CROSS_X1 + 6, st, rng, lights, texts)


def second_row(b, rng, lights, texts):
    """Taller, plainer blocks behind the far row, showing over its roofs."""
    fr = Frame((0, 0, S.FAR_FACADE_Z - 26.0), (1, 0, 0), (0, 0, 1))
    x = -80.0
    while x < 100.0:
        width = rng.uniform(12, 22)
        if S.CROSS_X0 - 4 < x + width / 2 < S.CROSS_X1 + 4:
            x += width
            continue
        st = _make_style(rng, {"kind": "walkup"})
        st.update(floors=rng.randint(6, 10), bays=int(width / 2.2), ground="house", fire_escape=rng.random() < 0.4,
                  top=rng.choice(["cornice", "parapet"]), water_tower=rng.random() < 0.5, ac=0.12, flowers=0.03,
                  depth=18.0, lod=1)
        set_back = rng.uniform(0, 12)
        f2 = Frame((0, 0, fr.o.z - set_back), (1, 0, 0), (0, 0, 1))
        building(b, f2, x, x + width, st, rng, lights, texts)
        x += width + rng.uniform(0, 3)
