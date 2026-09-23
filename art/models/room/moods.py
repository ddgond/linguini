"""The three moods: their lighting (for baking and preview renders), the
lightmap bake itself, and the painted views outside the window.

Glow* materials are emissive; each mood sets how strongly. Godot mirrors
these settings with live lights and emissive materials for the things that
aren't baked (the fish, the tank and its decor): see
godot/scripts/room_moods.gd, which must stay in step with MOODS here.
"""

import math
import os
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

from lib.common import G, material, mesh_object, srgb_to_linear
from lib.render import use_cycles

import layout as L

MOOD_NAMES = ["night", "rainy", "golden"]

MOODS = {
    "night": {
        "world": ((0.02, 0.03, 0.07), 0.25),
        "sun": {"dir": (0.2, -0.5, 1.0), "color": (0.6, 0.7, 1.0), "strength": 0.25},
        "window_light": ((0.3, 0.4, 0.7), 8.0),
        "glow": {"GlowWarm": 6.0, "GlowCeiling": 0.0, "GlowRGB": 7.0, "GlowFairy": 5.0, "GlowTally": 4.0,
                 "GlowChat": 1.6, "GlowRing": 0.0, "Tank": 2.4, "Monitor": 2.2},
        "points": [("floor_lamp", (1.0, 0.72, 0.42), 35.0), ("bedside_lamp", (1.0, 0.7, 0.4), 18.0)],
        "rgb": (0.62, 0.3, 1.0),
    },
    "rainy": {
        "world": ((0.2, 0.26, 0.36), 1.1),
        "sun": None,
        "window_light": ((0.55, 0.65, 0.85), 45.0),
        "glow": {"GlowWarm": 5.0, "GlowCeiling": 0.0, "GlowRGB": 2.0, "GlowFairy": 5.0, "GlowTally": 4.0,
                 "GlowChat": 1.2, "GlowRing": 0.0, "Tank": 1.6, "Monitor": 1.4},
        "points": [("floor_lamp", (1.0, 0.72, 0.42), 35.0), ("bedside_lamp", (1.0, 0.7, 0.4), 18.0)],
        "rgb": (0.3, 0.7, 1.0),
    },
    "golden": {
        "world": ((0.95, 0.78, 0.6), 1.6),
        "sun": {"dir": (-0.3, -0.75, 1.0), "color": (1.0, 0.7, 0.42), "strength": 5.0},
        "window_light": ((1.0, 0.8, 0.6), 60.0),
        "glow": {"GlowWarm": 0.0, "GlowCeiling": 0.0, "GlowRGB": 0.6, "GlowFairy": 1.0, "GlowTally": 4.0,
                 "GlowChat": 0.8, "GlowRing": 0.0, "Tank": 0.8, "Monitor": 0.8},
        "points": [],
        "rgb": (1.0, 0.5, 0.3),
    },
}

GLOW_COLORS = {
    "GlowWarm": (1.0, 0.8, 0.55),
    "GlowCeiling": (1.0, 0.95, 0.85),
    "GlowFairy": (1.0, 0.82, 0.5),
    "GlowTally": (1.0, 0.1, 0.1),
    "GlowChat": (0.75, 0.8, 0.95),
    "GlowRing": (1.0, 0.98, 0.95),
}

QUALITY = {
    # size baked, size saved, samples
    "draft": (512, 512, 128),
    "final": (2048, 1024, 256),
}


# --- geometry ------------------------------------------------------------------

def lightmap_uvs(room):
    """A second UV map laid out for the lightmap (uniform texel density)."""
    me = room.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    lm = me.uv_layers.new(name="Lightmap")
    me.uv_layers.active = lm
    bpy.ops.object.select_all(action="DESELECT")
    room.select_set(True)
    bpy.context.view_layer.objects.active = room
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    me.uv_layers["UVMap"].active_render = True
    me.uv_layers.active = me.uv_layers["UVMap"]


