"""A hang-on-back filter. It hooks over a rim: origin is the inside top edge of
the glass, the box hangs outside (Blender +Y), the intake tube reaches down
into the tank and the spillway pours toward -Y. Materials "Primary" (the
plastic), "Spill" (the falling sheet of water, animated in Godot).
Godot places it along the back or side rims only."""

import math

import bmesh
from mathutils import Vector

from lib.common import bevelled_box, join, mesh_object, paint
from lib.decor import box_points, collider, mats, still, tube

RENDER_VIEWS = [(35, 15)]


def build():
    m = mats(Primary=((0.8, 0.8, 0.8), 0.5), Spill=((0.8, 0.8, 0.8), 0.1))
    parts = [
        bevelled_box("Body", (0.13, 0.07, 0.13), 0.008, 3, m["Primary"], (0, 0.05, -0.035)),
        bevelled_box("LidTop", (0.135, 0.075, 0.012), 0.005, 2, m["Primary"], (0, 0.05, 0.034)),
        # The spillway lip reaching over the glass into the tank.
        bevelled_box("Lip", (0.09, 0.05, 0.008), 0.003, 2, m["Primary"], (0, -0.012, 0.012)),
    ]
    intake = tube("Intake", [Vector((0.045, 0.03, 0.0)), Vector((0.045, -0.012, 0.0)), Vector((0.045, -0.02, -0.02)),
                             Vector((0.045, -0.02, -0.35))], 0.007, m["Primary"], sides=12)
    parts.append(intake)
    strainer = tube("Strainer", [Vector((0.045, -0.02, -0.35)), Vector((0.045, -0.02, -0.41))], 0.011, m["Primary"], sides=14)
    parts.append(strainer)
    # The falling sheet of water, from the lip down to the water line (4 cm below the rim).
    bm = bmesh.new()
    rows = []
    for i in range(9):
        t = i / 8
        y = -0.037 - 0.012 * t * t
        z = 0.009 - 0.045 * t
        rows.append((bm.verts.new((-0.04, y, z)), bm.verts.new((0.04, y, z))))
    for i in range(8):
        bm.faces.new((rows[i][0], rows[i][1], rows[i + 1][1], rows[i + 1][0]))
    spill = mesh_object("Spill", bm, [m["Spill"]])
    paint(spill, lambda co, n: (1.0, 1.0, 1.0, 1.0))
    parts.append(spill)
    obj = join(parts, "Filter")

    def colour(co, n):
        if co.z < -0.34 and abs(co.y + 0.02) < 0.012:
            # Strainer slots.
            return (0.4, 0.4, 0.4, 1.0) if math.sin(co.z * 900) > 0.3 else (0.9, 0.9, 0.9, 1.0)
        return (0.92, 0.92, 0.92, 1.0)

    paint(obj, colour)
    still(obj)
    # The body and lip above the water, and the intake and strainer below.
    cols = [
        collider("Body", box_points((0, 0.05, -0.03), (0.135, 0.075, 0.14))),
        collider("Lip", box_points((0, -0.012, 0.012), (0.09, 0.05, 0.01))),
        collider("Intake", box_points((0.045, -0.02, -0.19), (0.016, 0.016, 0.34))),
        collider("Strainer", box_points((0.045, -0.02, -0.38), (0.024, 0.024, 0.07))),
    ]
    return [obj] + cols
