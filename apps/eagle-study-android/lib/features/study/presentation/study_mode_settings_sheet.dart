import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../application/study_mode_controller.dart';
import '../domain/study_mode_prefs.dart';

class StudyModeSettingsSheet extends ConsumerWidget {
  const StudyModeSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs =
        ref.watch(studyModePrefsProvider).value ?? const StudyModePrefs();
    final hasDndAccess = ref.watch(dndAccessProvider).value ?? false;
    final save = ref.read(studyModePrefsProvider.notifier).save;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Study Mode', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text(
              'Applies while this screen is open and is undone when you leave.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep screen on'),
              subtitle: const Text('The screen will not sleep in Study Mode'),
              value: prefs.keepScreenOn,
              onChanged: (v) => save(prefs.copyWith(keepScreenOn: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Session notification'),
              subtitle: const Text(
                'Shows the running timer with Pause, Resume and Finish',
              ),
              value: prefs.sessionNotification,
              onChanged: (v) => save(prefs.copyWith(sessionNotification: v)),
            ),
            const Divider(),
            const Text(
              'DO NOT DISTURB',
              style: TextStyle(fontSize: 11, letterSpacing: 1.2),
            ),
            if (!hasDndAccess)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'To silence notifications while you study, Android needs you '
                      'to allow EAGLE STUDY to change Do Not Disturb. The app only '
                      'changes it in Study Mode and restores your previous setting '
                      'when you leave.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    OutlinedButton(
                      onPressed: () => ref
                          .read(studyModeBridgeProvider)
                          .openDndSettings()
                          .catchError((Object e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not open settings: $e'),
                                ),
                              );
                            }
                          }),
                      child: const Text('ALLOW DO NOT DISTURB ACCESS'),
                    ),
                  ],
                ),
              ),
            RadioGroup<DndMode>(
              groupValue: prefs.dnd,
              onChanged: (mode) {
                if (mode != null) save(prefs.copyWith(dnd: mode));
              },
              child: Column(
                children: [
                  for (final mode in DndMode.values)
                    RadioListTile<DndMode>(
                      value: mode,
                      enabled: mode == DndMode.off || hasDndAccess,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(mode.label),
                      subtitle: Text(mode.description),
                    ),
                ],
              ),
            ),
            const Text(
              '“Total silence” is not offered because it would also mute the '
              'focus timer’s completion alarm.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
