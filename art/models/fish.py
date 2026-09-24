"""Linguini, a fancy fantail goldfish.

Faces Blender +Y (Godot -Z), up +Z. Nose at y = NOSE, tail tip near y = -0.067.
Three materials, swapped for Godot shaders by name:
  FishBody  opaque, colour from "Col" x the scale texture
  FishFin   translucent, colour and alpha from "Col"
  FishEye   glossy, colour from "Col"
"Anim" UV (UV2 in Godot, where the glTF export has flipped v to 1 - v):
  u  bend: 0 at the nose, 1 at the tail tip. The swim wave bends by u.
  v  flutter: 0 where a fin meets the body (and on the body), 1 at its edge.
     Fins ripple by v. 2 marks the lower lip, which drops to open the mouth.
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

# The body proper runs from the peduncle to BODY_FRONT; a rounded snout caps
# it out to the nose, with the mouth on its front.
SNOUT = 0.0055
BODY_FRONT = NOSE - SNOUT


def _profile(x):
    """Radius factor along the body: x = 0 at the peduncle, 1 at the front of
    the body (the snout continues from there). A fantail's egg: full through
    the belly, pinching quickly (not a cone) into the peduncle, and blunt at
    the head."""
    front = 0.5
    if x >= front:
        k = (x - front) / (1.0 - front)
        return math.sqrt(max(0.0, 1.0 - (k * 0.9) ** 2))
    t = x / front
    return 0.28 + 0.72 * (1.0 - (1.0 - t) ** 2.2) ** 0.8


def _hump(x):
    # A fantail's hump: the back rises a little behind the head.
    return 1.0 + 0.12 * math.exp(-((x - 0.55) / 0.2) ** 2)


def _ring_radii(x):
    """(half width, half height up, half height down, centre height) at x."""
    f = _profile(x)
    return HALF_WIDTH * f, HALF_HEIGHT_UP * _hump(x) * f, HALF_HEIGHT_DOWN * f, -0.002 * f


def _snout_y(px, pz):
    """How far forward the snout's surface is at sideways px, height pz."""
    hw, hu, hd, c = _ring_radii(1.0)
    dz = pz - c
    e = (px / hw) ** 2 + (dz / (hu if dz > 0 else hd)) ** 2
    return BODY_FRONT + SNOUT * math.sqrt(max(0.0, 1.0 - e))


def _body():
    rings, sides = 44, 36
    bm = bmesh.new()
    grid = []

    def ring(y, hw, hu, hd, c):
        out = []
        for j in range(sides):
            a = 2 * math.pi * j / sides
            h = hu if math.sin(a) >= 0 else hd
            out.append(bm.verts.new((hw * math.cos(a), y, c + h * math.sin(a))))
        return out

    for i in range(rings):
        x = i / (rings - 1)
        y = PEDUNCLE + (BODY_FRONT - PEDUNCLE) * x
        grid.append(ring(y, *_ring_radii(x)))
    # The snout: an ellipsoidal cap, so the head is blunt and smooth.
    hw, hu, hd, c = _ring_radii(1.0)
    cap = 6
    for i in range(1, cap):
        a = math.pi / 2 * i / cap
        k = math.cos(a)
        grid.append(ring(BODY_FRONT + SNOUT * math.sin(a), hw * k, hu * k, hd * k, c))
    for i in range(len(grid) - 1):
        for j in range(sides):
            a, b = grid[i][j], grid[i][(j + 1) % sides]
            c_, d = grid[i + 1][(j + 1) % sides], grid[i + 1][j]
            bm.faces.new((a, b, c_, d))
    nose = bm.verts.new((0, NOSE, c))
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
        # Pale cheeks, a hint of a gill line, and a paler, rosy muzzle.
        x = (co.y - PEDUNCLE) / (NOSE - PEDUNCLE)
        cheek = smoothstep(0.7, 0.9, x) * (1.0 - t) * 0.5
        c = mix_color(c[:3], PALETTE["goldfish_belly"], cheek)
        gill = math.exp(-((x - 0.74) / 0.025) ** 2) * (1.0 - smoothstep(0.004, 0.014, co.z))
        c = mix_color(c[:3], PALETTE["goldfish_deep"], 0.3 * gill)
        muzzle = smoothstep(BODY_FRONT - 0.004, NOSE, co.y) * 0.35
        c = mix_color(c[:3], LIP, muzzle)
        return c

    paint(obj, colour)
    anim_uv(obj, lambda co: (bend(co.y), 0.0))
    return obj


LIP = (1.0, 0.62, 0.46)


