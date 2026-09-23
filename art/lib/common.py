"""Shared helpers for Linguini's model scripts (run inside Blender by art/run.py).

Conventions
- Units are metres. Blender is Z-up; the glTF exporter converts to Godot's
  Y-up, and a model facing Blender +Y faces Godot -Z (Godot's "forward").
- Materials are named: Godot swaps some for its own shaders by name, and
  recolours decor by material name for colour variants.
- COLOR_0 (the active colour attribute "Col") carries painted colour; alpha
  is used for fin translucency.
- A second UV map ("Anim") carries per-vertex animation weights for vertex
  shaders (see each model's docstring for what u and v mean).
"""

import math
import random

import bmesh
import bpy
from mathutils import Vector

# The cosy palette. Linear-ish sRGB triples; materials convert as needed.
PALETTE = {
    "goldfish": (1.0, 0.42, 0.08),
    "goldfish_deep": (0.93, 0.25, 0.05),
    "goldfish_belly": (1.0, 0.78, 0.5),
    "fin_edge": (1.0, 0.95, 0.88),
    "eye_iris": (0.95, 0.72, 0.2),
    "black": (0.02, 0.02, 0.025),
    "white": (0.97, 0.96, 0.93),
    "stone": (0.52, 0.5, 0.48),
    "sandstone": (0.78, 0.64, 0.46),
    "slate": (0.34, 0.38, 0.42),
    "wood": (0.55, 0.36, 0.22),
    "wood_dark": (0.3, 0.2, 0.13),
    "leaf": (0.25, 0.62, 0.3),
    "leaf_light": (0.55, 0.8, 0.35),
    "moss": (0.22, 0.5, 0.22),
    "red": (0.85, 0.22, 0.18),
    "brass": (0.85, 0.65, 0.3),
    "plastic_black": (0.06, 0.065, 0.07),
    "gravel": (0.72, 0.62, 0.5),
}


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def linear_rgba(c):
    """sRGB colour (+ optional alpha, kept as is) to a linear RGBA tuple."""
    rgb = srgb_to_linear(c[:3])
    return (*rgb, c[3] if len(c) > 3 else 1.0)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(1)


def material(name, color=(0.8, 0.8, 0.8), roughness=0.5, metallic=0.0, alpha=1.0, vertex_color=False, image=None):
    """A Principled material. With vertex_color, the base colour comes from the
    "Col" attribute (multiplied by `color`); with `image`, from that texture."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    lin = srgb_to_linear(color)
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if alpha < 1.0 or vertex_color:
        bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        mat.surface_render_method = "BLENDED"
    links = mat.node_tree.links
    if vertex_color:
        attr = nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        links.new(attr.outputs["Alpha"], bsdf.inputs["Alpha"])
        mat.surface_render_method = "BLENDED"
    if image is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = image
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


def mesh_object(name, bm, materials=()):
    """Makes an object from a bmesh and links it into the scene."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for m in materials:
        obj.data.materials.append(m)
    return obj


def shade_smooth(obj, angle_deg=None):
    for p in obj.data.polygons:
        p.use_smooth = True
    if angle_deg is not None:
        # Auto-smooth by angle, via the modifier Blender 4.1+ uses.
        with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj]):
            bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg))


def add_modifier(obj, kind, **settings):
    mod = obj.modifiers.new(kind.lower(), kind)
    for k, v in settings.items():
        setattr(mod, k, v)
    return mod


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.modifier_apply(modifier=mod.name)


def bevelled_box(name, size, bevel=0.004, segments=2, mat=None, location=(0, 0, 0)):
    """A box with rounded edges: the cosy staple."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    obj = mesh_object(name, bm, [mat] if mat else [])
    obj.location = location
    if bevel > 0:
        add_modifier(obj, "BEVEL", width=bevel, segments=segments, limit_method="ANGLE")
        apply_modifiers(obj)
    shade_smooth(obj, 40)
    return obj


def paint(obj, fn, layer="Col"):
    """Paints the colour attribute per corner: fn(vertex_co, normal) -> RGBA,
    with RGB in sRGB like PALETTE. Stored linear, as glTF expects."""
    me = obj.data
    if layer not in me.color_attributes:
        me.color_attributes.new(layer, "FLOAT_COLOR", "CORNER")
    attr = me.color_attributes[layer]
    me.color_attributes.active_color = attr
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            attr.data[li].color = linear_rgba(fn(v.co, v.normal))


def anim_uv(obj, fn, name="Anim"):
    """Writes the animation-weight UV map: fn(vertex_co) -> (u, v).
    It's created as the second UV map so glTF exports it as TEXCOORD_1 (UV2)."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index]
            uv.data[li].uv = fn(v.co)
    me.uv_layers.active = me.uv_layers[0]


def box_uv(obj, scale=1.0):
    """Simple world-space box projection into the first UV map, for tiling textures."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers[0]
    for poly in me.polygons:
        n = poly.normal
        axis = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            a, b = [co[i] for i in range(3) if i != axis]
            uv.data[li].uv = (a * scale, b * scale)


def image(name, size, fn):
    """A small generated texture: fn(u, v) -> (r, g, b). Packed into the .glb."""
    w, h = size
    img = bpy.data.images.new(name, w, h, alpha=False)
    px = [0.0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            r, g, b = fn(x / w, y / h)
            i = (y * w + x) * 4
            px[i:i + 4] = (r, g, b, 1.0)
    img.pixels = px
    img.pack()
    return img


def join(objects, name):
    """Joins objects into one, with its origin at the world origin: models are
    authored in their final coordinates, and shaders measure from the origin."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return obj


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def mix_color(a, b, t, alpha=1.0):
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t), alpha)
