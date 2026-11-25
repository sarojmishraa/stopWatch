import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'features/dashboard/presentation/dashboard_screen.dart';
import 'features/learning/presentation/learning_dashboard_screen.dart';
import 'features/study/presentation/study_screen.dart';

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
  ],
);

class EagleStudyApp extends StatelessWidget {
  const EagleStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EAGLE STUDY',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
