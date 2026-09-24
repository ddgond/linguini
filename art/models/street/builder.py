"""A fast mesh builder for the street: big scenes made of thousands of boxes
and quads, collected in plain lists and turned into one Blender mesh per
builder at the end (bmesh per piece would take minutes).

Everything is given in Godot coordinates (x, y up, z; the room looks toward -Z)
and converted to Blender's when the mesh is made.

Per corner, each face carries:
  uv    UVMap (TEXCOORD_0). "metric" faces get world-aligned metres: u along
        the face (to the right, seen from outside), v up; floors get (x, -z).
  uv2   Data (TEXCOORD_1), for the shaders: sway weights, seeds and so on.
  col   Col (COLOR_0), linear RGBA: a surface tint, or seeds for the shaders.
"""

import math

import bpy
from mathutils import Vector

from lib.common import material, srgb_to_linear


def V(x, y, z):
    return Vector((x, y, z))


def lin(c, a=1.0):
    """An sRGB colour as a linear RGBA tuple."""
    return (*srgb_to_linear(c[:3]), c[3] if len(c) > 3 else a)


def _metric_axes(n):
    """World-aligned texture axes for a face with normal n: u to the right of
    someone looking at the face, v up (for walls), or x / -z (for floors)."""
    n = n.normalized()
    if abs(n.y) > 0.7:
        return V(1, 0, 0), V(0, 0, -1 if n.y > 0 else 1)
    u = V(0, 1, 0).cross(n).normalized() * -1.0
    # u points right when facing the wall: for a wall facing +z, u = +x.
    u = V(n.z, 0, -n.x).normalized()
    return u, V(0, 1, 0)


