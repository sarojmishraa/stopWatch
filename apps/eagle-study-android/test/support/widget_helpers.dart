import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 390×844 pt phone, like the devices the app targets.
void usePhoneScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Lets real SQLite I/O (which runs outside the fake-async test zone)
/// complete, then rebuilds. Avoids pumpAndSettle, which never settles while
/// the one-second clock ticker is active.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump();
  }
}

/// Unmounts the tree so providers (and their timers) are disposed.
Future<void> disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester);
}
