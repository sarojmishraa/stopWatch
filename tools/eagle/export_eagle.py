#!/usr/bin/env python3
"""Blender 4.5+ intake/export of an ARTIST-AUTHORED eagle, not model generation.

Run with Blender --background --disable-autoexec --python this_file -- ...
The source is never saved over. Output must be a new directory.
"""
import argparse
import json
from pathlib import Path
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_glb import CONTRACT, Glb, parse_glb, require, validate


def check_license(path):
    data = json.loads(path.read_text())
    for key in ('title', 'author', 'source_url', 'license', 'license_url', 'attribution'):
        require(isinstance(data.get(key), str) and data[key].strip() and
                'REPLACE' not in data[key], f'Fill in licence field: {key}')
    require(data.get('species') == CONTRACT['species'], 'Source must be a golden eagle')
    require(data.get('app_distribution_permitted') is True and
            data.get('modifications_permitted') is True,
            'Confirm app distribution and modification rights from the actual licence')
    return data


def main():
    import bpy

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--license', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--collection', default='Eagle')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    require(bpy.app.version >= (4, 5, 0), 'Use Blender 4.5 LTS or newer')
    source, output = args.source.resolve(), args.output.resolve()
    require(source.is_file() and source.suffix == '.blend', 'Supply an authored .blend source')
    require(not output.exists(), 'Output exists; choose a new directory (never overwrite)')
    license_data = check_license(args.license)
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
    collection = bpy.data.collections.get(args.collection)
    require(collection is not None, f'No collection named {args.collection}')
    objects = list(collection.all_objects)
    rigs = [obj for obj in objects if obj.type == 'ARMATURE']
    meshes = [obj for obj in objects if obj.type == 'MESH']
    require(len(rigs) == 1 and meshes, 'Collection needs one rig and its eagle meshes')
    rig = rigs[0]
    missing = set(CONTRACT['bones']) - set(rig.data.bones.keys())
    require(not missing, 'Missing bones: ' + ', '.join(sorted(missing)))
    require(rig.data.bones['Root'].parent is None, 'Root bone must have no parent')
    require(rig.parent is None and all(abs(v) < 1e-5 for v in rig.location) and
            all(abs(v) < 1e-5 for v in rig.rotation_euler) and
            all(abs(v-1) < 1e-5 for v in rig.scale), 'Apply rig transforms at the origin')
    require(abs(bpy.context.scene.unit_settings.scale_length-1) < 1e-6, 'Use metre scale')
    actions = set(bpy.data.actions.keys())
    require(actions == set(CONTRACT['animations']),
            'Source must contain exactly the eight authored actions; no renamed copies or extras')
    for action in bpy.data.actions:
        require(action.frame_range[1] > action.frame_range[0], f'Empty action: {action.name}')
    for mesh in meshes:
        skinned = any(mod.type == 'ARMATURE' and mod.object == rig for mod in mesh.modifiers)
        rigid = mesh.parent == rig and mesh.parent_type == 'BONE'
        require(skinned or rigid, f'{mesh.name}: mesh is not bound to the eagle rig')
        require(mesh.data.uv_layers and mesh.data.materials and
                all(material is not None for material in mesh.data.materials),
                f'{mesh.name}: missing UVs or materials')
        require(all(material.use_nodes for material in mesh.data.materials),
                f'{mesh.name}: use exportable Principled BSDF materials')
    for image in bpy.data.images:
        if image.source not in ('FILE', 'GENERATED') or image.users == 0:
            continue
        require(image.has_data and min(image.size) > 0, f'Missing image: {image.name}')
        require(max(image.size) <= CONTRACT['max_texture_edge'],
                f'{image.name}: prepare a mobile texture at 2048 px or below')

    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.eagle-staging-', dir=output.parent))
    print(f'Export staging: {stage}')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [rig, *meshes]:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.file.pack_all()
    # Copy the authoring source with packed images before the export. No
    # geometry, rig, action curves or texture pixels are fabricated here.
    bpy.ops.wm.save_as_mainfile(filepath=str(stage / 'eagle_mascot.blend'), copy=True)
    glb_path = stage / CONTRACT['asset']
    options = dict(
        filepath=str(glb_path), export_format='GLB', use_selection=True,
        export_yup=True, export_texcoords=True, export_normals=True,
        export_tangents=True, export_materials='EXPORT', export_image_format='AUTO',
        export_animations=True, export_animation_mode='ACTIONS',
        export_force_sampling=True, export_frame_range=False,
        export_frame_step=1, export_anim_slide_to_zero=True,
        export_anim_single_armature=True, export_reset_pose_bones=True,
        export_skins=True, export_def_bones=False, export_influence_nb=4,
        export_all_influences=False, export_morph=True, export_morph_animation=True,
        export_cameras=False, export_lights=False,
        export_draco_mesh_compression_enable=False,
    )
    # Fail explicitly on incompatible exporter APIs instead of silently
    # dropping flags that affect skinning or clip separation.
    available = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    require(set(options) <= set(available), 'Exporter API changed; review unsupported flags: ' +
            ', '.join(sorted(set(options)-set(available))))
    bpy.ops.export_scene.gltf(**options)
    report = validate(glb_path)
    document, binary, _ = parse_glb(glb_path)
    glb = Glb(document, binary)
    textures = stage / 'textures'
    textures.mkdir()
    for i, image in enumerate(document['images']):
        _, pixels = glb.view(image['bufferView'])
        extension = '.png' if image['mimeType'] == 'image/png' else '.jpg'
        (textures / f'texture_{i:02}{extension}').write_bytes(pixels)
    shutil.copy2(args.license, stage / 'license.json')
    (stage / 'CREDITS.md').write_text(
        f"# {license_data['title']}\n\n{license_data['attribution']}\n\n"
        f"Source: {license_data['source_url']}\n\n"
        f"Licence: {license_data['license']} — {license_data['license_url']}\n\n"
        'Changes: mobile export, sampled animations and embedded PBR textures.\n')
    (stage / 'validation.json').write_text(json.dumps(report, indent=2) + '\n')
    # Atomic directory publication on the same filesystem. The app asset is
    # deliberately not changed; inspect this staged delivery before bundling.
    require(not output.exists(), 'Output appeared during export; refusing to overwrite')
    stage.rename(output)
    print(f'Exported and structurally checked: {output}')
    print('Visual realism, clip quality and Android QA are still required.')


if __name__ == '__main__':
    main()
