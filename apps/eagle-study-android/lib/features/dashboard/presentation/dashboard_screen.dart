import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../alarms/application/alarm_controller.dart';
import '../../alarms/presentation/alarm_format.dart';
import '../../auth/application/auth_controller.dart';
import '../../eagle/presentation/widgets/eagle_3d_view.dart';
import '../../sessions/domain/study_session.dart';
import '../../sessions/presentation/session_format.dart';
import '../../sync/application/sync_controller.dart';
import '../../sync/presentation/sync_account_sheet.dart';
import '../../timer/application/study_timer_controller.dart';
import '../../timer/domain/study_timer_state.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(secondTickerProvider);
    final timer = ref.watch(studyTimerProvider);
    final controller = ref.read(studyTimerProvider.notifier);
    final summary = ref.watch(studySummaryProvider).value ?? StudySummary.empty;
    final now = ref.read(clockProvider)().millisecondsSinceEpoch;
    final seconds = timer.secondsAt(now);

    ref.listen(studyTimerProvider.select((s) => s.lastSaved), (previous, next) {
      if (next == null || identical(previous, next)) return;
      final text = next.capped
          ? 'Saved ${formatDuration(next.durationSeconds)}: capped at 24 hours.'
          : 'Session saved: ${formatDuration(next.durationSeconds)}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });

    Future<void> confirmReset() async {
      // Read the clock at tap time, not from the last repaint.
      final focusedNow = ref
          .read(studyTimerProvider)
          .focusedSecondsAt(ref.read(clockProvider)().millisecondsSinceEpoch);
      if (focusedNow >= 60) {
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this session?'),
            content: Text(
              '${formatDuration(focusedNow)} of focus will not be saved. '
              'Use FINISH to keep it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('KEEP GOING'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('DISCARD'),
              ),
            ],
          ),
        );
        if (discard != true) return;
      }
      await controller.reset();
    }

    Future<void> finish() async {
      try {
        final outcome = await controller.finish();
        if (outcome == FinishOutcome.tooShort && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Under a second: nothing to save.')),
          );
        }
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Couldn't save the session: $error")),
        );
      }
    }

    void lap() {
      if (!controller.addLap() && timer.laps.length >= maxLaps) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lap limit reached (500).')),
        );
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          const _AmbientBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth > 600 ? 32.0 : 20.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(horizontal, 14, horizontal, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Header(onFocusTap: () => context.push('/study')),
                          const SizedBox(height: 16),
                          const _UpcomingAlarm(),
                          const SizedBox(height: 12),
                          _WelcomePanel(
                            weekSeconds: summary.weekSeconds,
                            sessionCount: summary.todaySessions,
                          ),
                          const SizedBox(height: 6),
                          const Center(child: Eagle3DView(size: 170)),
                          const SizedBox(height: 6),
                          _TimerCard(
                            mode: timer.mode,
                            seconds: seconds,
                            countdownDurationSeconds:
                                timer.countdownDurationSeconds,
                            isRunning: timer.isRunning,
                            hasSession: timer.hasSession,
                            subject: timer.subject,
                            onSubjectSelected: controller.setSubject,
                            onModeSelected: controller.selectMode,
                            onToggle: controller.startOrResume,
                            onReset: confirmReset,
                            onLap: lap,
                            onFinish: finish,
                          ),
                          if (timer.mode == TimerMode.countdown) ...[
                            const SizedBox(height: 18),
                            _PresetPicker(
                              selectedSeconds: timer.countdownDurationSeconds,
                              enabled: !timer.hasSession,
                              onSelected: controller.setCountdownDuration,
                            ),
                          ],
                          if (timer.laps.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _LapList(laps: timer.laps),
                          ],
                          const SizedBox(height: 24),
                          const _SectionHeading(
                            title: 'TODAY AT A GLANCE',
                            trailing: 'ASIA/KOLKATA',
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _MetricCard(
                                  icon: Icons.today_rounded,
                                  label:
                                      "Today · goal ${formatDuration(summary.dailyTargetMinutes * 60)}",
                                  value: formatDuration(summary.todaySeconds),
                                  tint: AppColors.cyan,
                                  progress: _ratio(
                                    summary.todaySeconds,
                                    summary.dailyTargetMinutes * 60,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  icon: Icons.bolt_rounded,
                                  label: 'Sessions today',
                                  value: '${summary.todaySessions}',
                                  tint: AppColors.lime,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _MetricCard(
                                  icon: Icons.date_range_rounded,
                                  label:
                                      'Week · goal ${formatDuration(summary.weeklyTargetMinutes * 60)}',
                                  value: formatDuration(summary.weekSeconds),
                                  tint: const Color(0xFFB69AFF),
                                  progress: _ratio(
                                    summary.weekSeconds,
                                    summary.weeklyTargetMinutes * 60,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 26),
                          Row(
                            children: [
                              const Expanded(
                                child: _SectionHeading(
                                  title: 'RECENT SESSIONS',
                                  trailing: '',
                                ),
                              ),
                              TextButton(
                                onPressed: () => context.push('/history'),
                                child: const Text('VIEW ALL'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (summary.recent.isEmpty)
                            const Text(
                              'Finished sessions will appear here.',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ...summary.recent.map(
                            (session) => _SessionRow(
                              startedAt: ref
                                  .read(studyCalendarProvider)
                                  .local(session.startedAt),
                              durationSeconds: session.durationSeconds,
                              subject: session.subject,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _OfflineNote(pendingSync: summary.pendingSync),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

double? _ratio(int value, int target) =>
    target <= 0 ? null : (value / target).clamp(0, 1).toDouble();

class _Header extends StatelessWidget {
  const _Header({required this.onFocusTap});

  final VoidCallback onFocusTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF88EEFF), Color(0xFF168AB6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: 0.25),
                blurRadius: 22,
              ),
            ],
          ),
          child: const Icon(
            Icons.flight_rounded,
            color: Colors.white,
            size: 25,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EAGLE STUDY',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'FOCUS. BUILD. SOAR.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 9,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'About & credits',
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'EAGLE STUDY',
            applicationLegalese:
                '3D eagle: "Bald Eagle" by ucdavisterc (CC BY 4.0), see the '
                '"Bald Eagle 3D model" entry below.',
          ),
          icon: const Icon(Icons.info_outline_rounded, color: AppColors.muted),
        ),
        IconButton.filledTonal(
          onPressed: onFocusTap,
          tooltip: 'Open Study Mode',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            foregroundColor: AppColors.cyan,
          ),
          icon: const Icon(Icons.fullscreen_rounded),
        ),
      ],
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.weekSeconds, required this.sessionCount});

  final int weekSeconds;
  final int sessionCount;

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'GOOD MORNING'
        : hour < 18
        ? 'GOOD AFTERNOON'
        : 'GOOD EVENING';
    return GlassPanel(
      padding: const EdgeInsets.all(19),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Make this hour count.',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$sessionCount sessions · ${formatDuration(weekSeconds)} this week',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cyan.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: AppColors.lime,
              size: 25,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerCard extends StatelessWidget {
  const _TimerCard({
    required this.mode,
    required this.seconds,
    required this.countdownDurationSeconds,
    required this.isRunning,
    required this.hasSession,
    required this.subject,
    required this.onSubjectSelected,
    required this.onModeSelected,
    required this.onToggle,
    required this.onReset,
    required this.onLap,
    required this.onFinish,
  });

  final TimerMode mode;
  final int seconds;
  final int countdownDurationSeconds;
  final bool isRunning;
  final bool hasSession;
  final String? subject;
  final ValueChanged<String?> onSubjectSelected;
  final ValueChanged<TimerMode> onModeSelected;
  final VoidCallback onToggle;
  final VoidCallback onReset;
  final VoidCallback onLap;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final isCountdown = mode == TimerMode.countdown;
    final progress = isCountdown && seconds > 0
        ? 1 - seconds / countdownDurationSeconds
        : 0.0;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 18),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                _ModeButton(
                  label: 'STOPWATCH',
                  selected: !isCountdown,
                  enabled: !hasSession,
                  onTap: () => onModeSelected(TimerMode.stopwatch),
                ),
                _ModeButton(
                  label: 'FOCUS TIMER',
                  selected: isCountdown,
                  enabled: !hasSession,
                  onTap: () => onModeSelected(TimerMode.countdown),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SubjectPicker(selected: subject, onSelected: onSubjectSelected),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.circle, size: 7, color: AppColors.lime),
              const SizedBox(width: 7),
              Text(
                isRunning
                    ? 'SESSION IN PROGRESS'
                    : hasSession
                    ? 'PAUSED'
                    : 'READY WHEN YOU ARE',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  letterSpacing: 1.55,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress.clamp(0, 1)),
            duration: const Duration(milliseconds: 450),
            builder: (context, value, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (isCountdown)
                    SizedBox(
                      width: 226,
                      height: 145,
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 3,
                        backgroundColor: Colors.white.withValues(alpha: 0.07),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.lime,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 21),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatClock(seconds),
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 58,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 1,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          Text(
            isCountdown ? 'FOCUS SESSION' : 'TOTAL FOCUS TIME',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 21),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SmallAction(
                icon: Icons.restart_alt_rounded,
                label: 'RESET',
                onTap: onReset,
              ),
              const SizedBox(width: 18),
              _PrimaryPlayButton(isRunning: isRunning, onTap: onToggle),
              const SizedBox(width: 18),
              // Stopwatch: LAP while running, FINISH once paused.
              // Focus timer: FINISH ends early and saves the focused part.
              if (!isCountdown && isRunning)
                _SmallAction(
                  icon: Icons.flag_rounded,
                  label: 'LAP',
                  onTap: onLap,
                )
              else
                _SmallAction(
                  icon: Icons.check_rounded,
                  label: 'FINISH',
                  onTap: hasSession ? onFinish : null,
                ),
            ],
          ),
          if (isRunning) ...[
            const SizedBox(height: 17),
            TextButton.icon(
              onPressed: () => context.push('/study'),
              icon: const Icon(Icons.fullscreen_rounded, size: 17),
              label: const Text('OPEN DISTRACTION-FREE STUDY MODE'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.cyan,
                textStyle: const TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF4A637E), Color(0xFF344A63)],
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.text : AppColors.muted,
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({required this.isRunning, required this.onTap});

  final bool isRunning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isRunning
                ? const [Color(0xFF65E2F8), Color(0xFF1D9FC8)]
                : const [AppColors.pink, Color(0xFFE73F70)],
          ),
          boxShadow: [
            BoxShadow(
              color: (isRunning ? AppColors.cyan : AppColors.pink).withValues(
                alpha: 0.35,
              ),
              blurRadius: 22,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: onTap == null
                    ? AppColors.muted.withValues(alpha: 0.35)
                    : AppColors.muted,
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: onTap == null
                      ? AppColors.muted.withValues(alpha: 0.35)
                      : AppColors.muted,
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetPicker extends StatefulWidget {
  const _PresetPicker({
    required this.selectedSeconds,
    required this.enabled,
    required this.onSelected,
  });

  final int selectedSeconds;
  final bool enabled;
  final bool Function(int seconds) onSelected;

  @override
  State<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends State<_PresetPicker> {
  final _formKey = GlobalKey<FormState>();
  final _hoursController = TextEditingController();
  final _minutesController = TextEditingController();
  final _secondsController = TextEditingController();

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  Future<void> _showCustomDuration() async {
    _hoursController.clear();
    _minutesController.clear();
    _secondsController.clear();
    final seconds = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom focus timer'),
        content: Form(
          key: _formKey,
          child: Row(
            children: [
              _DurationField(
                controller: _hoursController,
                label: 'Hours',
                max: 24,
              ),
              const SizedBox(width: 8),
              _DurationField(
                controller: _minutesController,
                label: 'Minutes',
                max: 59,
              ),
              const SizedBox(width: 8),
              _DurationField(
                controller: _secondsController,
                label: 'Seconds',
                max: 59,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              final total =
                  (int.tryParse(_hoursController.text) ?? 0) * 3600 +
                  (int.tryParse(_minutesController.text) ?? 0) * 60 +
                  (int.tryParse(_secondsController.text) ?? 0);
              if (total == 0 || total > maxSessionSeconds) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      total == 0
                          ? 'Enter a duration greater than zero.'
                          : 'A session can be at most 24 hours.',
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context, total);
            },
            child: const Text('SET TIMER'),
          ),
        ],
      ),
    );
    if (seconds != null) widget.onSelected(seconds);
  }

  @override
  Widget build(BuildContext context) {
    const presets = [5, 15, 25, 45, 60, 90];
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'QUICK PRESETS',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets.map((minutes) {
              final selected = widget.selectedSeconds == minutes * 60;
              return ChoiceChip(
                label: Text('${minutes}m'),
                selected: selected,
                onSelected: widget.enabled
                    ? (_) => widget.onSelected(minutes * 60)
                    : null,
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: selected ? AppColors.background : AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                selectedColor: AppColors.lime,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(
                  color: selected
                      ? AppColors.lime
                      : Colors.white.withValues(alpha: 0.08),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.enabled ? _showCustomDuration : null,
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text('CUSTOM HOURS / MINUTES / SECONDS'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.cyan,
              side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.28)),
              textStyle: const TextStyle(fontSize: 9, letterSpacing: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationField extends StatelessWidget {
  const _DurationField({
    required this.controller,
    required this.label,
    required this.max,
  });

  final TextEditingController controller;
  final String label;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
        maxLength: 2,
        validator: (value) {
          final parsed = int.tryParse(value ?? '');
          if (parsed == null) return null;
          if (parsed < 0 || parsed > max) return '0–$max';
          return null;
        },
      ),
    );
  }
}

class _LapList extends StatelessWidget {
  const _LapList({required this.laps});

  final List<int> laps;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (var index = laps.length - 1; index >= 0; index--)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    'LAP ${index + 1}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatClock(laps[index]),
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 8,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(11, 13, 9, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tint, size: 17),
          const SizedBox(height: 13),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 9),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(tint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.startedAt,
    required this.durationSeconds,
    required this.subject,
  });

  /// Local time in the study timezone.
  final DateTime startedAt;
  final int durationSeconds;
  final String? subject;

  @override
  Widget build(BuildContext context) {
    final time =
        '${dayLabel(startedAt).split(',').first} ${clockTime(startedAt)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.lime, size: 17),
            const SizedBox(width: 10),
            Text(
              time,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subject ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.text, fontSize: 12),
              ),
            ),
            Text(
              formatDuration(durationSeconds),
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineNote extends ConsumerWidget {
  const _OfflineNote({required this.pendingSync});

  final int pendingSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final sync = ref.watch(syncControllerProvider);

    final IconData icon;
    final Color color;
    final String label;

    if (session == null) {
      icon = Icons.lock_outline_rounded;
      color = AppColors.muted.withValues(alpha: 0.8);
      label = pendingSync == 0
          ? 'Saved on this device'
          : 'Saved on this device · $pendingSync '
                '${pendingSync == 1 ? 'change' : 'changes'} waiting to sync';
    } else if (sync.syncing) {
      icon = Icons.cloud_sync_rounded;
      color = AppColors.cyan;
      label = 'Syncing with PostgreSQL...';
    } else if (sync.lastError != null) {
      icon = Icons.error_outline_rounded;
      color = AppColors.pink;
      label = 'Sync paused · Tap to retry';
    } else if (pendingSync > 0) {
      icon = Icons.cloud_upload_outlined;
      color = AppColors.cyan;
      label =
          '$pendingSync ${pendingSync == 1 ? 'change' : 'changes'} waiting · Tap to sync';
    } else {
      icon = Icons.cloud_done_rounded;
      color = AppColors.lime.withValues(alpha: 0.9);
      label = 'Synced to cloud (${session.email})';
    }

    return InkWell(
      onTap: () => showSyncAccountSheet(context),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  const _AmbientBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A3952),
              Color(0xFF11243B),
              AppColors.background,
            ],
            stops: [0, 0.44, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -110,
              right: -80,
              child: _GlowOrb(
                color: AppColors.cyan.withValues(alpha: 0.17),
                size: 280,
              ),
            ),
            Positioned(
              top: 380,
              left: -150,
              child: _GlowOrb(
                color: const Color(0xFF3B8DF0).withValues(alpha: 0.1),
                size: 280,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _SubjectPicker extends StatelessWidget {
  const _SubjectPicker({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final subject in studySubjects)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(subject),
                selected: subject == selected,
                showCheckmark: false,
                onSelected: (on) => onSelected(on ? subject : null),
                labelStyle: TextStyle(
                  color: subject == selected
                      ? AppColors.background
                      : AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                selectedColor: AppColors.cyan,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _UpcomingAlarm extends ConsumerWidget {
  const _UpcomingAlarm();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = ref.watch(nextAlarmProvider);
    final calendar = ref.watch(studyCalendarProvider);
    final now = ref.read(clockProvider)();
    return GlassPanel(
      child: ListTile(
        onTap: () => context.push('/alarms'),
        leading: const Icon(Icons.alarm_rounded, color: AppColors.cyan),
        title: Text(
          next == null
              ? 'No alarm set'
              : '${timeLabel(next.alarm.hour, next.alarm.minute)} · '
                    '${relativeLabel(next.at, now, calendar)}',
          style: const TextStyle(color: AppColors.text, fontSize: 14),
        ),
        subtitle: Text(
          next == null
              ? 'Tap to add a study alarm'
              : '${repeatLabel(next.alarm.days)} · ${next.alarm.sound.label}',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
        ),
      ),
    );
  }
}
