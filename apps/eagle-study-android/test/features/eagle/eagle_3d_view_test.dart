import 'package:eagle_study/features/eagle/application/eagle_render_settings.dart';
import 'package:eagle_study/features/eagle/presentation/widgets/eagle_3d_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';
import '../../support/widget_helpers.dart';

void main() {
  testWidgets('missing asset has a quiet fallback and a working saved toggle', (
    tester,
  ) async {
    final env = (await tester.runAsync(TestEnv.create))!;
    usePhoneScreen(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          eagleRenderCapabilityProvider.overrideWith((_) async => false),
        ],
        child: const MaterialApp(home: Scaffold(body: Eagle3DView())),
      ),
    );
    await settle(tester);
    expect(find.byType(EagleFallback), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    final rows = (await tester.runAsync(() async {
      final saved = await env.database.database;
      return saved.query(
        'app_state',
        where: 'key = ?',
        whereArgs: ['eagle_3d_enabled'],
      );
    }))!;
    expect(rows.single['value'], 'false');
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });

  testWidgets('reduced motion never initializes GPU even on a capable device', (
    tester,
  ) async {
    final env = (await tester.runAsync(TestEnv.create))!;
    usePhoneScreen(tester); // turns on the accessibility reduced-motion flag
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          eagleRenderCapabilityProvider.overrideWith((_) async => true),
        ],
        child: const MaterialApp(home: Scaffold(body: Eagle3DView())),
      ),
    );
    await settle(tester);
    expect(find.byType(EagleFallback), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeTree(tester);
  });
}
