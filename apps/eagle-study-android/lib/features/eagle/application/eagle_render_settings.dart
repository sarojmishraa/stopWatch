import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/providers.dart';

const eagleMascotAsset = 'assets/3d/eagle_mascot.glb';

final eagleRenderEnabledProvider =
    AsyncNotifierProvider<EagleRenderSettings, bool>(EagleRenderSettings.new);

class EagleRenderSettings extends AsyncNotifier<bool> {
  static const _key = 'eagle_3d_enabled';
  Future<void> _writes = Future.value();

  @override
  Future<bool> build() async {
    final db = await ref.read(studyDatabaseProvider).database;
    final rows = await db.query(
      'app_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_key],
      limit: 1,
    );
    return rows.isEmpty || rows.single['value'] != 'false';
  }

  /// Serialize writes so rapid toggles cannot persist in the wrong order.
  Future<void> setEnabled(bool enabled) {
    final operation = _writes.then((_) async {
      final db = await ref.read(studyDatabaseProvider).database;
      await db.insert('app_state', {
        'key': _key,
        'value': '$enabled',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (ref.mounted) state = AsyncData(enabled);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}

final eagleRenderCapabilityProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    if (!manifest.listAssets().contains(eagleMascotAsset)) return false;
    // Reuse the existing native low-RAM/GLES check as a conservative gate.
    // Actual Flutter GPU initialization is attempted and caught by the view.
    return await const MethodChannel('eagle_study/eagle')
            .invokeMethod<bool>('isSupported') ??
        false;
  } catch (error) {
    debugPrint('Eagle capability check failed: $error');
    return false;
  }
});
