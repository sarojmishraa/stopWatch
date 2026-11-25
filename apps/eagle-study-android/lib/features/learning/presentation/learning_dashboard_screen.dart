import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/study_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../../timer/application/study_timer_controller.dart';
import '../application/learning_controller.dart';
import 'roadmap_screen.dart';
import 'schedule_screen.dart';
import 'sleep_health_card.dart';

class LearningDashboardScreen extends ConsumerStatefulWidget {
  const LearningDashboardScreen({super.key});

  @override
  ConsumerState<LearningDashboardScreen> createState() =>
      _LearningDashboardScreenState();
}

class _LearningDashboardScreenState
    extends ConsumerState<LearningDashboardScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final learning = ref.watch(learningControllerProvider);
    final pages = [
      _OverviewPage(
        learning: learning,
        onOpenSchedule: () => setState(() => _index = 1),
      ),
      const ScheduleScreen(),
      const RoadmapScreen(),
      const LearningTracksPage(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 18,
        title: const Row(
          children: [
            Icon(Icons.flight_takeoff_rounded, color: AppColors.cyan, size: 23),
            SizedBox(width: 8),
            Text(
              'EAGLE STUDY',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/timer'),
            icon: const Icon(Icons.timer_outlined, size: 17),
            label: const Text('FOCUS'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.cyan,
              textStyle: const TextStyle(
                fontSize: 9,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          const _DashboardBackdrop(),
          SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = IndexedStack(index: _index, children: pages);
                if (constraints.maxWidth >= 820) {
                  return Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: (index) =>
                            setState(() => _index = index),
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: Colors.transparent,
                        selectedIconTheme: const IconThemeData(
                          color: AppColors.cyan,
                        ),
                        selectedLabelTextStyle: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 10,
                        ),
                        unselectedLabelTextStyle: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                        ),
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.space_dashboard_outlined),
                            selectedIcon: Icon(Icons.space_dashboard_rounded),
                            label: Text('Overview'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.calendar_month_outlined),
                            selectedIcon: Icon(Icons.calendar_month_rounded),
                            label: Text('Schedule'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.public_outlined),
                            selectedIcon: Icon(Icons.public_rounded),
                            label: Text('Roadmap'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.code_rounded),
                            selectedIcon: Icon(Icons.code_rounded),
                            label: Text('Tracks'),
                          ),
                        ],
                      ),
                      const VerticalDivider(width: 1, color: Color(0x1FFFFFFF)),
                      Expanded(child: content),
                    ],
                  );
                }
                return content;
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 820
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              backgroundColor: const Color(0xFF0B1928),
              indicatorColor: AppColors.cyan.withValues(alpha: 0.15),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard_rounded),
                  label: 'Overview',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Schedule',
                ),
                NavigationDestination(
                  icon: Icon(Icons.public_outlined),
                  selectedIcon: Icon(Icons.public_rounded),
                  label: 'Roadmap',
                ),
                NavigationDestination(
                  icon: Icon(Icons.code_rounded),
                  selectedIcon: Icon(Icons.code_rounded),
                  label: 'Tracks',
                ),
              ],
            )
          : null,
    );
  }
}

class _OverviewPage extends ConsumerWidget {
  const _OverviewPage({required this.learning, required this.onOpenSchedule});

