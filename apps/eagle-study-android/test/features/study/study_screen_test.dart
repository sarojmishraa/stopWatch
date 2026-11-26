import 'package:eagle_study/features/study/application/study_mode_controller.dart';
import 'package:eagle_study/features/study/domain/study_mode_prefs.dart';
import 'package:eagle_study/features/study/presentation/study_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_env.dart';
import '../../support/widget_helpers.dart';

void main() {
  testWidgets('opening Study Mode applies DND and keep-awake; leaving '
      'restores them', (tester) async {
    usePhoneScreen(tester);
    final env = (await tester.runAsync(TestEnv.create))!;
    env.studyMode.access = true;
    final container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await container.read(studyModePrefsProvider.future);
      await container
          .read(studyModePrefsProvider.notifier)
          .save(const StudyModePrefs(dnd: DndMode.alarms));
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const StudyScreen()),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('OPEN'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('STUDY MODE'), findsOneWidget);
    expect(
      find.text('Do Not Disturb on · restored when you leave'),
      findsOneWidget,
    );
    expect(find.text('START STUDY'), findsOneWidget);
    expect(find.textContaining(' of 6h 00m'), findsOneWidget); // today's goal
    expect(env.studyMode.dndOn, isTrue);
    expect(env.studyMode.keepScreenOn, isTrue);

    await tester.tap(find.byTooltip('Study Mode settings'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Alarms only'), findsOneWidget);
    expect(find.textContaining('Total silence'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20)); // close the sheet
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byTooltip('Leave Study Mode'));
    await settle(tester);
    // Exit runs after the pop animation (up to ~800 ms) disposes the screen.
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('STUDY MODE'), findsNothing);
    expect(env.studyMode.dndOn, isFalse);
    expect(env.studyMode.keepScreenOn, isFalse);
    await disposeTree(tester);
  });
}
