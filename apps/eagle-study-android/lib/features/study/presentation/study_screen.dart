import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../eagle/presentation/eagle_view.dart';
import '../../sessions/domain/study_session.dart';
import '../../sessions/presentation/session_format.dart';
import '../../timer/application/study_timer_controller.dart';
import '../../timer/domain/study_timer_state.dart';
import '../application/study_mode_controller.dart';
import 'study_mode_settings_sheet.dart';

/// Study Mode: distraction-free full screen. While it is open the user's
/// screen-awake and Do Not Disturb choices apply; closing restores them.
class StudyScreen extends ConsumerStatefulWidget {
  const StudyScreen({super.key});

  @override
  ConsumerState<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends ConsumerState<StudyScreen> {
  late final StudyModeController _studyMode;

  @override
  void initState() {
    super.initState();
    _studyMode = ref.read(studyModeProvider.notifier);
    // Providers must not change while widgets build/dispose: run afterwards.
    Future.microtask(_studyMode.enter);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // ref is unusable here; the notifier was captured in initState.
    Future.microtask(_studyMode.exit);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _finish() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await ref.read(studyTimerProvider.notifier).finish();
      if (outcome == FinishOutcome.tooShort) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Under a second: nothing to save.')),
        );
      }
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't save the session: $error")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(secondTickerProvider);
    final timer = ref.watch(studyTimerProvider);
    final mode = ref.watch(studyModeProvider);
    final summary = ref.watch(studySummaryProvider).value ?? StudySummary.empty;
    final controller = ref.read(studyTimerProvider.notifier);
    final now = ref.read(clockProvider)().millisecondsSinceEpoch;
    final seconds = timer.secondsAt(now);
    final focused = timer.focusedSecondsAt(now);
    final isCountdown = timer.mode == TimerMode.countdown;
    final dailyTarget = summary.dailyTargetMinutes * 60;
    final todayWithCurrent =
        summary.todaySeconds + (timer.hasSession ? focused : 0);

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
                            tooltip: 'Leave Study Mode',
                            onPressed: () => Navigator.of(context).maybePop(),
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
                          IconButton(
                            tooltip: 'Study Mode settings',
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: AppColors.surface,
                              builder: (_) => const StudyModeSettingsSheet(),
                            ),
                            icon: const Icon(Icons.tune_rounded),
                            color: AppColors.text,
                          ),
                        ],
                      ),
                      if (mode.dndApplied)
                        const _StatusChip(
                          icon: Icons.do_not_disturb_on_rounded,
                          text: 'Do Not Disturb on · restored when you leave',
                        ),
                      if (mode.notice != null)
                        _StatusChip(
                          icon: Icons.info_outline_rounded,
                          text: mode.notice!,
                        ),
                      const Spacer(),
                      const EagleView(size: 200),
                      const SizedBox(height: 22),
                      Text(
                        timer.isRunning
                            ? 'You’re in the zone'
                            : timer.hasSession
                            ? 'Paused'
                            : 'Ready to focus?',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [
                          isCountdown ? 'FOCUS SESSION' : 'STOPWATCH SESSION',
                          ?timer.subject?.toUpperCase(),
                        ].join(' · '),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 14),
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
                      Text(
                        isCountdown
                            ? 'REMAINING · ${formatDuration(focused)} FOCUSED'
                            : 'FOCUSED',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                          letterSpacing: 1.5,
                        ),
                      ),
                      if (isCountdown) ...[
                        const SizedBox(height: 12),
                        _Bar(
                          value: timer.countdownDurationSeconds == 0
                              ? 0
                              : focused / timer.countdownDurationSeconds,
                          color: AppColors.lime,
                        ),
                      ],
                      const Spacer(),
                      _TodayProgress(
                        seconds: todayWithCurrent,
                        targetSeconds: dailyTarget,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: timer.hasSession ? _finish : null,
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
                                timer.isRunning
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                              label: Text(
                                timer.isRunning
                                    ? 'PAUSE'
                                    : timer.hasSession
                                    ? 'RESUME'
                                    : 'START STUDY',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: timer.isRunning
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

class _TodayProgress extends StatelessWidget {
  const _TodayProgress({required this.seconds, required this.targetSeconds});

  final int seconds;
  final int targetSeconds;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Text(
              'TODAY',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            Text(
              '${formatDuration(seconds)} of ${formatDuration(targetSeconds)}',
              style: const TextStyle(color: AppColors.text, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _Bar(
          value: targetSeconds == 0 ? 0 : seconds / targetSeconds,
          color: AppColors.cyan,
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 5,
        backgroundColor: Colors.white.withValues(alpha: 0.1),
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: AppColors.cyan),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
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