def _mouth():
    """Lips on the front of the snout, closed over a dark mouth: the upper lip
    thinner, the lower one fuller, meeting at slightly raised corners. The
    lower lip (Anim v = 2) drops open now and then in the swim shader."""
    parts = []

    def lip(name, width, z_mid, z_corner_lift, radius, weight):
        bm = bmesh.new()
        n, sides = 10, 8
        rings = []
        for i in range(n + 1):
            t = -1 + 2 * i / n
            px = t * width
            pz = z_mid + z_corner_lift * t * t
            r = radius * (1.0 - 0.45 * t * t)
            py = _snout_y(px, pz) - r * 0.35
            centre = Vector((px, py, pz))
            # Around the lip's length (along x, bending back with the snout).
            ring = []
            for k in range(sides):
                a = 2 * math.pi * k / sides
                ring.append(bm.verts.new(centre + Vector((0.0, math.cos(a) * r, math.sin(a) * r))))
            rings.append(ring)
        for i in range(n):
            for k in range(sides):
                bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
        for end in (rings[0], rings[-1]):
            bm.faces.new(end)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.loops.layers.uv.new("UVMap")
        obj = mesh_object(name, bm, [bpy.data.materials["FishBody"]])
        shade_smooth(obj)
        paint(obj, lambda co, n_: (*LIP, 1.0))
        anim_uv(obj, lambda co, w=weight: (bend(co.y), w))
        return obj

    parts.append(lip("UpperLip", 0.0042, -0.0031, -0.0010, 0.0012, 0.0))
    parts.append(lip("LowerLip", 0.0040, -0.0060, 0.0012, 0.0015, 2.0))
    # The mouth behind them, dark, seen when the lower lip drops.
    bm = bmesh.new()
    cz = -0.0046
    pts = []
    for k in range(16):
        a = 2 * math.pi * k / 16
        px, pz = math.cos(a) * 0.0036, cz + math.sin(a) * 0.0017
        pts.append(bm.verts.new((px, _snout_y(px, pz) + 0.0002, pz)))
    bm.faces.new(pts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.y < 0:
            f.normal_flip()
    bm.loops.layers.uv.new("UVMap")
    inside = mesh_object("Mouth", bm, [bpy.data.materials["FishBody"]])
    paint(inside, lambda co, n_: (0.2, 0.05, 0.05, 1.0))
    anim_uv(inside, lambda co: (bend(co.y), 0.0))
    parts.append(inside)
    return parts


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
    x = max(0.0, min(1.0, (y - PEDUNCLE) / (BODY_FRONT - PEDUNCLE)))
    hw, hu, hd, c = _ring_radii(x)
    if side == "top":
        return Vector((0, y, c + hu))
    if side == "bottom":
        return Vector((0, y, c - hd))
    return Vector((hw * side, y, c))


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

def _cap(bm, centre, radius, look, angle, rings=6, segs=40):
    """A spherical cap round `look`, as its own little mesh in bm."""
    look = look.normalized()
    u = look.cross(Vector((0, 0, 1))).normalized()
    v = look.cross(u).normalized()
    loops = []
    for i in range(1, rings + 1):
        th = angle * i / rings
        loops.append([bm.verts.new(centre + (look * math.cos(th) + (u * math.cos(2 * math.pi * j / segs)
                                                                     + v * math.sin(2 * math.pi * j / segs)) * math.sin(th)) * radius)
                      for j in range(segs)])
    tip = bm.verts.new(centre + look * radius)
    for j in range(segs):
        bm.faces.new((tip, loops[0][j], loops[0][(j + 1) % segs]))
    for i in range(rings - 1):
        for j in range(segs):
            j2 = (j + 1) % segs
            bm.faces.new((loops[i][j], loops[i + 1][j], loops[i + 1][j2], loops[i][j2]))


def _eyes():
    """Glossy eyes: a white ball with a gold iris, a darker rim to it and a
    round pupil, each its own crisp cap (painting them on the ball's vertices
    left them jagged)."""
    eyes = []
    for sign in (-1, 1):
        centre = Vector((0.0112 * sign, 0.0165, 0.0055))
        look = Vector((0.85 * sign, 0.45, 0.2)).normalized()
        r = 0.0068
        parts = []
        eye_mat = bpy.data.materials.get("FishEye") or material("FishEye", roughness=0.08, vertex_color=True)
        for name, radius, angle, colour in (("EyeWhite", r, None, (0.93, 0.92, 0.88)),
                                            ("IrisRim", r * 1.02, math.radians(74), (0.5, 0.28, 0.08)),
                                            ("Iris", r * 1.03, math.radians(68), PALETTE["eye_iris"]),
                                            ("Pupil", r * 1.04, math.radians(40), PALETTE["black"])):
            bm = bmesh.new()
            if angle is None:
                bmesh.ops.create_uvsphere(bm, u_segments=36, v_segments=24, radius=radius)
                bmesh.ops.translate(bm, verts=bm.verts, vec=centre)
            else:
                _cap(bm, centre, radius, look, angle)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.loops.layers.uv.new("UVMap")
            obj = mesh_object(name, bm, [eye_mat])
            shade_smooth(obj)
            if name == "Iris":
                # Lighter toward the pupil.
                paint(obj, lambda co, n_, c=centre, lk=look: mix_color(PALETTE["eye_iris"], (1.0, 0.86, 0.45),
                                                                    smoothstep(0.5, 0.9, (co - c).normalized().dot(lk))))
            else:
                paint(obj, lambda co, n_, col=colour: (*col, 1.0))
            anim_uv(obj, lambda co: (bend(co.y), 0.0))
            parts.append(obj)
        eyes.append(join(parts, "Eye"))
    return eyes


def build():
    parts = [_body()] + _mouth() + _fins() + _eyes()
    fish = join(parts, "Fish")
    return [fish]
