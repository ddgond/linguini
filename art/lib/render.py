"""Studio renders of a model for the progress tracker (Cycles on the CPU, so it
works headless). Frames the model's bounds automatically."""

import math

import bpy
from mathutils import Vector


def _bounds(objects):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        if obj.type != "MESH" or obj.hide_render:
            continue
        for corner in obj.bound_box:
            w = obj.matrix_world @ Vector(corner)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def _look_at(obj, target):
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render(objects, out_png, yaw_deg=35.0, pitch_deg=18.0, size=640, samples=48, background=(0.86, 0.91, 0.9)):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"

    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (*background, 1.0)
    bg.inputs["Strength"].default_value = 0.6

    lo, hi = _bounds(objects)
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 0.01)

    # Key, fill and rim lights. Power grows with distance squared so a model
    # of any size gets the same light (`weight` is relative to the key).
    def light(name, weight, direction, size_mult):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = 450.0 * radius * radius * weight
        data.size = radius * size_mult
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = center + Vector(direction).normalized() * radius * 4
        _look_at(obj, center)
        return obj

    temp = [
        light("Key", 1.0, (1.2, -1.5, 1.6), 3.0),
        light("Fill", 0.35, (-1.6, -0.8, 0.6), 4.0),
        light("Rim", 0.6, (-0.4, 1.8, 1.2), 2.0),
    ]
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 70
    cam_data.clip_start = radius * 0.01
    cam_data.clip_end = radius * 100
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    # Distance that fits the bounding sphere in a 70 mm lens's field of view.
    fov = 2 * math.atan(36 / (2 * cam_data.lens))
    dist = radius / math.sin(fov / 2) * 1.08
    cam.location = center + Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch))) * dist
    _look_at(cam, center)
    scene.camera = cam
    temp.append(cam)

    scene.render.filepath = out_png
    bpy.ops.render.render(write_still=True)

    for obj in temp:
        bpy.data.objects.remove(obj, do_unlink=True)
