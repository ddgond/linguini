"""Linguini, a fancy fantail goldfish.

Faces Blender +Y (Godot -Z), up +Z. Nose at y = NOSE, tail tip near y = -0.067.
Three materials, swapped for Godot shaders by name:
  FishBody  opaque, colour from "Col" x the scale texture
  FishFin   translucent, colour and alpha from "Col"
  FishEye   glossy, colour from "Col"
"Anim" UV (UV2 in Godot):
  u  bend: 0 at the nose, 1 at the tail tip. The swim wave bends by u.
  v  flutter: 0 where a fin meets the body, 1 at its edge. Fins ripple by v.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

from lib.common import PALETTE, anim_uv, image, join, linear_rgba, material, mesh_object, mix_color, paint, shade_smooth, smoothstep

NOSE = 0.028
PEDUNCLE = -0.022
TAIL_LENGTH = 0.046
TAIL_TIP = PEDUNCLE - TAIL_LENGTH
HALF_WIDTH = 0.0165
HALF_HEIGHT_UP = 0.0205
HALF_HEIGHT_DOWN = 0.0235

RENDER_VIEWS = [(35, 14), (90, 4), (155, 28)]


def bend(y):
    return max(0.0, min(1.0, (NOSE - y) / (NOSE - TAIL_TIP)))


# --- body -------------------------------------------------------------------

def _profile(x):
    """Radius factor along the body: x = 0 at the peduncle, 1 at the nose."""
    front = 0.52
    if x >= front:
        k = (x - front) / (1.0 - front)
        return math.sqrt(max(0.0, 1.0 - k * k)) ** 0.9
    return 0.3 + 0.7 * smoothstep(0.0, front, x) ** 0.75


def _body():
    rings, sides = 44, 36
    bm = bmesh.new()
    grid = []
    for i in range(rings):
        x = i / (rings - 1)
        y = PEDUNCLE + (NOSE - PEDUNCLE) * x
        f = _profile(x)
        # A fantail's hump: the back rises a little behind the head.
        hump = 1.0 + 0.12 * math.exp(-((x - 0.55) / 0.2) ** 2)
        ring = []
        for j in range(sides):
            a = 2 * math.pi * j / sides
            up = math.sin(a) >= 0
            h = (HALF_HEIGHT_UP * hump if up else HALF_HEIGHT_DOWN) * f
            ring.append(bm.verts.new((HALF_WIDTH * f * math.cos(a), y, -0.002 * f + h * math.sin(a))))
        grid.append(ring)
    for i in range(rings - 1):
        for j in range(sides):
            a, b = grid[i][j], grid[i][(j + 1) % sides]
            c, d = grid[i + 1][(j + 1) % sides], grid[i + 1][j]
            bm.faces.new((a, b, c, d))
    nose = bm.verts.new((0, NOSE + 0.0005, -0.001))
    for j in range(sides):
        bm.faces.new((grid[-1][j], grid[-1][(j + 1) % sides], nose))
    tail_center = bm.verts.new((0, PEDUNCLE - 0.001, 0))
    for j in range(sides):
        bm.faces.new((grid[0][(j + 1) % sides], grid[0][j], tail_center))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Tube UVs (u around, v along) for the scale texture.
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop in face.loops:
            co = loop.vert.co
            loop[uv].uv = ((math.atan2(co.z, co.x) / (2 * math.pi)) % 1.0 * 9.0, (co.y - PEDUNCLE) / (NOSE - PEDUNCLE) * 6.0)

    scales = image("FishScales", (64, 64), _scale_pixel)
    body_mat = _body_material(scales)
    obj = mesh_object("Body", bm, [body_mat])
    shade_smooth(obj)

    def colour(co, n):
        back = PALETTE["goldfish_deep"]
        belly = PALETTE["goldfish_belly"]
        t = smoothstep(-0.016, 0.014, co.z)
        c = mix_color(belly, PALETTE["goldfish"], smoothstep(-0.016, 0.0, co.z))
        c = mix_color(c[:3], back, smoothstep(0.004, 0.02, co.z) * 0.8)
        # Pale cheeks and a hint of a gill line.
        x = (co.y - PEDUNCLE) / (NOSE - PEDUNCLE)
        cheek = smoothstep(0.7, 0.9, x) * (1.0 - t) * 0.5
        c = mix_color(c[:3], PALETTE["goldfish_belly"], cheek)
        gill = math.exp(-((x - 0.74) / 0.025) ** 2) * (1.0 - smoothstep(0.004, 0.014, co.z))
        c = mix_color(c[:3], PALETTE["goldfish_deep"], 0.3 * gill)
        # Mouth: a small darker pout at the tip of the nose.
        if x > 0.975 and abs(co.z + 0.002) < 0.005:
            c = (0.75, 0.3, 0.25, 1.0)
        return c

    paint(obj, colour)
    anim_uv(obj, lambda co: (bend(co.y), 0.0))
    return obj


def _scale_pixel(u, v):
    # Overlapping scallops, one row offset by half a scale.
    rows = 4
    su = u * rows
    sv = v * rows
    row = math.floor(sv)
    su += 0.5 * (row % 2)
    fu = su - math.floor(su) - 0.5
    fv = sv - row
    d = math.sqrt(fu * fu + (fv * 1.1) ** 2)
    edge = smoothstep(0.42, 0.5, d)
    shade = 0.96 + 0.04 * (1.0 - fv) - 0.06 * edge
    return (shade, shade, shade)


def _body_material(scales):
    mat = material("FishBody", roughness=0.35, vertex_color=True)
    mat.surface_render_method = "DITHERED"
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    col = nodes["Color Attribute"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = scales
    mul = nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    links.new(col.outputs["Color"], mul.inputs["A"])
    links.new(tex.outputs["Color"], mul.inputs["B"])
    links.new(mul.outputs["Result"], bsdf.inputs["Base Color"])
    # The body is opaque: don't take alpha from the colour attribute.
    for link in list(links):
        if link.to_socket == bsdf.inputs["Alpha"]:
            links.remove(link)
    bsdf.inputs["Alpha"].default_value = 1.0
    bsdf.inputs["Coat Weight"].default_value = 0.35
    return mat


# --- fins -------------------------------------------------------------------

def surface(y, side):
    """A point on the body surface at `y`: side "top", "bottom", or +-1 for left/right."""
    x = max(0.0, min(1.0, (y - PEDUNCLE) / (NOSE - PEDUNCLE)))
    f = _profile(x)
    hump = 1.0 + 0.12 * math.exp(-((x - 0.55) / 0.2) ** 2)
    if side == "top":
        return Vector((0, y, -0.002 * f + HALF_HEIGHT_UP * hump * f))
    if side == "bottom":
        return Vector((0, y, -0.002 * f - HALF_HEIGHT_DOWN * f))
    return Vector((HALF_WIDTH * f * side, y, -0.002 * f))


def _fin(name, base_a, base_b, direction, outline, spread=0.0, cup=0.0, ruffle=0.0006,
         rays=9, droop=0.0, root=0.002, res=(14, 10)):
    """A membrane growing from the base edge a-b along `direction`.

    outline(s) is the fin's length at s (0..1 along the base), so it sets the
    silhouette: sin-shaped for a rounded paddle, notched for a forked tail.
    The tips fan apart by `spread`, the membrane cups by `cup` (along its
    normal, growing with r^2) and ruffles by `ruffle` between its rays. The
    base is sunk `root` metres into the body so there's no gap.
    """
    a, b = Vector(base_a), Vector(base_b)
    d = Vector(direction).normalized()
    side = (b - a).normalized()
    normal = side.cross(d).normalized()
    bm = bmesh.new()
    cols, rows = res
    verts = []
    for i in range(cols + 1):
        s = i / cols
        base = a.lerp(b, s) - d * root
        length = outline(s) + root
        row = []
        for j in range(rows + 1):
            r = j / rows
            p = base + d * length * r + side * (s - 0.5) * spread * r
            p.z -= droop * r * r
            p += normal * (cup * r * r * math.sin(math.pi * s) + ruffle * math.sin(s * rays * math.pi) * r)
            row.append(bm.verts.new(p))
        verts.append(row)
    for i in range(cols):
        for j in range(rows):
            bm.faces.new((verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]))
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop in face.loops:
            loop[uv].uv = (0.0, 0.0)
    # Each vertex's place in the fin's own (s, r) grid, before the bmesh is freed.
    bm.verts.index_update()
    grid = {}
    for i, row in enumerate(verts):
        for j, v in enumerate(row):
            grid[v.index] = (i / cols, j / rows)
    obj = mesh_object(name, bm, [material("FishFin", roughness=0.4, alpha=0.8, vertex_color=True)])
    shade_smooth(obj)

    me = obj.data
    me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    colour = me.color_attributes["Col"]
    me.color_attributes.active_color = colour
    anim = me.uv_layers.new(name="Anim")
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            s, r = grid[vi]
            stripe = 0.9 + 0.1 * math.cos(s * rays * 2 * math.pi)
            c = mix_color(PALETTE["goldfish"], PALETTE["fin_edge"], smoothstep(0.1, 0.9, r), alpha=0.95 - 0.5 * r)
            colour.data[li].color = linear_rgba((c[0] * stripe, c[1] * stripe, c[2] * stripe, c[3]))
            anim.data[li].uv = (bend(me.vertices[vi].co.y), r)
    me.uv_layers.active = me.uv_layers[0]
    return obj


def _rounded(peak, lo=0.0, power=0.6):
    """Outline for a rounded fin: `lo` at the ends of the base, `peak` in the middle."""
    return lambda s: peak * (lo + (1 - lo) * math.sin(math.pi * s) ** power)


def _tail():
    lobes = []
    for sign in (-1, 1):
        # Each lobe is a broad fan with a notch in the middle of its trailing
        # edge, so the pair reads as the fantail's four-pointed double tail.
        outline = lambda s: TAIL_LENGTH * (0.55 + 0.45 * math.sin(math.pi * s) ** 0.5) * (
            1.0 - 0.3 * math.exp(-((s - 0.5) / 0.14) ** 2))
        lobe = _fin(
            "Tail", (0, PEDUNCLE + 0.004, 0.0105), (0, PEDUNCLE + 0.004, -0.0105), (0, -1, 0),
            outline, spread=0.05, cup=0.004 * sign, ruffle=0.0009, rays=12, droop=0.007,
            root=0.004, res=(22, 14))
        # Splay the lobes into a V seen from above, hanging slightly.
        pivot = Vector((0, PEDUNCLE + 0.004, 0))
        rot = Matrix.Rotation(math.radians(26 * sign), 4, "Z") @ Matrix.Rotation(math.radians(-7), 4, "X")
        lobe.data.transform(Matrix.Translation(-pivot))
        lobe.data.transform(rot)
        lobe.data.transform(Matrix.Translation(pivot))
        _reweight(lobe)
        lobes.append(lobe)
    return lobes


def _reweight(obj):
    me = obj.data
    anim = me.uv_layers["Anim"]
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            anim.data[li].uv = (bend(co.y), anim.data[li].uv[1])


def _fins():
    fins = _tail()
    # Dorsal: a tall rounded sail along the back, highest at the front.
    fins.append(_fin(
        "Dorsal", surface(0.011, "top"), surface(-0.017, "top"), (0, -0.5, 1),
        lambda s: 0.022 * math.sin(math.pi * s) ** 0.55 * (1.1 - 0.5 * s),
        spread=0.004, cup=0.0, ruffle=0.0005, rays=8, res=(14, 8)))
    for sign in (-1, 1):
        # Pectorals: rounded paddles behind the gills, out, back and down.
        pa = surface(0.009, sign) + Vector((0, 0, -0.006))
        pb = surface(0.002, sign) + Vector((0, 0, -0.009))
        fins.append(_fin("Pectoral", pa, pb, (0.55 * sign, -0.8, -0.55), _rounded(0.016, 0.35),
                         spread=0.006, cup=0.002 * sign, rays=6, res=(8, 6)))
        # Pelvics: a pair under the belly, trailing back.
        fins.append(_fin("Pelvic", surface(0.003, "bottom") + Vector((0.004 * sign, 0, 0.001)),
                         surface(-0.006, "bottom") + Vector((0.004 * sign, 0, 0.001)),
                         (0.35 * sign, -0.7, -1), _rounded(0.015, 0.3), spread=0.004, rays=5, res=(8, 6)))
        # Twin anal fins near the tail.
        fins.append(_fin("Anal", surface(-0.011, "bottom") + Vector((0.003 * sign, 0, 0.001)),
                         surface(-0.019, "bottom") + Vector((0.003 * sign, 0, 0.001)),
                         (0.3 * sign, -0.8, -1), _rounded(0.013, 0.3), spread=0.004, rays=5, res=(8, 6)))
    return fins


# --- eyes -------------------------------------------------------------------

def _eyes():
    eyes = []
    for sign in (-1, 1):
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.0068)
        uv = bm.loops.layers.uv.new("UVMap")
        obj = mesh_object("Eye", bm, [material("FishEye", roughness=0.08, vertex_color=True)])
        center = Vector((0.0112 * sign, 0.0165, 0.0055))
        obj.data.transform(Matrix.Translation(center))
        shade_smooth(obj)
        look = Vector((0.85 * sign, 0.45, 0.2)).normalized()

        def colour(co, n, look=look, center=center):
            d = (co - center).normalized().dot(look)
            if d > 0.8:
                return (*PALETTE["black"], 1.0)
            if d > 0.62:
                return (*PALETTE["eye_iris"], 1.0)
            return (*PALETTE["white"], 1.0)

        paint(obj, colour)
        anim_uv(obj, lambda co: (bend(co.y), 0.0))
        eyes.append(obj)
    return eyes


def build():
    parts = [_body()] + _fins() + _eyes()
    fish = join(parts, "Fish")
    return [fish]
