"""The neighbourhood outside the bedroom window: a street of brick rowhouses
and corner shops seen from the third floor, with a cross street, the taller
blocks behind and downtown in the distance.

Outputs (godot/art/street/):
  street.glb     Ground, Buildings, Props, Leaves, Signs, Skyline, and car
                 templates (CarTemplate_*) the game drives past; all in the
                 room model's coordinates
  layout.json    lamps, porch lights, neon signs, shop windows, traffic
                 signals, tree positions, beacons and traffic lanes

Materials are placeholders Godot swaps for its own shaders by name
(godot/scripts/street_builder.gd); Col and the Data UV map carry tints and
seeds for them (see builder.py and facades.py).
"""

import json
import random
from pathlib import Path

import bpy

from builder import Builder
import cars
import facades
import people
import ground
import props
import skyline
import street_layout as S

OUT = Path(__file__).resolve().parents[3] / "godot" / "art" / "street"

MATERIALS = {
    "Brick": {"vertex_color": True, "roughness": 0.9},
    "Stucco": {"vertex_color": True, "roughness": 0.85},
    "Siding": {"vertex_color": True, "roughness": 0.8},
    "GhostPaint": {"vertex_color": True, "roughness": 0.9},
    "Stone": {"vertex_color": True, "roughness": 0.8},
    "Trim": {"vertex_color": True, "roughness": 0.6},
    "Wood": {"vertex_color": True, "roughness": 0.7},
    "Roof": {"vertex_color": True, "roughness": 0.95},
    "Window": {"color": (0.1, 0.12, 0.15), "roughness": 0.05},
    "Asphalt": {"vertex_color": True, "roughness": 0.9},
    "Concrete": {"vertex_color": True, "roughness": 0.9},
    "Curb": {"vertex_color": True, "roughness": 0.85},
    "RoadPaint": {"vertex_color": True, "roughness": 0.7},
    "Soil": {"vertex_color": True, "roughness": 1.0},
    "Metal": {"vertex_color": True, "roughness": 0.5, "metallic": 0.6},
    "MetalPaint": {"vertex_color": True, "roughness": 0.45},
    "Iron": {"vertex_color": True, "roughness": 0.55},
    "Railing": {"vertex_color": True, "roughness": 0.55},
    "Brass": {"vertex_color": True, "roughness": 0.3, "metallic": 1.0},
    "Wire": {"vertex_color": True, "roughness": 0.6},
    "Grate": {"vertex_color": True, "roughness": 0.75},
    "Bark": {"vertex_color": True, "roughness": 0.95},
    "Foliage": {"vertex_color": True, "roughness": 0.8},
    "Awning": {"vertex_color": True, "roughness": 0.9},
    "Lamp": {"vertex_color": True, "roughness": 0.3},
    "Neon": {"vertex_color": True, "roughness": 0.3},
    "SignPaint": {"vertex_color": True, "roughness": 0.5},
    "Signal": {"color": (0.2, 0.2, 0.2), "roughness": 0.2},
    "SignalHousing": {"vertex_color": True, "roughness": 0.6},
    "Skyline": {"vertex_color": True, "roughness": 0.4},
    "CarPaint": {"vertex_color": True, "roughness": 0.25},
    "CarGlass": {"vertex_color": True, "roughness": 0.05},
    "Rubber": {"vertex_color": True, "roughness": 0.9},
    "Chrome": {"vertex_color": True, "roughness": 0.2, "metallic": 1.0},
    "Headlight": {"vertex_color": True, "roughness": 0.1},
    "Taillight": {"vertex_color": True, "roughness": 0.1},
    "Plate": {"vertex_color": True, "roughness": 0.5},
    "Walker": {"vertex_color": True, "roughness": 0.8},
    "Umbrella": {"vertex_color": True, "roughness": 0.4},
    "Bird": {"color": (0.35, 0.36, 0.4), "roughness": 0.8},
}


def add_text(b, t):
    """Lettering from Blender's built-in font, placed in a facade Frame: flat
    painted letters, or (tube=True) outlines for neon."""
    cu = bpy.data.curves.new("Text", "FONT")
    cu.body = t["text"]
    cu.size = t["size"]
    cu.align_x = "CENTER"
    cu.resolution_u = 3  # the default 12 made each sign thousands of triangles
    if t.get("tube"):
        cu.fill_mode = "NONE"
        cu.bevel_depth = t["size"] * 0.035
        cu.bevel_resolution = 0
    elif not t.get("flat"):
        cu.extrude = 0.006
    obj = bpy.data.objects.new("Text", cu)
    bpy.context.scene.collection.objects.link(obj)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    me = ev.to_mesh()
    fr = t["frame"]
    for poly in me.polygons:
        pts = [me.vertices[i].co for i in poly.vertices]
        b.face([fr.p(t["u"] + p.x, t["y"] + p.y, t["w"] + p.z) for p in pts], t["mat"], col=t["col"])
    ev.to_mesh_clear()
    bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.curves.remove(cu)


