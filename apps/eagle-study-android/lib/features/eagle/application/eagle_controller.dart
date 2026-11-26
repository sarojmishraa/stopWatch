import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../timer/application/study_timer_controller.dart';
import '../../timer/domain/study_timer_state.dart';

/// What the eagle is doing. Names match EagleMotion.parse in Kotlin.
enum EagleMood { idle, focus, rest, celebrate }

/// Bundled model (see assets/models/CREDITS.md for its licence).
const eagleModelAsset = 'assets/models/eagle.glb';

EagleMood moodFor(StudyTimerState timer) {
  if (timer.isRunning) return EagleMood.focus;
  if (timer.hasSession) return EagleMood.rest;
  return EagleMood.idle;
}

final eagleMoodProvider = NotifierProvider<EagleMoodController, EagleMood>(
  EagleMoodController.new,
);

/// Follows the study session; celebrates briefly when one is saved.
class EagleMoodController extends Notifier<EagleMood> {
  static const celebrationLength = Duration(seconds: 4);
  Timer? _celebration;

  @override
  EagleMood build() {
    ref.onDispose(() => _celebration?.cancel());
    ref.listen(studyTimerProvider, (previous, next) {
      final saved = next.lastSaved;
      if (saved != null && !identical(saved, previous?.lastSaved)) {
        _celebrate();
      } else if (_celebration == null) {
        state = moodFor(next);
      }
    });
    return moodFor(ref.read(studyTimerProvider));
  }

  void _celebrate() {
    _celebration?.cancel();
    state = EagleMood.celebrate;
    _celebration = Timer(celebrationLength, () {
      _celebration = null;
      state = moodFor(ref.read(studyTimerProvider));
    });
  }
}

/// Whether to render the 3D eagle: OpenGL ES 3.0, not a low-RAM phone, and
/// the model file is bundled. Otherwise the 2D eagle is shown.
final eagle3dAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    if (!manifest.listAssets().contains(eagleModelAsset)) return false;
    return await const MethodChannel('eagle_study/eagle')
            .invokeMethod<bool>('isSupported') ??
        false;
  } catch (error) {
    debugPrint('3D eagle unavailable: $error');
    return false;
  }
});
