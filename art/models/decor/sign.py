"""A wooden "NO FISHING" sign on a post. Materials "Primary" (wood) and
"Accent" (the lettering, raised from the board)."""

import math

import bpy
from mathutils import Matrix, noise

from lib.common import bevelled_box, join, paint
from lib.decor import mats, still

RENDER_VIEWS = [(20, 8)]


def _text(body, size, mat, location):
    curve = bpy.data.curves.new("SignText", "FONT")
    curve.body = body
    curve.size = size
    curve.extrude = 0.0008
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.space_line = 0.9
    obj = bpy.data.objects.new("SignText", curve)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    mesh_obj = bpy.context.view_layer.objects.active
    # Stand the text up on the board's front face.
    mesh_obj.data.transform(Matrix.Rotation(math.radians(90), 4, "X"))
    mesh_obj.data.transform(Matrix.Translation(location))
    mesh_obj.data.materials.clear()
    mesh_obj.data.materials.append(mat)
    return mesh_obj


def build():
    m = mats(Primary=((0.8, 0.8, 0.8), 0.8), Accent=((0.8, 0.8, 0.8), 0.6))
    post = bevelled_box("Post", (0.012, 0.012, 0.13), 0.002, 1, m["Primary"], (0, 0.004, 0.065))
    board = bevelled_box("Board", (0.1, 0.008, 0.05), 0.003, 2, m["Primary"], (0, 0, 0.1))
    board.rotation_euler = (0, math.radians(-4), 0)
    text = _text("NO\nFISHING", 0.018, m["Accent"], (0, -0.0045, 0.1))
    obj = join([post, board, text], "Sign")

    def colour(co, n):
        k = 0.8 + 0.12 * math.sin(co.x * 300 + noise.noise(co * 80) * 3)
        return (k, k, k, 1.0)

    paint(obj, colour)
    still(obj)
    return [obj]
