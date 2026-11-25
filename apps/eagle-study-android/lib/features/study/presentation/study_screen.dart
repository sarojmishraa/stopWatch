import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../sessions/presentation/session_format.dart';
import '../../timer/application/study_timer_controller.dart';
import '../../timer/domain/study_timer_state.dart';

class StudyScreen extends ConsumerWidget {
  const StudyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(secondTickerProvider);
    final state = ref.watch(studyTimerProvider);
    final controller = ref.read(studyTimerProvider.notifier);
    final seconds = state.secondsAt(
      ref.read(clockProvider)().millisecondsSinceEpoch,
    );
    final isCountdown = state.mode == TimerMode.countdown;
    final progress = isCountdown && state.countdownDurationSeconds > 0
        ? 1 - seconds / state.countdownDurationSeconds
        : null;

    return Scaffold(
      body: Stack(
        children: [
          const _FocusBackdrop(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: AppColors.text,
                          ),
                          const Spacer(),
                          const Text(
                            'STUDY MODE',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 48),
                        ],
                      ),
                      const Spacer(),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: 176,
                        height: 176,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              AppColors.cyan.withValues(alpha: 0.3),
                              AppColors.cyan.withValues(alpha: 0.02),
                            ],
                          ),
                          border: Border.all(
                            color: AppColors.cyan.withValues(alpha: 0.32),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.cyan.withValues(alpha: 0.15),
                              blurRadius: 40,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          state.isRunning
                              ? Icons.flight_takeoff_rounded
                              : Icons.air_rounded,
                          size: 72,
                          color: AppColors.cyan,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Text(
                        state.isRunning
                            ? 'You’re in the zone'
                            : 'Ready to focus?',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        [
                          isCountdown ? 'FOCUS SESSION' : 'STOPWATCH SESSION',
                          ?state.subject?.toUpperCase(),
                        ].join(' · '),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (progress != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: LinearProgressIndicator(
                              value: progress.clamp(0, 1),
                              minHeight: 5,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.1,
                              ),
                              valueColor: const AlwaysStoppedAnimation(
                                AppColors.lime,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatClock(seconds),
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 72,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 1,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: state.hasSession
                                  ? () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      try {
                                        await controller.finish();
                                        if (context.mounted) context.pop();
                                      } catch (error) {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Couldn't save the session: $error",
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                              icon: const Icon(Icons.stop_rounded),
                              label: const Text('FINISH'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.text,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: controller.startOrResume,
                              icon: Icon(
                                state.isRunning
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                state.isRunning
                                    ? 'PAUSE'
                                    : state.hasSession
                                    ? 'RESUME'
                                    : 'START STUDY',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: state.isRunning
                                    ? AppColors.cyanDeep
                                    : AppColors.pink,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusBackdrop extends StatelessWidget {
  const _FocusBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1,
            colors: [Color(0xFF17445A), AppColors.background],
          ),
        ),
      ),
    );
  }
}