def build():
    rng = random.Random(11)
    layout = {"lamps": [], "porch": [], "neon": [], "shops": [], "signals": [], "beacons": [], "trees": [],
              "lanes": [], "cars": [], "walkers": []}

    # Where the trees go (their pits are part of the ground).
    layout["trees"] = [[5.6, -5.0], [-16.0, -5.0], [22.5, -5.0], [-34.0, -5.0],
                       [-23.5, -17.3], [-8.5, -17.3], [31.0, -17.3], [45.0, -17.3], [-45.0, -17.3],
                       [9.3, -42.0], [9.3, -74.0], [18.7, -56.0], [18.7, -95.0]]

    gb = Builder()
    ground.build(gb, rng, layout)

    bb = Builder()
    texts = []
    facades.far_row(bb, rng, layout, texts)
    facades.cross_street(bb, rng, layout, texts)
    facades.second_row(bb, rng, layout, texts)

    pb = Builder()
    leaves = Builder()
    for i, (x, z) in enumerate(layout["trees"]):
        big = i == 0
        tint = rng.choice([(1.0, 1.0, 1.0), (0.95, 1.05, 0.9), (1.1, 1.0, 0.8)])
        # The one outside our window tops out about level with the sill, so
        # you look out over its crown.
        props.tree(pb, leaves, x, z, rng, height=7.6 if big else rng.uniform(8.0, 10.0),
                   spread=2.6 if big else rng.uniform(2.4, 3.0), tint=tint)
    for x in (-12.0, 13.0, -38.0, 36.0):
        props.street_lamp(pb, x, S.NEAR_CURB_Z + 0.4, (0, -1), layout)
    for x in (-17.0, 2.5, 27.0, 46.0, -44.0):
        props.street_lamp(pb, x, S.FAR_CURB_Z - 0.4, (0, 1), layout)
    for z in (-35.0, -68.0, -100.0):
        props.street_lamp(pb, S.CROSS_X0 + S.CROSS_WALK - 0.4, z, (1, 0), layout)
        props.street_lamp(pb, S.CROSS_X1 - S.CROSS_WALK + 0.4, z - 16.0, (-1, 0), layout)
    rx0, rx1 = S.CROSS_X0 + S.CROSS_WALK, S.CROSS_X1 - S.CROSS_WALK
    props.traffic_signal(pb, rx0 - 0.5, S.FAR_CURB_Z - 0.5, [(1, 0, 0), (0, -1, 1)], layout)
    props.traffic_signal(pb, rx1 + 0.5, S.FAR_CURB_Z - 0.5, [(-1, 0, 0), (0, -1, 1)], layout)
    props.traffic_signal(pb, (rx0 + rx1) / 2 + 1.0, S.NEAR_CURB_Z + 0.5, [(1, 0, 0), (-1, 0, 0)], layout)
    props.street_sign(pb, rx0 - 0.9, S.FAR_CURB_Z - 0.9, texts)
    props.utility_poles(pb, rng, layout)
    props.hydrant(pb, -2.2, S.NEAR_CURB_Z + 0.45)
    props.hydrant(pb, 24.5, S.FAR_CURB_Z - 0.45)
    for x, z in ((6.8, S.NEAR_CURB_Z + 0.45), (rx0 - 1.3, S.FAR_CURB_Z - 0.5), (-20.8, S.FAR_CURB_Z - 0.5)):
        props.bin_(pb, x, z)
    props.mailbox(pb, 6.6, S.FAR_CURB_Z - 0.55)
    props.bike_rack(pb, -7.5, S.NEAR_CURB_Z + 0.6, rng)
    props.bike_rack(pb, 33.5, S.FAR_CURB_Z - 0.6, rng, with_bike=False)
    cafe = facades.Frame((0, 0, S.FAR_FACADE_Z), (1, 0, 0), (0, 0, 1))
    props.cafe_tables(pb, cafe, S.CROSS_X1, S.CROSS_X1 + 8.5, rng)
    props.aframe_sign(pb, S.CROSS_X1 + 9.2, S.FAR_FACADE_Z + 2.2, texts, "COFFEE")
    for x in (-0.6, 2.2):
        props.planter(pb, x, S.FAR_FACADE_Z + 0.5, rng)
    props.parked_cars(pb, rng, layout)

    sb = Builder()
    for t in texts:
        add_text(sb, t)

    kb = Builder()
    skyline.build(kb, rng, layout)

    objects = [gb.build("Ground", MATERIALS), bb.build("Buildings", MATERIALS), pb.build("Props", MATERIALS),
               sb.build("Signs", MATERIALS), kb.build("Skyline", MATERIALS)]
    leaf_img = _image("LeafAtlas", props.leaf_texture())
    lv = leaves.build("Leaves", {"LeafCards": {"image": leaf_img, "roughness": 0.7}})
    # Cut the leaves out in Blender's own renders too (Godot uses its own shader).
    mat = lv.data.materials[0]
    tex = next(n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE")
    mat.node_tree.links.new(tex.outputs["Alpha"], mat.node_tree.nodes["Principled BSDF"].inputs["Alpha"])
    objects.append(lv)

    # Cars for the game to drive past: at the origin, facing +x, on the road.
    for kind in cars.TYPES:
        for taxi in (False, True) if kind == "sedan" else (False,):
            cb = Builder()
            cars.place(cb, kind, 0.0, 0.0, 0.0, (0.95, 0.72, 0.1) if taxi else (1.0, 1.0, 1.0), taxi, y=S.ROAD_Y)
            o = cb.build("CarTemplate_" + kind + ("_taxi" if taxi else ""), MATERIALS)
            objects.append(o)
            layout["cars"].append({"name": o.name, "length": cars.TYPES[kind]["length"], "taxi": taxi})
    # People, and an umbrella, for the game to walk along the sidewalks.
    for kind in people.FIGURES:
        o = people.figure(kind).build("Walker_" + kind, MATERIALS)
        objects.append(o)
        layout["walkers"].append(o.name)
    objects.append(people.umbrella().build("Umbrella", MATERIALS))
    objects.append(people.bird().build("Bird", MATERIALS))
    layout["walk"] = [{"z": S.WALK_NEAR_Z, "x": [-60.0, 60.0]}, {"z": S.WALK_FAR_Z, "x": [-60.0, 70.0]}]
    layout["walk_y"] = S.WALK_Y
    layout["lanes"] = [
        {"z": S.NEAR_CURB_Z - S.PARKING - 1.6, "dir": 1, "x": list(S.STREET_X)},
        {"z": S.FAR_CURB_Z + S.PARKING + 1.6, "dir": -1, "x": list(S.STREET_X)},
    ]
    layout["road_y"] = S.ROAD_Y
    layout["cross"] = [S.CROSS_X0, S.CROSS_X1, S.CROSS_END_Z]

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "layout.json").write_text(json.dumps(layout, indent=1) + "\n")
    print(f"street: {sum(len(o.data.polygons) for o in objects)} faces")
    return objects


