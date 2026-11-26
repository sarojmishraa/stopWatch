import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/eagle_controller.dart';

/// The eagle mascot. Renders the 3D model natively (Filament) when the
/// device supports it, otherwise an animated 2D eagle. Tap to make it react.
class EagleView extends ConsumerStatefulWidget {
  const EagleView({this.size = 200, super.key});

  final double size;

  @override
  ConsumerState<EagleView> createState() => _EagleViewState();
}

class _EagleViewState extends ConsumerState<EagleView> {
  MethodChannel? _channel;
  bool _failed = false;
  int _pokes = 0;

  void _onCreated(int id) {
    final channel = MethodChannel('eagle_study/eagle_view_$id');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'error') {
        debugPrint('3D eagle failed to load: ${call.arguments}');
        if (mounted) setState(() => _failed = true);
      }
    });
    _channel = channel;
    _send('setMood', ref.read(eagleMoodProvider).name);
  }

  void _send(String method, [Object? argument]) {
    _channel?.invokeMethod(method, argument).catchError((Object e) {
      debugPrint('Eagle view call failed: $e');
    });
  }

  void _poke() {
    HapticFeedback.selectionClick();
    setState(() => _pokes++);
    _send('poke');
  }

  @override
  Widget build(BuildContext context) {
    final mood = ref.watch(eagleMoodProvider);
    ref.listen(eagleMoodProvider, (_, next) => _send('setMood', next.name));
    final use3d =
        !_failed && (ref.watch(eagle3dAvailableProvider).value ?? false);

    return Semantics(
      label: 'Eagle mascot, ${_moodLabel(mood)}. Double tap to make it react.',
      button: true,
      child: GestureDetector(
        onTap: _poke,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          dimension: widget.size,
          child: use3d
              ? AndroidView(
                  viewType: 'eagle_study/eagle_view',
                  creationParams: {
                    'asset': eagleModelAsset,
                    'mood': mood.name,
                    'baseYawDeg': 0.0,
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: _onCreated,
                  // Taps are handled by the GestureDetector above.
                  gestureRecognizers:
                      const <Factory<OneSequenceGestureRecognizer>>{},
                )
              : _FlatEagle(mood: mood, pokes: _pokes, size: widget.size),
        ),
      ),
    );
  }
}

String _moodLabel(EagleMood mood) => switch (mood) {
  EagleMood.idle => 'gliding',
  EagleMood.focus => 'flying with you',
  EagleMood.rest => 'resting',
  EagleMood.celebrate => 'celebrating',
};

/// 2D fallback for devices without OpenGL ES 3.0 or without the model.
class _FlatEagle extends StatefulWidget {
  const _FlatEagle({
    required this.mood,
    required this.pokes,
    required this.size,
  });

  final EagleMood mood;
  final int pokes;
  final double size;

  @override
  State<_FlatEagle> createState() => _FlatEagleState();
}

class _FlatEagleState extends State<_FlatEagle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect Android's "Remove animations" accessibility setting.
    if (MediaQuery.disableAnimationsOf(context)) {
      _bob.stop();
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (icon, lift, turns) = switch (widget.mood) {
      EagleMood.focus => (Icons.flight_takeoff_rounded, -0.06, 0.0),
      EagleMood.rest => (Icons.air_rounded, 0.06, 0.0),
      EagleMood.celebrate => (Icons.flight_rounded, -0.12, 1.0),
      EagleMood.idle => (Icons.flight_rounded, 0.0, 0.0),
    };
    return AnimatedBuilder(
      animation: _bob,
      builder: (context, child) => Transform.translate(
        offset: Offset(
          0,
          widget.size * (lift + 0.02 * math.sin(_bob.value * math.pi)),
        ),
        child: child,
      ),
      child: AnimatedRotation(
        turns: turns + widget.pokes * 0.05,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutBack,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.cyan.withValues(alpha: 0.3),
                AppColors.cyan.withValues(alpha: 0.02),
              ],
            ),
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.32)),
          ),
          child: Icon(icon, size: widget.size * 0.4, color: AppColors.cyan),
        ),
      ),
    );
  }
}
