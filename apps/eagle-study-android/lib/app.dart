import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/learning/presentation/learning_dashboard_screen.dart';
import 'features/sessions/presentation/history_screen.dart';
import 'features/study/presentation/study_screen.dart';
import 'features/timer/application/study_timer_controller.dart';

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LearningDashboardScreen(),
    ),
    GoRoute(
      path: '/timer',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(path: '/study', builder: (context, state) => const StudyScreen()),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryScreen(),
    ),
  ],
);

class EagleStudyApp extends ConsumerStatefulWidget {
  const EagleStudyApp({super.key});

  @override
  ConsumerState<EagleStudyApp> createState() => _EagleStudyAppState();
}

class _EagleStudyAppState extends ConsumerState<EagleStudyApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        // A countdown may have ended, or the day changed, while suspended.
        ref.read(studyTimerProvider.notifier).checkCountdown();
        ref.invalidate(studySummaryProvider);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the timer alive app-wide so a countdown completes on any screen.
    ref.watch(studyTimerProvider);
    return MaterialApp.router(
      title: 'EAGLE STUDY',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
