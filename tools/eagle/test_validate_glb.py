"""Small synthetic parser fixtures only. These are not eagle artwork."""
import copy
import json
import math
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

from validate_glb import CONTRACT, validate


def fixture():
    binary = bytearray()
    doc = {'asset': {'version': '2.0'}, 'bufferViews': [], 'accessors': []}
    def view(data):
        while len(binary) % 4:
            binary.append(0)
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(data)})
        binary.extend(data)
        return len(doc['bufferViews'])-1
    def acc(values, kind='VEC3', code='f', component=5126):
        raw = struct.pack('<' + code*sum(map(len, values)), *[v for row in values for v in row])
        doc['accessors'].append({'bufferView': view(raw), 'componentType': component,
                                 'count': len(values), 'type': kind})
        return len(doc['accessors'])-1
    positions = acc([(0, 0, 0), (1, 0, 0), (0, 1, 0)])
    normals = acc([(0, 0, 1)]*3)
    uv = acc([(0, 0), (1, 0), (0, 1)], 'VEC2')
    joints = acc([(0, 0, 0, 0)]*3, 'VEC4', 'H', 5123)
    weights = acc([(1, 0, 0, 0)]*3, 'VEC4')
    inverse = acc([(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)]*len(CONTRACT['bones']), 'MAT4')
    def png_chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind+data))
    png = b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0))
    png += png_chunk(b'IDAT', zlib.compress(b'\x00\xff\xff\xff\xff')) + png_chunk(b'IEND', b'')
    doc['images'] = [{'bufferView': view(png), 'mimeType': 'image/png'}]
    doc['textures'] = [{'source': 0}]
    doc['materials'] = [{'pbrMetallicRoughness': {'baseColorTexture': {'index': 0},
                          'metallicRoughnessTexture': {'index': 0}}, 'normalTexture': {'index': 0}}]
    doc['nodes'] = [{'name': name} for name in CONTRACT['bones']]
    doc['nodes'][0]['children'] = list(range(1, len(doc['nodes'])))
    doc['nodes'].append({'name': 'FixtureMesh', 'mesh': 0, 'skin': 0})
    doc['skins'] = [{'joints': list(range(len(CONTRACT['bones']))), 'inverseBindMatrices': inverse}]
    doc['meshes'] = [{'primitives': [{'attributes': {'POSITION': positions, 'NORMAL': normals,
                      'TEXCOORD_0': uv, 'JOINTS_0': joints, 'WEIGHTS_0': weights}, 'material': 0}]}]
    doc['scenes'] = [{'nodes': [0, len(doc['nodes'])-1]}]
    doc['scene'] = 0
    times = acc([(0,), (1,)], 'SCALAR')
    doc['animations'] = []
    for i, name in enumerate(CONTRACT['animations']):
        angle = (i+1)*0.1
        output = acc([(0, 0, 0, 1), (0, math.sin(angle), 0, math.cos(angle))], 'VEC4')
        doc['animations'].append({'name': name, 'samplers': [{'input': times, 'output': output}],
                                  'channels': [{'sampler': 0, 'target': {'node': 0, 'path': 'rotation'}}]})
    doc['buffers'] = [{'byteLength': len(binary)}]
    return doc, binary


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'fixture.glb'
        self.doc, self.binary = fixture()

    def write(self):
        raw = json.dumps(self.doc).encode()
        raw += b' ' * (-len(raw) % 4)
        binary = self.binary + b'\x00' * (-len(self.binary) % 4)
        total = 12+8+len(raw)+8+len(binary)
        self.path.write_bytes(struct.pack('<4sII', b'glTF', 2, total) +
                              struct.pack('<II', len(raw), 0x4E4F534A) + raw +
                              struct.pack('<II', len(binary), 0x004E4942) + binary)

    def reject(self, message):
        self.write()
        with self.assertRaisesRegex(ValueError, message):
            validate(self.path)

    def test_valid_fixture_passes_structure_but_keeps_visual_and_device_qa_pending(self):
        self.write()
        result = validate(self.path)
        self.assertTrue(result['structural_pass'])
        self.assertEqual(8, len(result['clips_seconds']))
        self.assertEqual(1, result['triangles'])
        self.assertIn('Android rendering, memory and frame timing', result['pending'])

    def test_renamed_copy_does_not_count_as_distinct_animation(self):
        self.doc['animations'][1] = copy.deepcopy(self.doc['animations'][0])
        self.doc['animations'][1]['name'] = 'Study_Start'
        self.reject('duplicates another animation')

    def test_missing_bone(self):
        self.doc['nodes'][1]['name'] = 'wrong'
        self.reject('Missing rig bones')

    def test_external_texture(self):
        self.doc['images'][0]['uri'] = '../missing.png'
        self.reject('embedded buffer views')

    def test_bad_material_reference(self):
        self.doc['meshes'][0]['primitives'][0]['material'] = 9
        self.reject('Invalid materials index')

    def test_invalid_accessor_bounds(self):
        self.doc['accessors'][0]['count'] = 999999
        self.reject('Accessor outside buffer view')

    def test_cycle(self):
        self.doc['nodes'][1]['children'] = [0]
        self.reject('Cyclic node hierarchy')

    def test_clip_missing(self):
        self.doc['animations'].pop()
        self.reject('exactly eight clips')

    def test_unverified_compression(self):
        self.doc['extensionsUsed'] = ['KHR_draco_mesh_compression']
        self.reject('Compression is disabled')

    def test_bad_header(self):
        self.path.write_bytes(b'glTF')
        with self.assertRaisesRegex(ValueError, 'Truncated'):
            validate(self.path)

    def test_truncated_bin(self):
        self.write()
        self.path.write_bytes(self.path.read_bytes()[:-4])
        with self.assertRaisesRegex(ValueError, 'declared length'):
            validate(self.path)

    def test_zero_weight_vertex(self):
        index = self.doc['meshes'][0]['primitives'][0]['attributes']['WEIGHTS_0']
        view = self.doc['bufferViews'][self.doc['accessors'][index]['bufferView']]
        struct.pack_into('<4f', self.binary, view['byteOffset'], 0, 0, 0, 0)
        self.reject('zero skin weights')

    def test_static_animation(self):
        index = self.doc['animations'][0]['samplers'][0]['output']
        view = self.doc['bufferViews'][self.doc['accessors'][index]['bufferView']]
        struct.pack_into('<4f', self.binary, view['byteOffset']+16, 0, 0, 0, 1)
        self.reject('static animation')


if __name__ == '__main__':
    unittest.main()
