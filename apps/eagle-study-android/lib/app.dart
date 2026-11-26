import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/alarms/application/alarm_controller.dart';
import 'features/alarms/presentation/alarms_screen.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/learning/presentation/learning_dashboard_screen.dart';
import 'features/sessions/presentation/history_screen.dart';
import 'features/study/application/study_mode_controller.dart';
import 'features/study/presentation/study_screen.dart';
import 'features/sync/application/sync_controller.dart';
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
    GoRoute(path: '/alarms', builder: (context, state) => const AlarmsScreen()),
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
    final actions = ref.read(studyNotificationActionsProvider)
      ..onFinished = () => _router.go('/timer');
    // "Finish" tapped on the notification may have launched the app.
    actions.handlePending();
    // If the app was killed in Study Mode, give back the user's DND setting.
    ref.read(studyModeProvider.notifier).healAfterRestart();
    ref.read(syncControllerProvider.notifier).syncSilently();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        // A countdown may have ended, or the day changed, while suspended.
        ref.read(studyTimerProvider.notifier).checkCountdown();
        ref.invalidate(studySummaryProvider);
        ref.read(syncControllerProvider.notifier).syncSilently();
        // One-time alarms may have rung, and permissions may have changed.
        ref.read(alarmControllerProvider.notifier).refreshFired().ignore();
        ref.invalidate(alarmPermissionsProvider);
        ref.invalidate(dndAccessProvider);
        ref.read(studyNotificationActionsProvider).handlePending();
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
    // Load alarms at launch so the native schedule is re-synced every start.
    ref.watch(alarmControllerProvider);
    // Session notification follows the timer on every screen.
    ref.watch(sessionNotificationSyncProvider);
    return MaterialApp.router(
      title: 'EAGLE STUDY',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
