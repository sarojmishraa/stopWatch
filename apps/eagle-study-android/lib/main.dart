import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/credits.dart';
import 'core/time/study_calendar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeTimeZones();
  registerAssetCredits();
  runApp(const ProviderScope(child: EagleStudyApp()));
}
