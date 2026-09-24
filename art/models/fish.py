"""Linguini, a fancy fantail goldfish, modelled on the real Tortellini
(art/reference/tortellini.jpg): a longish body with a humped back, a red
cap, silvery cheeks and belly, small gold eyes, a tall sail of a dorsal and
long, flowing, translucent fins.

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

NOSE = 0.03
PEDUNCLE = -0.024
TAIL_LENGTH = 0.06
TAIL_TIP = PEDUNCLE - TAIL_LENGTH
HALF_WIDTH = 0.0112
HALF_HEIGHT_UP = 0.0165
HALF_HEIGHT_DOWN = 0.0168

RENDER_VIEWS = [(35, 14), (90, 4), (155, 28)]


def bend(y):
    return max(0.0, min(1.0, (NOSE - y) / (NOSE - TAIL_TIP)))


# --- body -------------------------------------------------------------------

# The body proper runs from the peduncle to BODY_FRONT; a rounded snout caps
# it out to the nose, with the mouth on its front.
SNOUT = 0.007
BODY_FRONT = NOSE - SNOUT


def _profile(x):
    """Radius factor along the body: x = 0 at the peduncle, 1 at the front of
    the body (the snout continues from there). Full through the middle, easing
    into a slim peduncle, and tapering to a snout at the head."""
    front = 0.5
    if x >= front:
        k = (x - front) / (1.0 - front)
        return math.sqrt(max(0.0, 1.0 - (k * 0.95) ** 2))
    t = x / front
    return 0.3 + 0.7 * (1.0 - (1.0 - t) ** 2.0) ** 0.85


def _hump(x):
    # The back rises steeply behind the head, to the front of the dorsal.
    return 1.0 + 0.34 * math.exp(-((x - 0.58) / 0.24) ** 2)


def _ring_radii(x):
    """(half width, half height up, half height down, centre height) at x.
    The head dips a little toward the snout."""
    f = _profile(x)
    centre = -0.002 * f - 0.003 * smoothstep(0.7, 1.0, x)
    return HALF_WIDTH * f, HALF_HEIGHT_UP * _hump(x) * f, HALF_HEIGHT_DOWN * f, centre


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
        # Tortellini: deep orange, darker along the back, a red cap over the
        # head, silvery-white cheeks, gill cover and belly.
        x = max(0.0, min(1.0, (co.y - PEDUNCLE) / (BODY_FRONT - PEDUNCLE)))
        hw, hu, hd, c0 = _ring_radii(x)
        up = (co.z - c0) / max(hu, 1e-4)
        c = ORANGE
        c = mix_color(c, ORANGE_DEEP, smoothstep(0.2, 0.9, up) * 0.7)[:3]
        c = mix_color(c, RED_CAP, smoothstep(0.66, 0.8, x) * smoothstep(-0.45, 0.05, up))[:3]
        cheek = smoothstep(0.6, 0.72, x) * (1.0 - smoothstep(0.92, 1.0, x)) * (1.0 - smoothstep(-0.45, 0.0, up))
        belly = smoothstep(0.25, 0.4, x) * (1.0 - smoothstep(0.64, 0.78, x)) * (1.0 - smoothstep(-0.35, 0.15, up))
        c = mix_color(c, SILVER, max(cheek, belly) * 0.9)[:3]
        # The gill cover's edge, and here and there a pale scale.
        gill = math.exp(-((x - 0.68) / 0.018) ** 2) * (1.0 - smoothstep(-0.2, 0.4, up))
        c = mix_color(c, ORANGE_DEEP, 0.35 * gill)[:3]
        speck = math.sin(co.x * 3100.0) * math.sin(co.y * 2700.0 + co.z * 1900.0)
        if speck > 0.93 and 0.2 < x < 0.7:
            c = mix_color(c, (1.0, 0.82, 0.55), 0.5)[:3]
        muzzle = smoothstep(BODY_FRONT - 0.003, NOSE, co.y) * 0.3
        return mix_color(c, LIP, muzzle)

    paint(obj, colour)
    anim_uv(obj, lambda co: (bend(co.y), 0.0))
    return obj


ORANGE = (1.0, 0.54, 0.12)
ORANGE_DEEP = (0.98, 0.42, 0.06)
RED_CAP = (0.96, 0.2, 0.07)
SILVER = (0.94, 0.9, 0.84)
LIP = (1.0, 0.56, 0.42)
FIN_ROOT = (1.0, 0.5, 0.12)
FIN_EDGE = (1.0, 0.74, 0.48)


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

    c = _ring_radii(1.0)[3]
    parts.append(lip("UpperLip", 0.0026, c + 0.0006, -0.0006, 0.0008, 0.0))
    parts.append(lip("LowerLip", 0.0025, c - 0.0014, 0.0008, 0.001, 2.0))
    # The mouth behind them, dark, seen when the lower lip drops.
    bm = bmesh.new()
    cz = c - 0.0004
    pts = []
    for k in range(16):
        a = 2 * math.pi * k / 16
        px, pz = math.cos(a) * 0.0017, cz + math.sin(a) * 0.0007
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
            # Orange at the root fading paler and clearer toward the edge,
            # with darker rays.
            stripe = 0.84 + 0.16 * math.cos(s * rays * 2 * math.pi)
            c = mix_color(FIN_ROOT, FIN_EDGE, smoothstep(0.2, 1.0, r), alpha=0.9 - 0.55 * r)
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
        # Each lobe is a long fan with a deep notch in its trailing edge, so
        # the pair reads as a double tail with pointed tips that droop.
        outline = lambda s: TAIL_LENGTH * (0.45 + 0.55 * math.sin(math.pi * s) ** 0.6) * (
            1.0 - 0.42 * math.exp(-((s - 0.5) / 0.12) ** 2))
        lobe = _fin(
            "Tail", (0, PEDUNCLE + 0.004, 0.0075), (0, PEDUNCLE + 0.004, -0.0085), (0, -1, 0),
            outline, spread=0.055, cup=0.005 * sign, ruffle=0.0014, rays=14, droop=0.026,
            root=0.004, res=(26, 18))
        # Splay the lobes into a V seen from above, hanging down a little.
        pivot = Vector((0, PEDUNCLE + 0.004, 0))
        rot = Matrix.Rotation(math.radians(24 * sign), 4, "Z") @ Matrix.Rotation(math.radians(-18), 4, "X")
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
    # Dorsal: a tall sail from the top of the hump, highest at the front,
    # leaning back.
    fins.append(_fin(
        "Dorsal", surface(0.006, "top"), surface(-0.02, "top"), (0, -0.45, 1),
        lambda s: 0.033 * math.sin(math.pi * min(1.0, s * 1.5 + 0.1)) ** 0.4 * (1.0 - 0.5 * s),
        spread=0.012, cup=0.0, ruffle=0.001, rays=11, droop=0.004, res=(16, 12)))
    for sign in (-1, 1):
        # Pectorals: small paddles behind the gill covers.
        pa = surface(0.012, sign) + Vector((0, 0, -0.005))
        pb = surface(0.006, sign) + Vector((0, 0, -0.007))
        fins.append(_fin("Pectoral", pa, pb, (0.55 * sign, -0.8, -0.55), _rounded(0.012, 0.35),
                         spread=0.005, cup=0.0015 * sign, rays=6, res=(8, 6)))
        # Pelvics: long, trailing back under the belly.
        fins.append(_fin("Pelvic", surface(0.004, "bottom") + Vector((0.003 * sign, 0, 0.001)),
                         surface(-0.004, "bottom") + Vector((0.003 * sign, 0, 0.001)),
                         (0.28 * sign, -0.9, -0.75), lambda s: 0.03 * math.sin(math.pi * s) ** 0.7 * (0.55 + 0.45 * s),
                         spread=0.006, rays=6, droop=0.006, res=(8, 12)))
        # Twin anal fins, long and trailing, near the tail.
        fins.append(_fin("Anal", surface(-0.012, "bottom") + Vector((0.0025 * sign, 0, 0.001)),
                         surface(-0.021, "bottom") + Vector((0.0025 * sign, 0, 0.001)),
                         (0.25 * sign, -1.0, -0.6), lambda s: 0.03 * math.sin(math.pi * s) ** 0.7 * (0.5 + 0.5 * s),
                         spread=0.006, rays=6, droop=0.008, res=(8, 12)))
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
        # Small and set into the head, looking out sideways and a little forward.
        r = 0.0036
        x = 0.83
        y = PEDUNCLE + (BODY_FRONT - PEDUNCLE) * x
        hw, hu, hd, c0 = _ring_radii(x)
        z = c0 + 0.35 * hu
        side = hw * math.sqrt(max(0.0, 1.0 - 0.35 ** 2))
        centre = Vector(((side - r * 0.35) * sign, y, z))
        look = Vector((1.0 * sign, 0.3, 0.12)).normalized()
        parts = []
        eye_mat = bpy.data.materials.get("FishEye") or material("FishEye", roughness=0.08, vertex_color=True)
        for name, radius, angle, colour in (("EyeWhite", r, None, (0.42, 0.3, 0.16)),
                                            ("IrisRim", r * 1.02, math.radians(82), (0.45, 0.25, 0.08)),
                                            ("Iris", r * 1.03, math.radians(74), PALETTE["eye_iris"]),
                                            ("Pupil", r * 1.04, math.radians(44), PALETTE["black"])):
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
