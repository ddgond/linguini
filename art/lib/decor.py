"""Building blocks for tank decor (art/models/decor/*.py).

Decor conventions, on top of lib/common:
- Origin at the centre of the base, sitting on the gravel (Blender z = 0),
  front toward Blender -Y (the tank's front glass).
- Material names drive Godot: "Primary", "Secondary" and "Accent" take the
  colour variant's colours (times the painted "Col" colour); "Plant" gets
  the swaying plant shader; "Ember" glows; "Spill" is flowing water.
- For swaying parts, Anim UV u = sway weight (0 at the root, 1 at the tip).
- Collision: Godot gives a solid piece one convex hull of its whole mesh.
  Pieces with openings (an arch to swim through) instead add collision-only
  convex parts with collider(); Godot's importer turns objects named
  "*-convcolonly" into collision shapes and doesn't draw them.
"""

import math
import random

import bmesh
from mathutils import Matrix, Vector, noise

from lib.common import anim_uv, material, mesh_object, paint, shade_smooth, smoothstep


def mats(**colors):
    """Named decor materials with neutral base colours; Godot tints them."""
    out = {}
    for name, (color, roughness) in colors.items():
        out[name] = material(name, color, roughness=roughness, vertex_color=True)
        out[name].surface_render_method = "DITHERED"
        # Opaque: the colour attribute's alpha isn't transparency here.
        links = out[name].node_tree.links
        bsdf = out[name].node_tree.nodes["Principled BSDF"]
        for link in list(links):
            if link.to_socket == bsdf.inputs["Alpha"]:
                links.remove(link)
        bsdf.inputs["Alpha"].default_value = 1.0
    return out


def rock(name, size, seed, mat, roughness=0.5, flat_bottom=True, subdivisions=3):
    """A lumpy stone: a noise-displaced icosphere, flattened where it meets the gravel."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=0.5)
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in bm.verts:
        n = noise.fractal(v.co * 2.2 + off, 0.55, 2.0, 4)
        v.co *= 1.0 + roughness * 0.35 * n
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2] + size[2] * 0.42))
        if flat_bottom and v.co.z < 0.0:
            v.co.z = 0.0
    obj = mesh_object(name, bm, [mat])
    shade_smooth(obj)
    return obj


def paint_stone(obj, seed=0, moss=0.0):
    """Crevices darker, tops lighter, optional moss on upward faces."""
    off = Vector((seed, seed * 2, seed * 3))

    def colour(co, n):
        k = 0.78 + 0.22 * noise.noise(co * 40.0 + off) + 0.12 * max(n.z, 0.0)
        c = (k, k, k, 1.0)
        m = moss * smoothstep(0.35, 0.8, n.z) * smoothstep(-0.1, 0.4, noise.noise(co * 25.0 + off))
        if m > 0.0:
            green = (0.42, 0.62, 0.3)
            c = tuple(c[i] * (1 - m) + green[i] * m for i in range(3)) + (1.0,)
        return c

    paint(obj, colour)


def tube(name, points, radius, mat, sides=10, radius_fn=None, closed_ends=True):
    """A tube swept along `points` (list of Vector). radius_fn(t) scales the radius."""
    bm = bmesh.new()
    rings = []
    count = len(points)
    for i, p in enumerate(points):
        t = i / (count - 1)
        forward = (points[min(i + 1, count - 1)] - points[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(forward.z) < 0.95 else Vector((1, 0, 0))
        side = forward.cross(up).normalized()
        up = side.cross(forward).normalized()
        r = radius * (radius_fn(t) if radius_fn else 1.0)
        ring = []
        for j in range(sides):
            a = 2 * math.pi * j / sides
            ring.append(bm.verts.new(p + (side * math.cos(a) + up * math.sin(a)) * r))
        rings.append(ring)
    for i in range(count - 1):
        for j in range(sides):
            bm.faces.new((rings[i][j], rings[i][(j + 1) % sides], rings[i + 1][(j + 1) % sides], rings[i + 1][j]))
    if closed_ends:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj = mesh_object(name, bm, [mat])
    shade_smooth(obj)
    return obj


def bezier(p0, p1, p2, p3, steps=16):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append(p0 * u ** 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ** 3)
    return out


def ribbon(name, spine, widths, mat, normal_hint=Vector((0, -1, 0)), fold=0.0):
    """A flat strip (grass blade, leaf) along `spine`, `widths[i]` wide at each
    point. `fold` creases it along the middle. Anim UV u = distance along (0..1)."""
    bm = bmesh.new()
    rows = []
    n = len(spine)
    for i, p in enumerate(spine):
        forward = (spine[min(i + 1, n - 1)] - spine[max(i - 1, 0)]).normalized()
        side = forward.cross(normal_hint).normalized()
        if side.length < 0.1:
            side = Vector((1, 0, 0))
        face_n = side.cross(forward).normalized()
        w = widths[i] / 2
        mid = p + face_n * fold * widths[i]
        rows.append((bm.verts.new(p - side * w), bm.verts.new(mid), bm.verts.new(p + side * w)))
    for i in range(n - 1):
        a, b = rows[i], rows[i + 1]
        bm.faces.new((a[0], a[1], b[1], b[0]))
        bm.faces.new((a[1], a[2], b[2], b[1]))
    obj = mesh_object(name, bm, [mat])
    shade_smooth(obj)
    return obj


def sway_by_height(obj, height):
    """Anim UV u = height above the gravel / `height`, squared (roots stay put)."""
    anim_uv(obj, lambda co: (min(1.0, max(0.0, co.z / height)) ** 1.5, 0.0))


def still(obj):
    anim_uv(obj, lambda co: (0.0, 0.0))


def collider(name, points):
    """A collision-only convex hull around `points` (Vectors)."""
    bm = bmesh.new()
    verts = [bm.verts.new(p) for p in points]
    bmesh.ops.convex_hull(bm, input=verts)
    obj = mesh_object(f"{name}-convcolonly", bm)
    obj.hide_render = True
    return obj


def tube_colliders(name, points, radius, every=3):
    """Convex pieces hugging a tube, one per few spine segments."""
    out = []
    for i in range(0, len(points) - 1, every):
        seg = points[i:i + every + 1]
        pts = []
        for p in seg:
            for dx in (-radius, radius):
                for dy in (-radius, radius):
                    for dz in (-radius, radius):
                        pts.append(p + Vector((dx, dy, dz)))
        out.append(collider(f"{name}{i}", pts))
    return out


def box_points(center, size):
    c = Vector(center)
    return [c + Vector((sx * size[0] / 2, sy * size[1] / 2, sz * size[2] / 2))
            for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]


def rng(seed):
    return random.Random(seed)


def transformed(obj, matrix):
    obj.data.transform(matrix)
    return obj


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def move(x, y, z):
    return Matrix.Translation((x, y, z))
