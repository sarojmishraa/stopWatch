import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/time/study_calendar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeTimeZones();
  runApp(const ProviderScope(child: EagleStudyApp()));
}