def _image(name, pixels):
    from lib.common import image_np
    return image_np(name, pixels)


def render(objects, renders_dir, model_id):
    """A tracker preview: the view from the bedroom window in late sun."""
    from lib.common import G
    from lib.render import use_cycles

    scene = bpy.context.scene
    for o in objects:
        if o.name.startswith(("CarTemplate_", "Walker_", "Umbrella", "Bird")):
            o.hide_render = True
    world = bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.65, 0.85, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.data.color = (1.0, 0.85, 0.7)
    scene.collection.objects.link(sun)
    sun.rotation_euler = G(0.4, -0.5, 0.6).normalized().to_track_quat("-Z", "Y").to_euler()
    use_cycles(int(__import__("os").environ.get("ART_RENDER_SAMPLES", "32")))
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 960, 540
    scene.view_settings.view_transform = "AgX"
    shots = [((-0.15, 1.5, -1.9), (-0.15, 0.3, -20.0), 22), ((-0.15, 3.0, -1.9), (12.0, -1.0, -30.0), 24),
             ((-0.15, 1.5, -1.9), (-12.0, 0.0, -20.0), 24)]
    for i, (eye, at, lens) in enumerate(shots):
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        cam.data.lens = lens
        cam.data.clip_end = 3000
        scene.collection.objects.link(cam)
        cam.location = G(*eye)
        cam.rotation_euler = (G(*at) - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        scene.render.image_settings.file_format = "PNG"
        scene.render.filepath = str(renders_dir / f"{model_id}{'' if i == 0 else f'_{i + 1}'}.png")
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
