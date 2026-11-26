import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../application/alarm_controller.dart';
import '../data/alarm_bridge.dart';
import '../data/alarm_repository.dart';
import '../domain/alarm.dart';
import 'alarm_format.dart';

class AlarmEditorSheet extends ConsumerStatefulWidget {
  const AlarmEditorSheet({
    required this.initial,
    required this.isNew,
    super.key,
  });

  final Alarm initial;
  final bool isNew;

  @override
  ConsumerState<AlarmEditorSheet> createState() => _AlarmEditorSheetState();
}

class _AlarmEditorSheetState extends ConsumerState<AlarmEditorSheet> {
  late Alarm _alarm = widget.initial;
  late final _message = TextEditingController(text: widget.initial.message);
  bool _busy = false;
  bool _recording = false;
  bool _previewing = false;
  late final AlarmBridge _bridge;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(alarmBridgeProvider);
  }

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  void dispose() {
    _message.dispose();
    // ref is unusable in dispose(); use the bridge captured in initState.
    if (_previewing) _bridge.stopPreview().ignore();
    if (_recording) _bridge.stopRecording().ignore();
    super.dispose();
  }

  Alarm get _current => _alarm.copyWith(message: _message.text);

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _alarm.hour, minute: _alarm.minute),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(
        () =>
            _alarm = _alarm.copyWith(hour: picked.hour, minute: picked.minute),
      );
    }
  }

  Future<void> _togglePreview() async {
    final bridge = ref.read(alarmBridgeProvider);
    try {
      if (_previewing) {
        await bridge.stopPreview();
      } else {
        await bridge.preview(
          _current.toNative(ref.read(studyCalendarProvider).zoneName),
        );
      }
      if (mounted) setState(() => _previewing = !_previewing);
    } catch (e) {
      _toast('Preview failed: ${_describe(e)}');
    }
  }

  Future<void> _toggleRecording() async {
    final bridge = ref.read(alarmBridgeProvider);
    try {
      if (_recording) {
        await bridge.stopRecording();
        setState(() => _recording = false);
        _toast('Recording saved. Tap PREVIEW to hear it.');
        return;
      }
      final permissions = await bridge.permissions();
      if (!permissions.microphone) {
        await bridge.requestMicrophone();
        _toast('Allow the microphone, then tap RECORD again.');
        return;
      }
      final old = _alarm.recordingPath;
      final path = await bridge.startRecording();
      setState(() {
        _recording = true;
        _alarm = _alarm.copyWith(recordingPath: path);
      });
      if (old != null && old != widget.initial.recordingPath) {
        bridge.deleteRecording(old).ignore();
      }
    } catch (e) {
      setState(() => _recording = false);
      _toast(_describe(e));
    }
  }

  Future<void> _save() async {
    if (_recording) await _toggleRecording();
    setState(() => _busy = true);
    try {
      final permissions = await ref.read(alarmBridgeProvider).permissions();
      if (!permissions.notifications) {
        await ref.read(alarmBridgeProvider).requestNotifications();
      }
      await ref
          .read(alarmControllerProvider.notifier)
          .save(_current.copyWith(enabled: true));
      if (mounted) Navigator.pop(context);
      final previous = widget.initial.recordingPath;
      if (previous != null && previous != _alarm.recordingPath) {
        ref.read(alarmBridgeProvider).deleteRecording(previous).ignore();
      }
    } on InvalidAlarmException catch (e) {
      _toast(e.problems.join(' '));
    } catch (e) {
      _toast("Couldn't schedule the alarm: ${_describe(e)}");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(alarmControllerProvider.notifier)
          .delete(widget.initial.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _toast(_describe(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _describe(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: TextButton(
                onPressed: _busy ? null : _pickTime,
                child: Text(
                  timeLabel(_alarm.hour, _alarm.minute),
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ),
            ),
            Center(
              child: Text(
                repeatLabel(_alarm.days),
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var day = 1; day <= 7; day++)
                  _DayChip(
                    label: _dayLetters[day - 1],
                    semantics: const [
                      'Monday',
                      'Tuesday',
                      'Wednesday',
                      'Thursday',
                      'Friday',
                      'Saturday',
                      'Sunday',
                    ][day - 1],
                    selected: _alarm.days.contains(day),
                    onTap: () => setState(() {
                      final days = {..._alarm.days};
                      days.contains(day) ? days.remove(day) : days.add(day);
                      _alarm = _alarm.copyWith(days: days);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Time to study. Wake up, eagle.',
                helperText: 'Shown on the alarm, and spoken by voice styles',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'SOUND',
              style: TextStyle(fontSize: 11, letterSpacing: 1.2),
            ),
            RadioGroup<AlarmSound>(
              groupValue: _alarm.sound,
              onChanged: (s) =>
                  setState(() => _alarm = _alarm.copyWith(sound: s)),
              child: Column(
                children: [
                  for (final sound in AlarmSound.values)
                    RadioListTile<AlarmSound>(
                      value: sound,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(sound.label),
                      subtitle: Text(sound.description),
                    ),
                ],
              ),
            ),
            if (_alarm.sound == AlarmSound.recording)
              OutlinedButton.icon(
                onPressed: _busy ? null : _toggleRecording,
                icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(
                  _recording
                      ? 'STOP RECORDING'
                      : _alarm.recordingPath == null
                      ? 'RECORD (UP TO 30 S)'
                      : 'RECORD AGAIN',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _recording ? AppColors.pink : AppColors.cyan,
                ),
              ),
            Row(
              children: [
                const Icon(
                  Icons.volume_up_rounded,
                  color: AppColors.muted,
                  size: 20,
                ),
                Expanded(
                  child: Slider(
                    value: _alarm.volume,
                    min: 0.1,
                    divisions: 9,
                    label: '${(_alarm.volume * 100).round()}%',
                    onChanged: (v) =>
                        setState(() => _alarm = _alarm.copyWith(volume: v)),
                  ),
                ),
                TextButton.icon(
                  onPressed: _busy || _recording ? null : _togglePreview,
                  icon: Icon(
                    _previewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_previewing ? 'STOP' : 'PREVIEW'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibrate'),
              value: _alarm.vibrate,
              onChanged: (v) =>
                  setState(() => _alarm = _alarm.copyWith(vibrate: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (!widget.isNew)
                  TextButton.icon(
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('DELETE'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.pink,
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('SAVE'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.semantics,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semantics;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected
                ? AppColors.cyan
                : Colors.white.withValues(alpha: 0.06),
          ),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.background : AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
