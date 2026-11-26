// Standalone renderer diagnostic; this cube is not an eagle substitute.
// flutter run -t lib/eagle_scene_probe.dart --enable-flutter-gpu
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() => runApp(const MaterialApp(home: EagleSceneProbe()));

class EagleSceneProbe extends StatefulWidget {
  const EagleSceneProbe({super.key});

  @override
  State<EagleSceneProbe> createState() => _EagleSceneProbeState();
}

class _EagleSceneProbeState extends State<EagleSceneProbe> {
  Scene? _scene;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await Scene.initializeStaticResources();
      if (!mounted) return;
      final scene = Scene();
      _scene = scene;
      scene.add(
        Node(
          mesh: Mesh(
            CuboidGeometry(vm.Vector3(1, 1, 1)),
            PhysicallyBasedMaterial(),
          ),
        ),
      );
      setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _scene?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Flutter Scene rendering probe')),
    body: _error != null
        ? Center(child: Text('Renderer failed: $_error'))
        : _scene == null
        ? const Center(child: CircularProgressIndicator())
        : SceneView(
            _scene!,
            camera: PerspectiveCamera(position: vm.Vector3(2, 2, -4)),
            maxFrameRate: 60,
            errorBuilder: (_, error, _) => Text('Renderer failed: $error'),
          ),
  );
}
