import 'package:flutter/material.dart';

import '../../../core/persistence/study_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../application/learning_controller.dart';

class SleepHealthCard extends StatelessWidget {
  const SleepHealthCard({required this.tasks, super.key});

  final List<ScheduledStudyTask> tasks;

  @override
  Widget build(BuildContext context) {
    final minimumRest = minimumOvernightRest(tasks);
    final isAtRisk =
        minimumRest != null && minimumRest < const Duration(hours: 7);
    final message = minimumRest == null
        ? 'Not enough upcoming sessions to estimate your overnight rest window.'
        : minimumRest.isNegative
        ? 'Your planned sessions overlap across consecutive days. Move a session to create a safe rest window.'
        : isAtRisk
        ? 'Your shortest overnight gap is ${_formatDuration(minimumRest.inMinutes)}. That is below the 7-hour adult sleep recommendation. Consider moving or shortening a late session.'
        : 'Your shortest overnight gap is ${_formatDuration(minimumRest.inMinutes)}. Your plan allows at least 7 hours between study days.';
    final tint = isAtRisk ? AppColors.pink : AppColors.lime;

    return GlassPanel(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bedtime_outlined, color: tint, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SLEEP HEALTH CHECK',
                  style: TextStyle(
                    color: tint,
                    fontSize: 9,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 10,
                    height: 1.45,
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

String _formatDuration(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours == 0) return '${remainder}m';
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}
