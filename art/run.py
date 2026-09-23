"""Builds one model from art/catalog.json inside Blender.

    blender -b --factory-startup -P art/run.py -- MODEL_ID [--no-render] [--no-export]

Imports art/<script>, calls its build() (returning the objects to export),
exports them to godot/<output> as .glb, renders thumbnails into art/renders/,
and records the input hashes in art/manifest.json for art/check.py.
"""

import importlib.util
import json
import sys
from pathlib import Path

ART = Path(__file__).resolve().parent
ROOT = ART.parent
sys.path.insert(0, str(ART))

import bpy  # noqa: E402

from lib import common  # noqa: E402
from lib import render as studio  # noqa: E402
from lib.hashing import input_hash  # noqa: E402


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    model_id = argv[0]
    catalog = json.loads((ART / "catalog.json").read_text())
    entry = next(m for m in catalog["models"] if m["id"] == model_id)

    common.reset_scene()
    spec = importlib.util.spec_from_file_location(model_id, ART / entry["script"])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    objects = module.build(**entry.get("args", {}))

    if "--no-export" not in argv:
        out = ROOT / "godot" / entry["output"]
        out.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.object.select_all(action="DESELECT")
        for o in objects:
            o.select_set(True)
        bpy.ops.export_scene.gltf(
            filepath=str(out),
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_yup=True,
            export_texcoords=True,
            export_normals=True,
            export_vertex_color="ACTIVE",
            export_all_vertex_colors=False,
            export_materials="EXPORT",
            export_image_format="AUTO",
            export_extras=True,
        )
        manifest_path = ART / "manifest.json"
        manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
        manifest[model_id] = {"output": entry["output"], "inputs": input_hash(entry["script"], entry.get("args"))}
        manifest_path.write_text(json.dumps(dict(sorted(manifest.items())), indent=2) + "\n")
        print(f"exported {out.relative_to(ROOT)}")

    if "--no-render" not in argv:
        _preview_colours(model_id)
        renders = ART / "renders"
        renders.mkdir(exist_ok=True)
        views = getattr(module, "RENDER_VIEWS", [(35, 18)])
        for i, (yaw, pitch) in enumerate(views):
            suffix = "" if i == 0 else f"_{i + 1}"
            studio.render(objects, str(renders / f"{model_id}{suffix}.png"), yaw_deg=yaw, pitch_deg=pitch)
        print(f"rendered {len(views)} view(s) of {model_id}")


def _preview_colours(model_id):
    """Tints decor with its first colour variant for the renders (Godot does
    this itself at runtime from the same file). Runs after export, so the
    .glb keeps its neutral colours."""
    catalog = json.loads((ROOT / "godot" / "data" / "decor.json").read_text())
    item = catalog["items"].get(model_id)
    if not item:
        return
    variant = item["variants"][0]
    for mat in bpy.data.materials:
        hex_color = variant.get(mat.name)
        if not hex_color or not mat.use_nodes:
            continue
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        bsdf = nodes.get("Principled BSDF")
        base = bsdf.inputs["Base Color"]
        source = base.links[0].from_socket if base.links else None
        tint = common.srgb_to_linear(tuple(int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)))
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["B"].default_value = (*tint, 1.0)
        if source is not None:
            links.new(source, mix.inputs["A"])
        else:
            mix.inputs["A"].default_value = (1, 1, 1, 1)
        links.new(mix.outputs["Result"], base)
        if mat.name == item.get("glow"):
            bsdf.inputs["Emission Color"].default_value = (*tint, 1.0)
            bsdf.inputs["Emission Strength"].default_value = 3.0


main()
