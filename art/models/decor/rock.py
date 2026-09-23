"""Rocks in three shapes: a round boulder, a flat slab and a tall spire.
Material "Primary" (stone colour variants), painted crevices and a little moss."""

from lib.decor import mats, paint_stone, rock, still

RENDER_VIEWS = [(30, 20)]

SHAPES = {
    "round": ((0.085, 0.075, 0.065), 11, 0.55),
    "flat": ((0.14, 0.1, 0.035), 23, 0.35),
    "tall": ((0.055, 0.05, 0.14), 37, 0.45),
}


def build(shape="round"):
    size, seed, roughness = SHAPES[shape]
    m = mats(Primary=((0.8, 0.8, 0.8), 0.8))
    obj = rock("Rock", size, seed, m["Primary"], roughness=roughness, subdivisions=4)
    paint_stone(obj, seed, moss=0.5 if shape != "tall" else 0.3)
    still(obj)
    return [obj]