class Builder:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.mats = []
        self.uvs = []
        self.uv2s = []
        self.cols = []
        self.mat_names = []

    # --- basics ---------------------------------------------------------------

    def _mat(self, name):
        if name not in self.mat_names:
            self.mat_names.append(name)
        return self.mat_names.index(name)

    def face(self, pts, mat, col=(1, 1, 1, 1), uv=None, uv2=None, uv_scale=1.0, uv_offset=(0.0, 0.0)):
        """A polygon (points counter-clockwise seen from its front)."""
        pts = [p if isinstance(p, Vector) else V(*p) for p in pts]
        base = len(self.verts)
        self.verts.extend(pts)
        self.faces.append(tuple(range(base, base + len(pts))))
        self.mats.append(self._mat(mat))
        if uv is None or uv == "metric":
            n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
            if n.length < 1e-12 and len(pts) > 3:
                n = (pts[2] - pts[0]).cross(pts[3] - pts[0])
            u_ax, v_ax = _metric_axes(n if n.length > 1e-12 else V(0, 0, 1))
            uv = [((p.dot(u_ax) + uv_offset[0]) * uv_scale, (p.dot(v_ax) + uv_offset[1]) * uv_scale) for p in pts]
        self.uvs.append(list(uv))
        self.uv2s.append(list(uv2) if uv2 is not None else [(0.0, 0.0)] * len(pts))
        cols = col if isinstance(col, list) else [col] * len(pts)
        self.cols.append(cols)

    def quad(self, a, b, c, d, mat, **kw):
        self.face([a, b, c, d], mat, **kw)

    def box(self, lo, hi, mat, col=(1, 1, 1, 1), skip=(), uv2=None, uv_scale=1.0):
        """An axis-aligned box from corner lo to corner hi. `skip` names faces
        to leave out: "top", "bottom", "front" (+z), "back", "left" (-x), "right"."""
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        p = [V(x0, y0, z0), V(x1, y0, z0), V(x1, y1, z0), V(x0, y1, z0),
             V(x0, y0, z1), V(x1, y0, z1), V(x1, y1, z1), V(x0, y1, z1)]
        sides = {
            "front": (4, 5, 6, 7), "back": (1, 0, 3, 2), "left": (0, 4, 7, 3),
            "right": (5, 1, 2, 6), "top": (7, 6, 2, 3), "bottom": (0, 1, 5, 4),
        }
        for name, idx in sides.items():
            if name in skip:
                continue
            u2 = [uv2] * 4 if uv2 is not None and not isinstance(uv2, list) else uv2
            self.face([p[i] for i in idx], mat, col=col, uv2=u2, uv_scale=uv_scale)

    def cbox(self, center, size, mat, **kw):
        cx, cy, cz = center
        sx, sy, sz = size
        self.box((cx - sx / 2, cy - sy / 2, cz - sz / 2), (cx + sx / 2, cy + sy / 2, cz + sz / 2), mat, **kw)

    def oriented_box(self, center, size, yaw, mat, col=(1, 1, 1, 1), skip=(), uv2=None, pitch=0.0):
        """A box turned by `yaw` radians about y (and `pitch` about its own x)."""
        cx, cy, cz = center
        sx, sy, sz = [s / 2 for s in size]
        cy_, sy_ = math.cos(yaw), math.sin(yaw)
        cp, sp = math.cos(pitch), math.sin(pitch)

        def t(x, y, z):
            y, z = y * cp - z * sp, y * sp + z * cp
            return V(cx + x * cy_ + z * sy_, cy + y, cz - x * sy_ + z * cy_)

        p = [t(-sx, -sy, -sz), t(sx, -sy, -sz), t(sx, sy, -sz), t(-sx, sy, -sz),
             t(-sx, -sy, sz), t(sx, -sy, sz), t(sx, sy, sz), t(-sx, sy, sz)]
        sides = {
            "front": (4, 5, 6, 7), "back": (1, 0, 3, 2), "left": (0, 4, 7, 3),
            "right": (5, 1, 2, 6), "top": (7, 6, 2, 3), "bottom": (0, 1, 5, 4),
        }
        for name, idx in sides.items():
            if name not in skip:
                u2 = [uv2] * 4 if uv2 is not None and not isinstance(uv2, list) else uv2
                self.face([p[i] for i in idx], mat, col=col, uv2=u2)

    def cylinder(self, base, height, radius, mat, col=(1, 1, 1, 1), sides=10, top=True, bottom=False,
                 radius_top=None, axis="y", uv2=None, u_scale=None):
        """A cylinder (or cone, with radius_top) standing on `base` along +axis."""
        rt = radius if radius_top is None else radius_top
        bx, by, bz = base

        def pt(r, a, h):
            c, s = math.cos(a) * r, math.sin(a) * r
            if axis == "y":
                return V(bx + c, by + h, bz + s)
            if axis == "x":
                return V(bx + h, by + c, bz + s)
            return V(bx + c, by + s, bz + h)

        circ = 2 * math.pi * max(radius, rt)
        us = u_scale if u_scale is not None else circ
        for i in range(sides):
            a0 = 2 * math.pi * i / sides
            a1 = 2 * math.pi * (i + 1) / sides
            q = [pt(radius, a0, 0), pt(radius, a1, 0), pt(rt, a1, height), pt(rt, a0, height)]
            if axis == "y":
                q = [q[1], q[0], q[3], q[2]]
            uv = [(us * (i + 1) / sides, 0), (us * i / sides, 0), (us * i / sides, height), (us * (i + 1) / sides, height)] \
                if axis == "y" else [(us * i / sides, 0), (us * (i + 1) / sides, 0), (us * (i + 1) / sides, height), (us * i / sides, height)]
            u2 = [uv2] * 4 if uv2 is not None and not isinstance(uv2, list) else uv2
            self.face(q, mat, col=col, uv=uv, uv2=u2)
        if top and rt > 0:
            ring = [pt(rt, 2 * math.pi * i / sides, height) for i in range(sides)]
            if axis == "y":
                ring.reverse()
            self.face(ring, mat, col=col, uv2=[uv2] * sides if uv2 is not None and not isinstance(uv2, list) else None)
        if bottom:
            ring = [pt(radius, 2 * math.pi * i / sides, 0) for i in range(sides)]
            if axis != "y":
                ring.reverse()
            self.face(ring, mat, col=col)

    def tube(self, points, radius, mat, col=(1, 1, 1, 1), sides=6, uv2=None):
        """A tube along a polyline (wires, railings, branches)."""
        pts = [p if isinstance(p, Vector) else V(*p) for p in points]
        rings = []
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            a = V(0, 1, 0) if abs(d.y) < 0.9 else V(1, 0, 0)
            n1 = d.cross(a).normalized()
            n2 = d.cross(n1).normalized()
            r = radius[i] if isinstance(radius, (list, tuple)) else radius
            rings.append([p + (n1 * math.cos(2 * math.pi * k / sides) + n2 * math.sin(2 * math.pi * k / sides)) * r
                          for k in range(sides)])
        length = 0.0
        for i in range(len(pts) - 1):
            seg = (pts[i + 1] - pts[i]).length
            for k in range(sides):
                q = [rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]]
                uv = [(k / sides, length), ((k + 1) / sides, length), ((k + 1) / sides, length + seg), (k / sides, length + seg)]
                u2 = uv2[i] if isinstance(uv2, list) else uv2
                self.face(q, mat, col=col, uv=uv, uv2=[u2] * 4 if u2 is not None else None)
            length += seg

    # --- output ---------------------------------------------------------------

    def build(self, name, materials):
        """Makes the Blender object. `materials` maps a material name to its
        common.material() arguments."""
        me = bpy.data.meshes.new(name)
        # Godot (x, y, z) -> Blender (x, -z, y)
        me.vertices.add(len(self.verts))
        flat = []
        for v in self.verts:
            flat.extend((v.x, -v.z, v.y))
        me.vertices.foreach_set("co", flat)
        loop_total = [len(f) for f in self.faces]
        loop_start = []
        s = 0
        for n in loop_total:
            loop_start.append(s)
            s += n
        me.loops.add(s)
        me.polygons.add(len(self.faces))
        me.loops.foreach_set("vertex_index", [i for f in self.faces for i in f])
        me.polygons.foreach_set("loop_start", loop_start)
        me.polygons.foreach_set("material_index", self.mats)
        me.update(calc_edges=True)
        uv = me.uv_layers.new(name="UVMap")
        uv.data.foreach_set("uv", [c for f in self.uvs for p in f for c in p])
        uv2 = me.uv_layers.new(name="Data")
        uv2.data.foreach_set("uv", [c for f in self.uv2s for p in f for c in p])
        col = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        col.data.foreach_set("color", [c for f in self.cols for p in f for c in p])
        me.color_attributes.active_color = col
        me.uv_layers.active = uv
        for p in me.polygons:
            p.use_smooth = False
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        for m in self.mat_names:
            args = materials.get(m, {})
            obj.data.materials.append(material(m, **args))
        me.validate()
        # Weld corners that share a position; the exporter keeps faces apart
        # where their normals, UVs or colours differ.
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bm.to_mesh(me)
        bm.free()
        return obj
