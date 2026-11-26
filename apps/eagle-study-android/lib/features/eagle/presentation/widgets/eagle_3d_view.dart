import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_scene/scene.dart' as scene;
import 'package:vector_math/vector_math.dart' as vm;

import '../../application/eagle_animation_controller.dart';
import '../../application/eagle_animation_state.dart';
import '../../application/eagle_render_settings.dart';
import '../../data/eagle_asset_credits.dart';
import '../../domain/eagle_animation_type.dart';

/// A decorative golden eagle above the timer. Missing assets, unsupported
/// devices, reduced motion and renderer failures all use the static fallback.
class Eagle3DView extends ConsumerStatefulWidget {
  const Eagle3DView({this.size = 200, super.key});
  final double size;

  @override
  ConsumerState<Eagle3DView> createState() => _Eagle3DViewState();
}

class _Eagle3DViewState extends ConsumerState<Eagle3DView> {
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    registerGoldenEagleCredits();
    final initial = WidgetsBinding.instance.lifecycleState;
    _foreground = initial == null || initial == AppLifecycleState.resumed;
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (mounted) {
          setState(() => _foreground = state == AppLifecycleState.resumed);
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onError(Object error) {
    debugPrint('Golden eagle renderer unavailable: $error');
    // Renderer errors can arrive during paint. Remove it after that frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  Future<void> _toggle(bool enabled) async {
    try {
      await ref.read(eagleRenderEnabledProvider.notifier).setEnabled(enabled);
      if (mounted && enabled) setState(() => _failed = false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the eagle preference.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final animation = ref.watch(eagleAnimationProvider);
    final enabled = ref.watch(eagleRenderEnabledProvider);
    final capable = ref.watch(eagleRenderCapabilityProvider).value ?? false;
    final render =
        enabled.value == true &&
        capable &&
        !_failed &&
        _foreground &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Eagle Study',
          image: true,
          child: SizedBox.square(
            dimension: widget.size,
            child: render
                ? _EagleScene(
                    state: animation,
                    onCompleted: ref
                        .read(eagleAnimationProvider.notifier)
                        .completed,
                    onError: _onError,
                  )
                : const EagleFallback(),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('3D eagle'),
            const SizedBox(width: 8),
            Switch(
              value: enabled.value ?? false,
              onChanged: enabled.hasValue ? _toggle : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// Quiet, zero-ticker fallback. It makes no claim to be the finished artwork.
class EagleFallback extends StatelessWidget {
  const EagleFallback({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      Icons.landscape_outlined,
      size: 64,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class _EagleScene extends StatefulWidget {
  const _EagleScene({
    required this.state,
    required this.onCompleted,
    required this.onError,
  });
  final EagleAnimationState state;
  final ValueChanged<int> onCompleted;
  final ValueChanged<Object> onError;

  @override
  State<_EagleScene> createState() => _EagleSceneState();
}

class _EagleSceneState extends State<_EagleScene> {
  static const _blendSeconds = 0.25;
  _GuardedScene? _scene;
  final _clips = <EagleAnimationType, scene.AnimationClip>{};
  final _durations = <EagleAnimationType, double>{};
  final _blendFrom = <EagleAnimationType, double>{};
  bool _hasAssetClaim = false;
  double _blendTime = _blendSeconds;
  int? _completionReported;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await scene.Scene.initializeStaticResources().timeout(
        const Duration(seconds: 30),
      );
      if (!mounted) return;
      final model = await scene.loadScene(eagleMascotAsset);
      // A load that finishes after disposal still owns a cache claim.
      if (!mounted) {
        await scene.releaseScene(eagleMascotAsset);
        return;
      }
      _hasAssetClaim = true;
      for (final type in EagleAnimationType.values) {
        final animation = model.findAnimationByName(type.clipName);
        if (animation == null ||
            animation.endTime <= 0 ||
            !animation.endTime.isFinite ||
            animation.channels.isEmpty) {
          throw FormatException('Missing or empty clip: ${type.clipName}');
        }
        _durations[type] = animation.endTime;
        _clips[type] = model.createAnimationClip(animation)..weight = 0;
      }
      final world = _GuardedScene(_fail);
      _scene = world;
      world.renderQuality
        ..tier = scene.RenderQualityTier.medium
        ..adaptive = true
        ..targetFrameRate = 60;
      world.add(model);
      _play(first: true);
      world.update(0);
      setState(() {});
    } catch (error) {
      if (mounted) _fail(error);
    }
  }

  void _fail(Object error) {
    if (_error != null) return;
    _error = error;
    widget.onError(error);
    // Handles asynchronous load errors as well as errors raised during paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didUpdateWidget(covariant _EagleScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.requestId != widget.state.requestId) _play();
  }

  void _play({bool first = false}) {
    if (_clips.isEmpty) return;
    _completionReported = null;
    _blendTime = first ? _blendSeconds : 0;
    for (final entry in _clips.entries) {
      _blendFrom[entry.key] = first ? 0 : entry.value.weight;
    }
    final clip = _clips[widget.state.animation]!;
    clip.loop = widget.state.loop;
    clip.replay();
    if (first) clip.weight = 1;
  }

  void _tick(Duration elapsed, double delta) {
    if (_error != null || _scene == null) return;
    try {
      // Explicit updates prevent wall-clock time in the background jumping
      // an animation to its end. Long stalls advance at most 100 ms.
      final dt = delta.clamp(0.0, 0.1);
      _blendTime = math.min(_blendTime + dt, _blendSeconds);
      final blend = _blendTime / _blendSeconds;
      for (final entry in _clips.entries) {
        final target = entry.key == widget.state.animation ? 1.0 : 0.0;
        final from = _blendFrom[entry.key] ?? 0;
        entry.value.weight = from + (target - from) * blend;
        if (target == 0 && blend == 1) entry.value.stop();
      }
      _scene!.update(dt);
      final clip = _clips[widget.state.animation]!;
      if (!widget.state.loop &&
          clip.playbackTime >= _durations[widget.state.animation]! &&
          _completionReported != widget.state.requestId) {
        final id = widget.state.requestId;
        _completionReported = id;
        scheduleMicrotask(() {
          if (mounted) widget.onCompleted(id);
        });
      }
    } catch (error) {
      _fail(error);
    }
  }

  @override
  void dispose() {
    for (final clip in _clips.values) {
      clip.stop();
    }
    _clips.clear();
    _scene?.removeAll();
    _scene?.dispose();
    _scene = null;
    if (_hasAssetClaim) {
      unawaited(
        scene.releaseScene(eagleMascotAsset).catchError((Object error) {
          debugPrint('Eagle cache release failed: $error');
          return false;
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return const EagleFallback();
    if (_scene == null) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading eagle'),
      );
    }
    return scene.SceneView(
      _scene!,
      // Asset contract: metres, feet at ground, +Y up and forward +Z in glTF.
      camera: scene.PerspectiveCamera(
        position: vm.Vector3(0, 0.75, -3.4),
        target: vm.Vector3(0, 0.5, 0),
      ),
      maxFrameRate: 60,
      pixelRatio: math.min(MediaQuery.devicePixelRatioOf(context), 2),
      onTick: _tick,
      loadingBuilder: (_, _) => const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading eagle'),
      ),
      errorBuilder: (_, error, _) {
        _fail(error);
        return const EagleFallback();
      },
    );
  }
}

/// SceneView's errorBuilder handles initialization failures. Frame-time GPU
/// errors also need containment, without replacing Flutter's global handler.
final class _GuardedScene extends scene.Scene {
  _GuardedScene(this.onError);
  final ValueChanged<Object> onError;
  bool failed = false;

  @override
  void render(
    scene.Camera camera,
    Canvas canvas, {
    Rect? viewport,
    double? pixelRatio,
  }) {
    if (failed) return;
    try {
      super.render(camera, canvas, viewport: viewport, pixelRatio: pixelRatio);
    } catch (error) {
      failed = true;
      onError(error);
    }
  }
}