def window_glass():
    wl = L.WINDOW_CENTER_X - L.WINDOW_WIDTH / 2
    wr = L.WINDOW_CENTER_X + L.WINDOW_WIDTH / 2
    z = L.ROOM_MIN[2] - L.WALL / 2 - 0.02
    bm = bmesh.new()
    vs = [bm.verts.new(G(wl, L.WINDOW_SILL, z)), bm.verts.new(G(wr, L.WINDOW_SILL, z)),
          bm.verts.new(G(wr, L.WINDOW_TOP, z)), bm.verts.new(G(wl, L.WINDOW_TOP, z))]
    bm.faces.new(vs)
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop, (u, v) in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv].uv = (u, v)
    return mesh_object("WindowGlass", bm, [material("WindowGlass", (0.85, 0.92, 0.95), roughness=0.05, alpha=0.1)])


def window_view():
    """A big backdrop outside the window, showing the mood's view."""
    z = L.ROOM_MIN[2] - 2.2
    cx = L.WINDOW_CENTER_X
    w, y0, y1 = 7.0, -0.8, 3.9
    bm = bmesh.new()
    vs = [bm.verts.new(G(cx - w / 2, y0, z)), bm.verts.new(G(cx + w / 2, y0, z)),
          bm.verts.new(G(cx + w / 2, y1, z)), bm.verts.new(G(cx - w / 2, y1, z))]
    bm.faces.new(vs)
    uv = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for loop, (u, v) in zip(face.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop[uv].uv = (u, v)
    mat = material("WindowView", (1, 1, 1), roughness=1.0)
    obj = mesh_object("WindowView", bm, [mat])
    obj.visible_shadow = False  # the sun shines past it, through the window
    return obj


# --- mood setup ----------------------------------------------------------------

def _set_emission(mat, color, strength):
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        return
    bsdf.inputs["Emission Color"].default_value = (*srgb_to_linear(color), 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength


def _stand_ins(tank=True):
    """Things the bake needs that the room mesh doesn't include: the tank
    (lit from inside, casting a cool glow) and the monitor's screen."""
    tx, ty, tz = L.TANK_ORIGIN
    stand = material("StandIn", (0.35, 0.24, 0.16), roughness=0.6)
    glow = material("TankGlow", (0.7, 0.9, 1.0), roughness=0.5)
    screen = material("MonitorGlow", (0.7, 0.8, 1.0), roughness=0.5)
    parts = []
    if tank:
        for name, mat, scale, y in (("StandInStand", stand, (1.3, 0.62, 0.8), 0.4),
                                    ("StandInTank", glow, (1.2, 0.5, 0.6), ty + 0.3)):
            bm = bmesh.new()
            bmesh.ops.create_cube(bm, size=1.0)
            obj = mesh_object(name, bm, [mat])
            obj.scale = scale
            obj.location = G(tx, y, tz)
            parts.append(obj)
    sx, sy, sz = L.SCREEN_CENTER
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    obj = mesh_object("StandInScreen", bm, [screen])
    obj.scale = (0.004, L.SCREEN_SIZE[0], L.SCREEN_SIZE[1])
    obj.location = G(sx - 0.003, sy, sz)
    parts.append(obj)
    return parts


def _apply_mood(name, room):
    """Sets the world, lights and emission for a mood. Returns the lights made."""
    mood = MOODS[name]
    scene = bpy.context.scene
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    colour, strength = mood["world"]
    bg.inputs["Color"].default_value = (*srgb_to_linear(colour), 1.0)
    bg.inputs["Strength"].default_value = strength

    for mat in bpy.data.materials:
        if mat.name in GLOW_COLORS:
            _set_emission(mat, GLOW_COLORS[mat.name], mood["glow"].get(mat.name, 0.0))
        elif mat.name == "GlowRGB":
            _set_emission(mat, mood["rgb"], mood["glow"]["GlowRGB"])
        elif mat.name == "TankGlow":
            _set_emission(mat, (0.7, 0.92, 1.0), mood["glow"]["Tank"])
        elif mat.name == "MonitorGlow":
            _set_emission(mat, (0.65, 0.78, 1.0), mood["glow"]["Monitor"])

    lights = []

    def add(kind, name_, location, colour_, energy, size=0.1, rotation=None):
        data = bpy.data.lights.new(name_, kind)
        data.color = srgb_to_linear(colour_)
        data.energy = energy
        if kind in ("POINT", "SPOT"):
            data.shadow_soft_size = size
        elif kind == "AREA":
            data.shape = "RECTANGLE"
            data.size, data.size_y = size
        obj = bpy.data.objects.new(name_, data)
        scene.collection.objects.link(obj)
        obj.location = location
        if rotation is not None:
            obj.rotation_euler = rotation
        lights.append(obj)
        return obj

    points = {"floor_lamp": L.FLOOR_LAMP, "bedside_lamp": L.BEDSIDE_LAMP}
    for key, colour_, energy in mood["points"]:
        add("POINT", key, G(*points[key]), colour_, energy, 0.08)
    if mood["sun"]:
        s = mood["sun"]
        d = G(*s["dir"]).normalized()
        sun = add("SUN", "Sun", G(0, 2, 0), s["color"], s["strength"])
        sun.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sun.data.angle = math.radians(1.5)
    # Sky light through the window, as an area light filling the opening.
    colour_, energy = mood["window_light"]
    wz = L.ROOM_MIN[2] - L.WALL - 0.05
    area = add("AREA", "WindowLight", G(L.WINDOW_CENTER_X, (L.WINDOW_SILL + L.WINDOW_TOP) / 2, wz), colour_, energy,
               (L.WINDOW_WIDTH, L.WINDOW_TOP - L.WINDOW_SILL))
    area.rotation_euler = G(0, 0, 1).to_track_quat("-Z", "Y").to_euler()
    return lights


# --- baking --------------------------------------------------------------------

def _denoise(arr, strength):
    """A light blur (the draft bake is noisy). arr: H x W x C float."""
    import numpy as np

    if strength <= 0:
        return arr
    k = np.array([1, 4, 6, 4, 1], np.float32)
    k /= k.sum()
    out = arr
    for _ in range(strength):
        out = sum(np.roll(out, i - 2, axis=0) * k[i] for i in range(5))
        out = sum(np.roll(out, i - 2, axis=1) * k[i] for i in range(5))
    return out


def bake_all(room, hidden, out_dir, quality):
    import numpy as np

    bake_size, save_size, samples = QUALITY[quality]
    scene = bpy.context.scene
    use_cycles(samples)
    scene.cycles.use_denoising = False
    # Clamp the indirect light's fireflies (bright specks from the lamp shades),
    # which a lightmap would show as blotches.
    scene.cycles.sample_clamp_indirect = 2.0
    scene.render.bake.margin = max(4, bake_size // 128)
    scene.render.bake.use_pass_direct = True
    scene.render.bake.use_pass_indirect = True
    scene.render.bake.use_pass_color = False
    for obj in hidden:
        obj.hide_render = True
    stand_ins = _stand_ins()

    me = room.data
    me.uv_layers.active = me.uv_layers["Lightmap"]
    # The bake records the light falling on each surface (Godot multiplies in
    # the colour), so metals must bake as diffuse or they'd come out black.
    metals = {}
    for mat in me.materials:
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf and bsdf.inputs["Metallic"].default_value > 0:
            metals[mat] = bsdf.inputs["Metallic"].default_value
            bsdf.inputs["Metallic"].default_value = 0.0
    for mood in MOOD_NAMES:
        lights = _apply_mood(mood, room)
        img = bpy.data.images.new(f"Lightmap_{mood}", bake_size, bake_size, alpha=False, float_buffer=True)
        nodes_added = []
        for mat in me.materials:
            node = mat.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = img
            mat.node_tree.nodes.active = node
            nodes_added.append((mat, node))
        bpy.ops.object.select_all(action="DESELECT")
        room.select_set(True)
        bpy.context.view_layer.objects.active = room
        print(f"baking {mood} at {bake_size}px, {samples} samples…", flush=True)
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, margin=scene.render.bake.margin,
                            use_clear=True, target="IMAGE_TEXTURES")

        px = np.empty(bake_size * bake_size * 4, np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(bake_size, bake_size, 4)[..., :3]
        if save_size != bake_size:
            f = bake_size // save_size
            px = px.reshape(save_size, f, save_size, f, 3).mean(axis=(1, 3))
        px = _denoise(px, 2 if quality == "draft" else 1)
        out = bpy.data.images.new(f"LightmapOut_{mood}", save_size, save_size, alpha=False, float_buffer=True)
        out.pixels.foreach_set(np.concatenate([px, np.ones((save_size, save_size, 1), np.float32)], axis=2).reshape(-1))
        path = out_dir / f"lightmap_{mood}.exr"
        scene.render.image_settings.file_format = "OPEN_EXR"
        scene.render.image_settings.color_depth = "16"
        scene.render.image_settings.exr_codec = "ZIP"
        out.save_render(str(path), scene=scene)
        print(f"saved {path.name}", flush=True)

        for mat, node in nodes_added:
            mat.node_tree.nodes.remove(node)
        for light in lights:
            bpy.data.objects.remove(light, do_unlink=True)
    me.uv_layers.active = me.uv_layers["UVMap"]
    for mat, value in metals.items():
        mat.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = value
    for obj in stand_ins:
        bpy.data.objects.remove(obj, do_unlink=True)
    for obj in hidden:
        obj.hide_render = False


# --- window views --------------------------------------------------------------

def _skyline(w, h, rng, base, height, count, np):
    """Building silhouettes: a height per column, and a mask of lit windows."""
    heights = np.zeros(w)
    x = 0
    while x < w:
        bw = int(rng.integers(w // 40, w // 14))
        bh = base + rng.uniform(0.2, 1.0) * height
        heights[x:x + bw] = np.maximum(heights[x:x + bw], bh)
        x += bw + int(rng.integers(0, w // 60))
    ys = np.arange(h)[:, None] / h
    building = (1.0 - ys) < heights[None, :]
    cols = (np.arange(w)[None, :] // 7) % 2 == 0
    rows = (np.arange(h)[:, None] // 9) % 2 == 0
    lit = building & cols & rows & (rng.random((h, w)) < 0.02).repeat(1, 0)
    # Make lit windows blocky: sample the randomness per 7x9 cell.
    cell = rng.random((h // 9 + 1, w // 7 + 1))
    cell_lit = cell[(np.arange(h) // 9)[:, None], (np.arange(w) // 7)[None, :]] < count
    return building, building & cols & rows & cell_lit


def paint_views(out_dir):
    import numpy as np

    w, h = 1024, 640
    ys = np.linspace(0, 1, h)[:, None, None]  # 0 = top
    xs = np.linspace(0, 1, w)[None, :, None]
    for mood in MOOD_NAMES:
        rng = np.random.default_rng({"night": 1, "rainy": 2, "golden": 3}[mood])
        if mood == "night":
            sky = (1 - ys) * np.array([0.07, 0.1, 0.22]) + ys * np.array([0.14, 0.12, 0.3])
            img = np.broadcast_to(sky, (h, w, 3)).copy()
            stars = (rng.random((h, w)) < 0.0012) & (ys[..., 0] < 0.55)
            img[stars] = [0.9, 0.9, 1.0]
            moon = ((xs[..., 0] - 0.78) ** 2 * (w / h) ** 2 + (ys[..., 0] - 0.22) ** 2) < 0.0022
            img[moon] = [0.95, 0.93, 0.85]
            far, far_lit = _skyline(w, h, rng, 0.3, 0.2, 0.25, np)
            img[far] = [0.09, 0.09, 0.17]
            img[far_lit] = [0.95, 0.75, 0.45]
            near, near_lit = _skyline(w, h, rng, 0.18, 0.2, 0.35, np)
            img[near] = [0.04, 0.04, 0.08]
            img[near_lit] = [1.0, 0.82, 0.5]
        elif mood == "rainy":
            sky = (1 - ys) * np.array([0.34, 0.4, 0.5]) + ys * np.array([0.45, 0.48, 0.55])
            img = np.broadcast_to(sky, (h, w, 3)).copy()
            far, far_lit = _skyline(w, h, rng, 0.3, 0.22, 0.2, np)
            img[far] = img[far] * 0.75 + np.array([0.3, 0.33, 0.4]) * 0.25
            img[far_lit] = [0.85, 0.72, 0.5]
            near, near_lit = _skyline(w, h, rng, 0.16, 0.2, 0.3, np)
            img[near] = [0.2, 0.22, 0.28]
            img[near_lit] = [0.95, 0.78, 0.5]
            # Haze: blur a little and lift toward grey.
            img = _denoise(img, 3) * 0.8 + np.array([0.4, 0.43, 0.5]) * 0.2
        else:
            sky = (1 - ys) * np.array([1.0, 0.62, 0.35]) ** 1.0 + ys * np.array([0.45, 0.62, 0.85])
            sky = ys ** 1.4 * np.array([0.5, 0.66, 0.88]) + (1 - ys ** 1.4) * np.array([1.0, 0.7, 0.42])
            img = np.broadcast_to(sky, (h, w, 3)).copy()
            d = np.sqrt((xs[..., 0] - 0.7) ** 2 * (w / h) ** 2 + (ys[..., 0] - 0.62) ** 2)
            img += (np.exp(-d * 9)[..., None] * np.array([1.0, 0.8, 0.5]) * 0.9)
            img[d < 0.045] = [1.0, 0.95, 0.82]
            far, _ = _skyline(w, h, rng, 0.28, 0.2, 0.0, np)
            img[far] = img[far] * 0.55 + np.array([0.55, 0.36, 0.3]) * 0.45
            near, _ = _skyline(w, h, rng, 0.15, 0.2, 0.0, np)
            img[near] = [0.3, 0.2, 0.18]
        img = np.clip(img, 0, 1)
        im = bpy.data.images.new(f"View_{mood}", w, h, alpha=False)
        im.pixels.foreach_set(np.concatenate([img[::-1], np.ones((h, w, 1))], axis=2).astype(np.float32).reshape(-1))
        im.filepath_raw = str(out_dir / f"view_{mood}.png")
        im.file_format = "PNG"
        im.save()


# --- tracker renders -----------------------------------------------------------

def render_moods(objects, renders_dir, model_id):
    """One preview per mood, from the doorway, with the mood's real lights."""
    scene = bpy.context.scene
    room, window, view = objects
    window.hide_render = True
    stand_ins = _stand_ins(tank=False)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(Path(__file__).resolve().parents[3] / "godot" / "art" / "tank.glb"))
    tank_parts = [o for o in bpy.data.objects if o not in before]
    for o in tank_parts:
        if o.parent is None:
            o.location += G(*L.TANK_ORIGIN)
    view_mat = view.data.materials[0]
    shots = [(mood, (-1.25, 1.55, 1.55), (0.35, 1.0, -1.4)) for mood in MOOD_NAMES]
    shots.append(("night", (1.55, 1.45, 0.9), (-1.6, 1.0, -0.6)))  # the bed side
    for i, (mood, eye, look) in enumerate(shots):
        lights = _apply_mood(mood, room)
        lamp = bpy.data.lights.new("TankLamp", "AREA")
        lamp.shape, lamp.size, lamp.size_y = "RECTANGLE", 1.1, 0.45
        lamp.color = srgb_to_linear((0.75, 0.92, 1.0))
        lamp.energy = 12.0 * MOODS[mood]["glow"]["Tank"]
        lamp_obj = bpy.data.objects.new("TankLamp", lamp)
        scene.collection.objects.link(lamp_obj)
        lamp_obj.location = G(L.TANK_ORIGIN[0], L.TANK_ORIGIN[1] + 0.62, L.TANK_ORIGIN[2])
        lights.append(lamp_obj)
        # The view as an emissive picture.
        nodes = view_mat.node_tree.nodes
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(Path(__file__).resolve().parents[3] / "godot" / "art" / "room" / f"view_{mood}.png"))
        bsdf = nodes["Principled BSDF"]
        view_mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.0
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
        use_cycles(int(os.environ.get("ART_RENDER_SAMPLES", "24")))
        scene.cycles.use_denoising = True
        scene.render.resolution_x, scene.render.resolution_y = 640, 360
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
        cam_data = bpy.data.cameras.new("Cam")
        cam_data.lens = 20
        cam = bpy.data.objects.new("Cam", cam_data)
        scene.collection.objects.link(cam)
        cam.location = G(*eye)
        target = G(*look)
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        suffix = "" if i == 0 else f"_{i + 1}"
        scene.render.image_settings.file_format = "PNG"  # the bake leaves it on EXR
        scene.render.image_settings.color_depth = "8"
        scene.render.filepath = str(renders_dir / f"{model_id}{suffix}.png")
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
        nodes.remove(tex)
        for light in lights:
            bpy.data.objects.remove(light, do_unlink=True)
    for obj in stand_ins + tank_parts:
        bpy.data.objects.remove(obj, do_unlink=True)
    window.hide_render = False