  final LearningState learning;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = asiaKolkataToday();
    final todayMinutes = learning.dayTasks
        .where((task) => task.isComplete)
        .fold<int>(0, (total, task) => total + task.durationMinutes);
    final weekMinutes = learning.weekTasks
        .where((task) => task.isComplete)
        .fold<int>(0, (total, task) => total + task.durationMinutes);
    final weekPercent = (weekMinutes / (50 * 60)).clamp(0, 1).toDouble();
    final nextTask = learning.upcomingTasks
        .where((task) => !task.isComplete)
        .firstOrNull;
    final timer = ref.watch(studyTimerProvider);
    final nextTitle = nextTask == null
        ? 'No upcoming sessions'
        : '${nextTask.subject} · ${nextTask.topic}';
    final nextDate = nextTask == null
        ? 'Add a session to your calendar'
        : '${_dateLabel(nextTask.date)} at ${nextTask.startTime}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        GlassPanel(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DISTRIBUTED SYSTEMS ENGINEER · 12-MONTH PLAN',
                          style: TextStyle(
                            color: AppColors.cyan,
                            fontSize: 9,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Build skills. Ship systems.',
                          style: TextStyle(
                            color: AppColors.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.hub_rounded,
                    color: AppColors.cyan,
                    size: 38,
                  ),
                ],
              ),
              const SizedBox(height: 11),
              const Text(
                'JAVA BACKEND  ·  GO BACKEND  ·  PLATFORM  ·  DISTRIBUTED SYSTEMS',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 8,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _Tag(
                    icon: Icons.calendar_today_rounded,
                    text:
                        '${_dateLabel(DateTime(2026, 11, 30))} — ${_dateLabel(DateTime(2027, 11, 28))}',
                  ),
                  const _Tag(icon: Icons.public_rounded, text: 'Asia/Kolkata'),
                  const _Tag(
                    icon: Icons.flag_rounded,
                    text: '50 study hours / week',
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.pink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: AppColors.pink.withValues(alpha: 0.22),
                  ),
                ),
                child: const Text(
                  'SAMPLE ROADMAP · Progress starts at 0% and is saved on this device',
                  style: TextStyle(
                    color: AppColors.pink,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: _OverviewMetric(
                label: 'TODAY',
                value: _formatDuration(todayMinutes),
                detail: 'completed study',
                icon: Icons.today_rounded,
                color: AppColors.cyan,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _OverviewMetric(
                label: 'THIS WEEK',
                value:
                    '${(weekMinutes / 60).toStringAsFixed(weekMinutes % 60 == 0 ? 0 : 1)}h',
                detail: 'of 50h target',
                icon: Icons.bolt_rounded,
                color: AppColors.lime,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _OverviewMetric(
                label: 'ROADMAP',
                value:
                    '${learning.milestones.where((item) => item.completion == 100).length}/12',
                detail: 'milestones done',
                icon: Icons.flag_rounded,
                color: const Color(0xFFB69AFF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        GlassPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'WEEKLY FOCUS',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${(weekMinutes / 60).toStringAsFixed(weekMinutes % 60 == 0 ? 0 : 1)} / 50 h',
                    style: const TextStyle(
                      color: AppColors.lime,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: weekPercent,
                  minHeight: 7,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: const AlwaysStoppedAnimation(AppColors.lime),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  const Icon(
                    Icons.bedtime_outlined,
                    color: AppColors.pink,
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  const Expanded(
                    child: Text(
                      'Sleep schedule needs review',
                      style: TextStyle(color: AppColors.muted, fontSize: 9),
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenSchedule,
                    child: const Text(
                      'REVIEW',
                      style: TextStyle(fontSize: 8, letterSpacing: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            Expanded(
              child: GlassPanel(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.event_note_rounded,
                      color: AppColors.cyan,
                      size: 19,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'NEXT STUDY BLOCK',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 8,
                        letterSpacing: 0.9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      nextTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nextDate,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: InkWell(
                onTap: () => context.push('/study'),
                borderRadius: BorderRadius.circular(22),
                child: GlassPanel(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        timer.isRunning
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                        color: AppColors.pink,
                        size: 20,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'FOCUS SESSION',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 8,
                          letterSpacing: 0.9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        timer.isRunning
                            ? 'Resume your timer'
                            : 'Start a study timer',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Stopwatch · countdown · session history',
                        style: TextStyle(color: AppColors.muted, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        SleepHealthCard(tasks: learning.upcomingTasks),
        const SizedBox(height: 20),
        const Text(
          'TODAY · ASIA/KOLKATA',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 9),
        if (learning.dayTasks.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(15),
            child: Text(
              today.isBefore(DateTime(2026, 11, 30))
                  ? 'Your study plan starts ${_dateLabel(DateTime(2026, 11, 30))}. Your schedule is ready to preview.'
                  : 'No sessions on today’s calendar. Add one from Schedule.',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          )
        else
          ...learning.dayTasks
              .take(3)
              .map((task) => _CompactSession(task: task)),
        const SizedBox(height: 18),
        _WeeklyReportCard(learning: learning),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.cyan, size: 11),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(color: AppColors.muted, fontSize: 8),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(11, 12, 9, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 9),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 7,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 8),
          ),
        ],
      ),
    );
  }
}

class _CompactSession extends StatelessWidget {
  const _CompactSession({required this.task});

  final ScheduledStudyTask task;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        child: Row(
          children: [
            Icon(
              task.isComplete ? Icons.check_circle : Icons.circle_outlined,
              color: task.isComplete ? AppColors.lime : AppColors.cyan,
              size: 16,
            ),
            const SizedBox(width: 10),
            Text(
              task.startTime,
              style: const TextStyle(color: AppColors.cyan, fontSize: 10),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${task.subject} · ${task.task}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.text, fontSize: 10),
              ),
            ),
            Text(
              '${(task.durationMinutes / 60).toStringAsFixed(0)}h',
              style: const TextStyle(color: AppColors.muted, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyReportCard extends StatelessWidget {
  const _WeeklyReportCard({required this.learning});

  final LearningState learning;

  @override
  Widget build(BuildContext context) {
    final weekDays = List.generate(7, (index) {
      final monday = (learning.selectedDate ?? asiaKolkataToday()).subtract(
        Duration(
          days: (learning.selectedDate ?? asiaKolkataToday()).weekday - 1,
        ),
      );
      final date = monday.add(Duration(days: index));
      final minutes = learning.weekTasks
          .where(
            (task) =>
                task.isComplete &&
                task.date.year == date.year &&
                task.date.month == date.month &&
                task.date.day == date.day,
          )
          .fold<int>(0, (sum, task) => sum + task.durationMinutes);
      return (date: date, hours: minutes / 60);
    });
    final total = weekDays.fold<double>(0, (sum, day) => sum + day.hours);
    return GlassPanel(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'WEEKLY REPORT',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'COMPLETED TIME',
                style: TextStyle(color: AppColors.muted, fontSize: 8),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${total.toStringAsFixed(total.truncateToDouble() == total ? 0 : 1)} hours logged · ${learning.weekTasks.where((task) => task.isComplete).length} sessions complete',
            style: const TextStyle(color: AppColors.muted, fontSize: 9),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weekDays.map((day) {
                final fraction = (day.hours / 10).clamp(0.06, 1).toDouble();
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          day.hours == 0
                              ? ''
                              : day.hours.toStringAsFixed(
                                  day.hours.truncateToDouble() == day.hours
                                      ? 0
                                      : 1,
                                ),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: fraction * 52,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: day.hours > 0
                                  ? const [AppColors.cyan, Color(0xFF2756A2)]
                                  : [
                                      Colors.white.withValues(alpha: 0.07),
                                      Colors.white.withValues(alpha: 0.03),
                                    ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.date.weekday -
                              1],
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class LearningTracksPage extends ConsumerWidget {
  const LearningTracksPage({super.key});

  static const _tracks = <_LearningTrack>[
    _LearningTrack(
      'DSA Tracker',
      Icons.account_tree_rounded,
      [11],
      'Track problem-solving practice and review systems-thinking fundamentals.',
    ),
    _LearningTrack(
      'Java Learning',
      Icons.coffee_rounded,
      [1, 2, 3],
      'Java foundations, JVM internals, concurrency and Spring backend engineering.',
    ),
    _LearningTrack('Go Learning', Icons.code_rounded, [
      4,
      5,
    ], 'Idiomatic Go, concurrent services, API design and data persistence.'),
    _LearningTrack(
      'Distributed Systems',
      Icons.hub_rounded,
      [8, 9],
      'Replication, consistency, messaging, delivery guarantees and failure recovery.',
    ),
    _LearningTrack('Projects', Icons.rocket_launch_rounded, [
      10,
    ], 'Build portfolio evidence through platform and backend projects.'),
    _LearningTrack(
      'System Design',
      Icons.schema_rounded,
      [11],
      'Practice architecture, capacity reasoning and clear design communication.',
    ),
    _LearningTrack(
      'Weekly Reports',
      Icons.bar_chart_rounded,
      [],
      'Review completed sessions against the 50-hour weekly target.',
    ),
    _LearningTrack(
      'International Job Preparation',
      Icons.public_rounded,
      [12],
      'Prepare a portfolio, resume, interview plan and international applications.',
    ),
    _LearningTrack(
      'Platform Engineering',
      Icons.cloud_outlined,
      [6, 7, 10],
      'Develop Linux, reliability, containers, Kubernetes and developer platforms.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(learningControllerProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
      children: [
        const Text(
          'LEARNING AREAS',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose a track to inspect milestones and update your progress.',
          style: TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _tracks.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: MediaQuery.sizeOf(context).width > 650 ? 3 : 2,
            mainAxisSpacing: 9,
            crossAxisSpacing: 9,
            childAspectRatio: 1.18,
          ),
          itemBuilder: (context, index) {
            final track = _tracks[index];
            final milestones = state.milestones
                .where((milestone) => track.months.contains(milestone.month))
                .toList();
            final progress = milestones.isEmpty
                ? 0
                : milestones.fold<int>(
                        0,
                        (sum, milestone) => sum + milestone.completion,
                      ) ~/
                      milestones.length;
            return _TrackCard(
              track: track,
              progress: progress,
              onTap: () => _showTrackDetails(context, ref, track),
            );
          },
        ),
        const SizedBox(height: 15),
        const _SamplePlanNote(),
      ],
    );
  }

  Future<void> _showTrackDetails(
    BuildContext context,
    WidgetRef ref,
    _LearningTrack track,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => _TrackDetails(track: track),
    );
  }
}

class _LearningTrack {
  const _LearningTrack(this.title, this.icon, this.months, this.description);

  final String title;
  final IconData icon;
  final List<int> months;
  final String description;
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.progress,
    required this.onTap,
  });

  final _LearningTrack track;
  final int progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${track.title}, $progress percent complete',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: GlassPanel(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(track.icon, color: AppColors.cyan, size: 19),
              const Spacer(),
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 4,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.lime,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$progress%',
                    style: const TextStyle(color: AppColors.lime, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackDetails extends ConsumerWidget {
  const _TrackDetails({required this.track});

  final _LearningTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final milestones = ref
        .watch(learningControllerProvider)
        .milestones
        .where((milestone) => track.months.contains(milestone.month))
        .toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(track.icon, color: AppColors.cyan),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      track.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                track.description,
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 14),
              if (milestones.isEmpty)
                const Expanded(child: _WeeklyReportDetails())
              else
                Expanded(
                  child: ListView(
                    children: milestones.map((milestone) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: GlassPanel(
                          padding: const EdgeInsets.all(13),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MONTH ${milestone.month} · ${milestone.title}',
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${_dateLabel(milestone.startDate)} — ${_dateLabel(milestone.endDate)}',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 9,
                                ),
                              ),
                              Slider(
                                value: milestone.completion.toDouble(),
                                max: 100,
                                divisions: 20,
                                label: '${milestone.completion}%',
                                onChanged: (value) => ref
                                    .read(learningControllerProvider.notifier)
                                    .updateMilestoneProgress(
                                      milestone,
                                      value.round(),
                                    ),
                              ),
                              Wrap(
                                spacing: 5,
                                children: milestone.skills
                                    .map(
                                      (skill) => Chip(
                                        label: Text(skill),
                                        visualDensity: VisualDensity.compact,
                                        labelStyle: const TextStyle(
                                          fontSize: 8,
                                          color: AppColors.cyan,
                                        ),
                                        side: BorderSide(
                                          color: AppColors.cyan.withValues(
                                            alpha: 0.2,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const _SamplePlanNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyReportDetails extends ConsumerWidget {
  const _WeeklyReportDetails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(learningControllerProvider);
    final completed = state.weekTasks
        .where((task) => task.isComplete)
        .fold<int>(0, (total, task) => total + task.durationMinutes);
    final planned = state.weekTasks.fold<int>(
      0,
      (total, task) => total + task.durationMinutes,
    );
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${(completed / 60).toStringAsFixed(1)} hours completed'),
          const SizedBox(height: 6),
          Text(
            '${(planned / 60).toStringAsFixed(1)} hours scheduled · target 50 hours',
            style: const TextStyle(color: AppColors.muted, fontSize: 10),
          ),
          const SizedBox(height: 12),
          ...state.weekTasks.map(
            (task) => CheckboxListTile(
              value: task.isComplete,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${task.startTime} · ${task.subject}'),
              subtitle: Text(task.task),
              onChanged: (value) => ref
                  .read(learningControllerProvider.notifier)
                  .toggleTask(task, value ?? false),
            ),
          ),
        ],
      ),
    );
  }
}

class _SamplePlanNote extends StatelessWidget {
  const _SamplePlanNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.13)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.cyan, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sample roadmap content is editable. Completion and schedule changes are saved locally on this device.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 9,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBackdrop extends StatelessWidget {
  const _DashboardBackdrop();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF12364B),
              Color(0xFF0B1C2D),
              AppColors.background,
            ],
            stops: [0, 0.38, 1],
          ),
        ),
      ),
    );
  }
}

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';

String _monthName(int month) => const [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
][month - 1];

String _formatDuration(int minutes) {
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '${remaining}m';
  return remaining == 0 ? '${hours}h' : '${hours}h ${remaining}m';
}
