#!/usr/bin/env python3
"""Conservative mobile asset checks, not a photorealism or renderer certificate.

No third-party dependencies. Run Khronos glTF Validator and visual/device QA
as well; this script enforces the Eagle Study contract on an uncompressed GLB.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

CONTRACT = json.loads(Path(__file__).with_name('asset_contract.json').read_text())
COMPONENTS = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2),
              5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def parse_glb(path):
    data = Path(path).read_bytes()
    require(len(data) >= 20, 'Truncated GLB header')
    magic, version, length = struct.unpack_from('<4sII', data)
    require(magic == b'glTF' and version == 2, 'Expected glTF 2.0 GLB')
    require(length == len(data), 'GLB declared length does not match file')
    chunks, offset = [], 12
    while offset < length:
        require(offset + 8 <= length, 'Truncated chunk header')
        size, kind = struct.unpack_from('<II', data, offset)
        offset += 8
        require(size % 4 == 0 and offset + size <= length, 'Invalid chunk length')
        chunks.append((kind, data[offset:offset + size]))
        offset += size
    require(len(chunks) == 2 and chunks[0][0] == 0x4E4F534A and
            chunks[1][0] == 0x004E4942, 'Expected one JSON and one BIN chunk')
    document = json.loads(chunks[0][1])
    require(document.get('asset', {}).get('version') == '2.0', 'Invalid glTF version')
    return document, chunks[1][1], data


class Glb:
    def __init__(self, document, binary):
        self.doc, self.binary = document, binary

    def item(self, collection, index):
        values = self.doc.get(collection, [])
        require(type(index) is int and 0 <= index < len(values),
                f'Invalid {collection} index: {index}')
        return values[index]

    def view(self, index):
        view = self.item('bufferViews', index)
        require(view.get('buffer') == 0, 'Buffer view must use embedded buffer 0')
        start, length = view.get('byteOffset', 0), view['byteLength']
        require(start >= 0 and length > 0 and start + length <= len(self.binary),
                'Buffer view outside BIN chunk')
        return view, self.binary[start:start + length]

    def accessor(self, index):
        acc = self.item('accessors', index)
        require('sparse' not in acc, 'Bake sparse accessors before mobile export')
        require(acc.get('componentType') in COMPONENTS and acc.get('type') in WIDTHS,
                'Unsupported accessor layout')
        code, width = COMPONENTS[acc['componentType']]
        count, components = acc['count'], WIDTHS[acc['type']]
        require(count > 0, 'Empty accessor')
        view, raw = self.view(acc.get('bufferView'))
        size = components * width
        stride, start = view.get('byteStride', size), acc.get('byteOffset', 0)
        require(stride >= size and stride % width == 0 and start >= 0 and
                start % width == 0 and start + (count - 1) * stride + size <= len(raw),
                'Accessor outside buffer view or incorrectly aligned')
        result = [struct.unpack_from('<' + code * components, raw, start + i * stride)
                  for i in range(count)]
        require(all(math.isfinite(x) for row in result for x in row),
                'Non-finite geometry or animation value')
        if acc.get('normalized') and acc['componentType'] != 5126:
            divisor = {5120: 127, 5121: 255, 5122: 32767, 5123: 65535}.get(acc['componentType'])
            require(divisor is not None, 'Invalid normalized component type')
            result = [tuple(max(-1, x / divisor) for x in row) for row in result]
        return result


def image_dimensions(data, mime):
    if mime == 'image/png':
        require(len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n' and
                data[12:16] == b'IHDR', 'Invalid PNG header')
        return struct.unpack_from('>II', data, 16)
    require(mime == 'image/jpeg' and data[:2] == b'\xff\xd8', 'Expected PNG or JPEG image')
    offset = 2
    while offset + 4 <= len(data):
        require(data[offset] == 255, 'Invalid JPEG marker')
        while offset < len(data) and data[offset] == 255:
            offset += 1
        require(offset < len(data), 'Truncated JPEG marker')
        marker = data[offset]
        offset += 1
        require(marker not in (0xD9, 0xDA), 'JPEG missing size marker')
        size = struct.unpack_from('>H', data, offset)[0]
        require(size >= 2 and offset + size <= len(data), 'Truncated JPEG segment')
        if marker in (0xC0, 0xC1, 0xC2):
            require(size >= 8, 'Invalid JPEG size marker')
            height, width = struct.unpack_from('>HH', data, offset + 3)
            return width, height
        offset += size
    raise ValueError('JPEG missing dimensions')


def validate(path):
    doc, binary, raw = parse_glb(path)
    glb = Glb(doc, binary)
    require(len(raw) <= CONTRACT['max_glb_bytes'], 'GLB exceeds 30 MiB budget')
    buffers = doc.get('buffers', [])
    require(len(buffers) == 1 and 'uri' not in buffers[0], 'External buffers are forbidden')
    require(0 <= len(binary) - buffers[0]['byteLength'] <= 3, 'BIN buffer length mismatch')
    compressed = {'KHR_draco_mesh_compression', 'EXT_meshopt_compression', 'KHR_texture_basisu'}
    require(not compressed.intersection(doc.get('extensionsUsed', [])),
            'Compression is disabled until renderer compatibility is verified')
    require(not doc.get('extensionsRequired'), 'Required extensions need an explicit renderer review')
    for index in range(len(doc.get('bufferViews', []))):
        glb.view(index)
    for index in range(len(doc.get('accessors', []))):
        glb.accessor(index)

    nodes = doc.get('nodes', [])
    require(nodes, 'No nodes')
    names = [node.get('name') for node in nodes]
    require(all(names) and len(names) == len(set(names)),
            'Every node needs a unique name for Flutter Scene animation binding')
    parents = {}
    for parent, node in enumerate(nodes):
        require(not ('matrix' in node and any(k in node for k in ('translation', 'rotation', 'scale'))),
                'Node contains both matrix and TRS')
        for key in ('translation', 'rotation', 'scale', 'matrix'):
            require(all(math.isfinite(x) for x in node.get(key, [])), 'Invalid node transform')
        for child in node.get('children', []):
            glb.item('nodes', child)
            require(child not in parents, 'Node has multiple parents')
            parents[child] = parent
    for start in range(len(nodes)):
        visited, current = set(), start
        while current in parents:
            require(current not in visited, 'Cyclic node hierarchy')
            visited.add(current)
            current = parents[current]
    active_scene = glb.item('scenes', doc.get('scene', 0))
    reachable = set()
    def visit(index):
        glb.item('nodes', index)
        if index in reachable:
            return
        reachable.add(index)
        for child in nodes[index].get('children', []):
            visit(child)
    for index in active_scene.get('nodes', []):
        require(index not in parents, 'Scene root has a parent')
        visit(index)
    require(reachable, 'Default scene is empty')
    skins = doc.get('skins', [])
    require(skins, 'No skeletal skin')
    joint_names = set()
    for skin in skins:
        joints = skin.get('joints', [])
        require(joints and len(joints) == len(set(joints)), 'Empty or duplicated skin joints')
        for joint in joints:
            joint_names.add(glb.item('nodes', joint)['name'])
            require(joint in reachable, 'Joint not in default scene')
        inverse = glb.item('accessors', skin.get('inverseBindMatrices'))
        require(inverse['type'] == 'MAT4' and inverse['componentType'] == 5126 and
                inverse['count'] == len(joints), 'Invalid inverse bind matrices')
    require(set(CONTRACT['bones']) <= joint_names,
            'Missing rig bones: ' + ', '.join(sorted(set(CONTRACT['bones']) - joint_names)))

    images = doc.get('images', [])
    require(images, 'No embedded textures')
    texture_bytes, dimensions = 0, []
    for image in images:
        require('uri' not in image, 'Textures must use embedded buffer views')
        _, data = glb.view(image.get('bufferView'))
        w, h = image_dimensions(data, image.get('mimeType'))
        require(0 < w <= CONTRACT['max_texture_edge'] and 0 < h <= CONTRACT['max_texture_edge'],
                'Texture exceeds 2048 px or has invalid size')
        dimensions.append([w, h])
        texture_bytes += math.ceil(w * h * 4 * 4 / 3)
    require(texture_bytes <= CONTRACT['max_texture_memory_bytes'], 'Texture memory exceeds 128 MiB')
    for texture in doc.get('textures', []):
        glb.item('images', texture.get('source'))
    mapped_plumage = False
    for material in doc.get('materials', []):
        pbr = material.get('pbrMetallicRoughness', {})
        require(pbr, 'Material missing PBR properties')
        slots = [pbr.get('baseColorTexture'), pbr.get('metallicRoughnessTexture'),
                 material.get('normalTexture'), material.get('occlusionTexture'),
                 material.get('emissiveTexture')]
        for slot in filter(None, slots):
            glb.item('textures', slot.get('index'))
        mapped_plumage |= all(slot is not None for slot in slots[:3])
    require(mapped_plumage, 'Plumage needs base-color, normal and metallic-roughness maps')

    triangles, skinned_meshes = 0, 0
    for node_index in reachable:
        node = nodes[node_index]
        if 'mesh' not in node:
            continue
        skin = glb.item('skins', node['skin']) if 'skin' in node else None
        skinned_meshes += skin is not None
        mesh = glb.item('meshes', node['mesh'])
        require(mesh.get('primitives'), 'Empty mesh')
        for primitive in mesh['primitives']:
            require(primitive.get('mode', 4) == 4, 'Triangulate meshes')
            glb.item('materials', primitive.get('material'))
            attributes = primitive.get('attributes', {})
            require({'POSITION', 'NORMAL', 'TEXCOORD_0'} <= attributes.keys(),
                    'Mesh needs positions, normals and UVs')
            positions = glb.accessor(attributes['POSITION'])
            normals = glb.accessor(attributes['NORMAL'])
            require(all(len(p) == 3 for p in positions) and len(positions) == len(normals),
                    'Invalid position/normal layout')
            require(all(0.9 < sum(x*x for x in row) < 1.1 for row in normals),
                    'Non-unit or zero normals')
            require(len(glb.accessor(attributes['TEXCOORD_0'])) == len(positions), 'UV count mismatch')
            indices = ([x[0] for x in glb.accessor(primitive['indices'])]
                       if 'indices' in primitive else list(range(len(positions))))
            require(len(indices) % 3 == 0 and all(type(i) is int and 0 <= i < len(positions) for i in indices),
                    'Invalid triangle indices')
            triangles += len(indices) // 3
            for i in range(0, len(indices), 3):
                a, b, c = [positions[j] for j in indices[i:i+3]]
                u, v = [b[j]-a[j] for j in range(3)], [c[j]-a[j] for j in range(3)]
                cross = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
                require(sum(x*x for x in cross) > 1e-20, 'Degenerate triangle')
            if skin:
                require({'JOINTS_0', 'WEIGHTS_0'} <= attributes.keys(), 'Unweighted skinned mesh')
                joints, weights = glb.accessor(attributes['JOINTS_0']), glb.accessor(attributes['WEIGHTS_0'])
                require(len(joints) == len(weights) == len(positions), 'Skin accessor count mismatch')
                require(all(len(row) == 4 and all(type(j) is int and 0 <= j < len(skin['joints']) for j in row)
                            for row in joints), 'Invalid joint index')
                require(all(len(row) == 4 and all(0 <= w <= 1 for w in row) and
                            abs(sum(row)-1) < 0.02 for row in weights), 'Unnormalized or zero skin weights')
    require(skinned_meshes > 0 and 0 < triangles <= CONTRACT['max_triangles'],
            'No skinned geometry or triangle budget exceeded')

    animations, fingerprints, clips = doc.get('animations', []), set(), {}
    require(len(animations) == len(CONTRACT['animations']), 'Expected exactly eight clips')
    for animation in animations:
        name = animation.get('name')
        require(name in CONTRACT['animations'] and name not in clips, 'Invalid or duplicated clip name')
        samplers, channels = animation.get('samplers', []), animation.get('channels', [])
        require(channels and samplers, f'{name}: empty animation')
        signature, duration, moving, targets = [], 0, False, set()
        for channel in channels:
            target = channel['target']
            require(target.get('node') in reachable, f'{name}: target outside default scene')
            path = target.get('path')
            require(path in ('translation', 'rotation', 'scale', 'weights'), f'{name}: unsupported target')
            key = (target['node'], path)
            require(key not in targets, f'{name}: duplicated target channel')
            targets.add(key)
            index = channel.get('sampler')
            require(type(index) is int and 0 <= index < len(samplers), f'{name}: invalid sampler')
            sampler = samplers[index]
            time_accessor = glb.item('accessors', sampler.get('input'))
            require(time_accessor['type'] == 'SCALAR' and time_accessor['componentType'] == 5126,
                    f'{name}: keyframe times must be float scalars')
            times = [row[0] for row in glb.accessor(sampler['input'])]
            require(len(times) >= 2 and times[0] == 0 and all(a < b for a, b in zip(times, times[1:])),
                    f'{name}: times must start at zero and increase')
            values = glb.accessor(sampler.get('output'))
            interpolation = sampler.get('interpolation', 'LINEAR')
            require(interpolation in ('LINEAR', 'STEP', 'CUBICSPLINE'), f'{name}: invalid interpolation')
            multiplier = 3 if interpolation == 'CUBICSPLINE' else 1
            if path != 'weights':
                require(len(values) == len(times)*multiplier and
                        all(len(row) == (4 if path == 'rotation' else 3) for row in values),
                        f'{name}: invalid channel output layout')
                samples = values[1::3] if multiplier == 3 else values
                moving |= any(row != samples[0] for row in samples[1:])
            else:
                require(len(values) % (len(times)*multiplier) == 0, f'{name}: invalid morph output')
                width = len(values) // len(times)
                moving |= any(values[i:i+width] != values[:width] for i in range(width, len(values), width))
            duration = max(duration, times[-1])
            signature.append((target['node'], path, interpolation, times, values))
        require(moving and duration > 0, f'{name}: static animation')
        fingerprint = hashlib.sha256(json.dumps(sorted(signature)).encode()).hexdigest()
        require(fingerprint not in fingerprints, f'{name}: duplicates another animation')
        fingerprints.add(fingerprint)
        clips[name] = duration
    return {'structural_pass': True, 'sha256': hashlib.sha256(raw).hexdigest(),
            'bytes': len(raw), 'triangles': triangles, 'skin_count': len(skins),
            'joint_count': len(joint_names), 'textures': dimensions,
            'estimated_texture_bytes_with_mips': texture_bytes, 'clips_seconds': clips,
            'pending': ['Full Khronos glTF validation', 'Texture decode and visual inspection',
                        'Golden-eagle anatomy and feather realism', 'Independent clip playback',
                        'Android rendering, memory and frame timing']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('glb', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    try:
        report = validate(args.glb)
    except (OSError, ValueError, KeyError, TypeError, IndexError, struct.error) as error:
        report = {'structural_pass': False, 'error': str(error)}
    output = json.dumps(report, indent=2)
    print(output)
    if args.report:
        with args.report.open('x') as handle:
            handle.write(output + '\n')
    return 0 if report['structural_pass'] else 1


if __name__ == '__main__':
    sys.exit(main())
