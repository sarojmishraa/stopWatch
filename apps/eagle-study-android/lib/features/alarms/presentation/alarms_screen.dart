import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../application/alarm_controller.dart';
import '../data/alarm_bridge.dart';
import '../domain/alarm.dart';
import 'alarm_editor_sheet.dart';
import 'alarm_format.dart';

class AlarmsScreen extends ConsumerWidget {
  const AlarmsScreen({super.key});

  Future<void> _edit(
    BuildContext context,
    Alarm alarm, {
    required bool isNew,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => AlarmEditorSheet(initial: alarm, isNew: isNew),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(secondTickerProvider);
    final alarms = ref.watch(alarmControllerProvider);
    final permissions = ref.watch(alarmPermissionsProvider).value;
    final calendar = ref.watch(studyCalendarProvider);
    final now = ref.read(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Alarms'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(
          context,
          Alarm(
            id: const Uuid().v4(),
            hour: 7,
            minute: 0,
            days: const {1, 2, 3, 4, 5},
          ),
          isNew: true,
        ),
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('NEW ALARM'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (permissions != null) _PermissionPanel(permissions: permissions),
          const _TimerSoundPanel(),
          const SizedBox(height: 16),
          ...switch (alarms) {
            AsyncData(:final value) when value.isEmpty => [
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No alarms yet. Tap NEW ALARM to add one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
            AsyncData(:final value) => [
              for (final alarm in value)
                _AlarmTile(
                  alarm: alarm,
                  nextLabel: alarm.enabled
                      ? 'Rings ${relativeLabel(nextTrigger(alarm, now, calendar), now, calendar)}'
                      : 'Off',
                  onTap: () => _edit(context, alarm, isNew: false),
                  onToggle: (on) async {
                    try {
                      await ref
                          .read(alarmControllerProvider.notifier)
                          .setEnabled(alarm.id, on);
                    } catch (e) {
                      if (context.mounted) _showError(context, e);
                    }
                  },
                ),
            ],
            AsyncError(:final error) => [Text("Couldn't load alarms: $error")],
            _ => [const Center(child: CircularProgressIndicator())],
          },
        ],
      ),
    );
  }
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
}

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({
    required this.alarm,
    required this.nextLabel,
    required this.onTap,
    required this.onToggle,
  });

  final Alarm alarm;
  final String nextLabel;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final dim = alarm.enabled ? 1.0 : 0.45;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
            child: Row(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: dim,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          timeLabel(alarm.hour, alarm.minute),
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 34,
                            fontWeight: FontWeight.w300,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          '${repeatLabel(alarm.days)} · ${alarm.sound.label}',
                          style: const TextStyle(
                            color: AppColors.cyan,
                            fontSize: 12,
                          ),
                        ),
                        if (alarm.message.isNotEmpty)
                          Text(
                            alarm.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        Text(
                          nextLabel,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Switch(value: alarm.enabled, onChanged: onToggle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains each missing permission in plain words before sending the user
/// to grant it. Nothing is requested silently.
class _PermissionPanel extends ConsumerWidget {
  const _PermissionPanel({required this.permissions});

  final AlarmPermissions permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.read(alarmBridgeProvider);
    final rows = [
      if (!permissions.notifications)
        (
          'Notifications are off',
          'Needed to show the ringing alarm with Snooze and Dismiss.',
          'ALLOW',
          bridge.requestNotifications,
        ),
      if (!permissions.exactAlarms)
        (
          'Exact alarms are off',
          'Without this, Android may ring your alarm several minutes late.',
          'OPEN SETTINGS',
          bridge.openExactAlarmSettings,
        ),
      if (!permissions.fullScreen)
        (
          'Lock-screen alarm is off',
          'You will get a notification instead of a full-screen alarm.',
          'OPEN SETTINGS',
          bridge.openFullScreenSettings,
        ),
      if (!permissions.batteryUnrestricted)
        (
          'Battery optimisation is on',
          'Recommended: set EAGLE STUDY to “Unrestricted”. Some phones '
              '(Xiaomi, Oppo, Vivo, Samsung) can delay alarms otherwise.',
          'OPEN SETTINGS',
          bridge.openBatterySettings,
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FOR RELIABLE ALARMS',
              style: TextStyle(
                color: AppColors.pink,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            for (final (title, why, action, open) in rows)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(color: AppColors.text),
                          ),
                          Text(
                            why,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await open();
                        } catch (e) {
                          if (context.mounted) _showError(context, e);
                        }
                      },
                      child: Text(action),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final _timerSoundProvider = FutureProvider<AlarmSound>(
  (ref) => ref.watch(alarmRepositoryProvider).timerSound(),
);

class _TimerSoundPanel extends ConsumerWidget {
  const _TimerSoundPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(_timerSoundProvider).value ?? AlarmSound.classic;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: [
          const Icon(
            Icons.hourglass_bottom_rounded,
            color: AppColors.cyan,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Focus timer end sound',
              style: TextStyle(color: AppColors.text),
            ),
          ),
          DropdownButton<AlarmSound>(
            value: current,
            underline: const SizedBox.shrink(),
            items: [
              for (final sound in AlarmSound.values.where(
                (s) => s != AlarmSound.recording,
              ))
                DropdownMenuItem(value: sound, child: Text(sound.label)),
            ],
            onChanged: (sound) async {
              if (sound == null) return;
              await ref.read(alarmRepositoryProvider).setTimerSound(sound);
              ref.invalidate(_timerSoundProvider);
            },
          ),
        ],
      ),
    );
  }
}
