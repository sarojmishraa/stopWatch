import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/study_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../application/learning_controller.dart';
import 'sleep_health_card.dart';

enum ScheduleView { day, week, month }

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  ScheduleView _view = ScheduleView.month;
  DateTime _displayMonth = asiaKolkataToday();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(learningControllerProvider);
    final controller = ref.read(learningControllerProvider.notifier);
    final selectedDate = state.selectedDate ?? asiaKolkataToday();
    final tasks = _view == ScheduleView.week ? state.weekTasks : state.dayTasks;
    final completed = state.weekTasks
        .where((task) => task.isComplete)
        .fold<int>(0, (total, task) => total + task.durationMinutes);
    final target = state.weekTasks.fold<int>(
      0,
      (total, task) => total + task.durationMinutes,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'DAILY SCHEDULE',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: () => _addTask(context, state.milestones),
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Add study session',
            ),
          ],
        ),
        const SizedBox(height: 10),
        GlassPanel(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => _moveMonth(-1, selectedDate, controller),
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Previous month',
                  ),
                  Expanded(
                    child: Text(
                      '${_monthName(_displayMonth.month)} ${_displayMonth.year}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _moveMonth(1, selectedDate, controller),
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Next month',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SegmentedButton<ScheduleView>(
                segments: const [
                  ButtonSegment(value: ScheduleView.day, label: Text('DAY')),
                  ButtonSegment(value: ScheduleView.week, label: Text('WEEK')),
                  ButtonSegment(
                    value: ScheduleView.month,
                    label: Text('MONTH'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (value) =>
                    setState(() => _view = value.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  textStyle: WidgetStatePropertyAll(
                    TextStyle(fontSize: 9, letterSpacing: 0.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_view == ScheduleView.month)
                _MonthCalendar(
                  month: _displayMonth,
                  selected: selectedDate,
                  weekTasks: state.calendarTasks,
                  onSelect: controller.selectDate,
                  onToday: () {
                    final today = asiaKolkataToday();
                    setState(() => _displayMonth = today);
                    controller.selectDate(today);
                  },
                )
              else if (_view == ScheduleView.week)
                _WeekStrip(
                  selected: selectedDate,
                  tasks: state.weekTasks,
                  onSelect: controller.selectDate,
                )
              else
                _DayHeading(date: selectedDate),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _WeeklySummary(completedMinutes: completed, plannedMinutes: target),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                _view == ScheduleView.week
                    ? 'THIS WEEK'
                    : _prettyDate(selectedDate),
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${tasks.length} SESSIONS',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 9,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (state.isLoading && tasks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (tasks.isEmpty)
          GlassPanel(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(
                  Icons.event_available,
                  color: AppColors.cyan,
                  size: 28,
                ),
                const SizedBox(height: 10),
                Text(
                  selectedDate.isBefore(DateTime(2026, 11, 30))
                      ? 'Your sample plan begins on 30 November 2026.'
                      : 'No study sessions planned for this date.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _addTask(context, state.milestones),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('ADD A SESSION'),
                ),
              ],
            ),
          )
        else
          ...tasks.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _ScheduleTaskCard(
                task: task,
                onToggle: (value) => controller.toggleTask(task, value),
                onEdit: () => _editTask(context, task),
                onReschedule: () => _rescheduleTask(context, task, controller),
              ),
            ),
          ),
        const SizedBox(height: 16),
        SleepHealthCard(tasks: state.upcomingTasks),
      ],
    );
  }

  void _moveMonth(
    int amount,
    DateTime selectedDate,
    LearningController controller,
  ) {
    final month = DateTime(_displayMonth.year, _displayMonth.month + amount, 1);
    final date = DateTime(
      month.year,
      month.month,
      selectedDate.day
          .clamp(1, DateTime(month.year, month.month + 1, 0).day)
          .toInt(),
    );
    setState(() => _displayMonth = month);
    controller.selectDate(date);
  }

  Future<void> _addTask(
    BuildContext context,
    List<RoadmapMilestone> milestones,
  ) async {
    final result = await showModalBottomSheet<_TaskFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => _TaskForm(milestones: milestones),
    );
    if (result == null || !mounted) return;
    final selected =
        ref.read(learningControllerProvider).selectedDate ?? asiaKolkataToday();
    await ref
        .read(learningControllerProvider.notifier)
        .addTask(
          milestoneId: result.milestoneId,
          date: selected,
          startTime: result.startTime,
          subject: result.subject,
          topic: result.topic,
          durationMinutes: result.durationMinutes,
          description: result.description,
        );
  }

  Future<void> _editTask(BuildContext context, ScheduledStudyTask task) async {
    final result = await showModalBottomSheet<_TaskFormResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => _TaskForm(
        existing: task,
        milestones: ref.read(learningControllerProvider).milestones,
      ),
    );
    if (result == null || !mounted) return;
    await ref
        .read(learningControllerProvider.notifier)
        .editTask(
          task: task,
          startTime: result.startTime,
          durationMinutes: result.durationMinutes,
          description: result.description,
          subject: result.subject,
          topic: result.topic,
        );
  }

  Future<void> _rescheduleTask(
    BuildContext context,
    ScheduledStudyTask task,
    LearningController controller,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate: task.date,
      firstDate: DateTime(2026),
      lastDate: DateTime(2030),
      helpText: 'RESCHEDULE STUDY SESSION',
    );
    if (date != null) await controller.rescheduleTask(task, date);
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.selected,
    required this.weekTasks,
    required this.onSelect,
    required this.onToday,
  });

  final DateTime month;
  final DateTime selected;
  final List<ScheduledStudyTask> weekTasks;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - DateTime.monday;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final count = ((offset + daysInMonth + 6) ~/ 7) * 7;
    final today = asiaKolkataToday();
    return Column(
      children: [
        Row(
          children: const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 9),
                      child: Text(
                        day,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
            childAspectRatio: 0.88,
          ),
          itemBuilder: (context, index) {
            final dayNumber = index - offset + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }
            final date = DateTime(month.year, month.month, dayNumber);
            final isSelected = _sameDay(date, selected);
            final isToday = _sameDay(date, today);
            final isBeforeStart = date.isBefore(DateTime(2026, 11, 30));
            final countForDate = weekTasks
                .where((task) => _sameDay(task.date, date))
                .length;
            return Semantics(
              button: true,
              selected: isSelected,
              label:
                  '${_prettyDate(date)}${countForDate == 0 ? '' : ', $countForDate sessions'}',
              child: InkWell(
                onTap: () => onSelect(date),
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.cyan.withValues(alpha: 0.17)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: isToday ? AppColors.cyan : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNumber',
                        style: TextStyle(
                          color: isBeforeStart
                              ? AppColors.muted.withValues(alpha: 0.45)
                              : isSelected
                              ? AppColors.text
                              : AppColors.muted,
                          fontSize: 12,
                          fontWeight: isToday || isSelected
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      if (countForDate > 0)
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? AppColors.lime : AppColors.cyan,
                          ),
                        )
                      else
                        const SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onToday,
            child: const Text('JUMP TO TODAY'),
          ),
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selected,
    required this.tasks,
    required this.onSelect,
  });

  final DateTime selected;
  final List<ScheduledStudyTask> tasks;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    return Row(
      children: List.generate(7, (index) {
        final date = monday.add(Duration(days: index));
        final count = tasks.where((task) => _sameDay(task.date, date)).length;
        return Expanded(
          child: InkWell(
            onTap: () => onSelect(date),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: _sameDay(date, selected)
                    ? AppColors.cyan.withValues(alpha: 0.17)
                    : Colors.transparent,
                border: Border.all(
                  color: _sameDay(date, asiaKolkataToday())
                      ? AppColors.cyan
                      : Colors.transparent,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                    style: const TextStyle(color: AppColors.muted, fontSize: 9),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${date.day}',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Icon(
                    count > 0 ? Icons.circle : Icons.circle_outlined,
                    color: count > 0 ? AppColors.cyan : Colors.transparent,
                    size: 5,
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.today_rounded, color: AppColors.cyan, size: 18),
        const SizedBox(width: 8),
        Text(
          _prettyDate(date),
          style: const TextStyle(color: AppColors.text, fontSize: 12),
        ),
      ],
    );
  }
}

class _WeeklySummary extends StatelessWidget {
  const _WeeklySummary({
    required this.completedMinutes,
    required this.plannedMinutes,
  });

  final int completedMinutes;
  final int plannedMinutes;

  @override
  Widget build(BuildContext context) {
    final hours = completedMinutes / 60;
    final progress = (hours / 50).clamp(0, 1).toDouble();
    return GlassPanel(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'WEEKLY STUDY TARGET',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)} / 50 h',
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
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(AppColors.lime),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            '${(plannedMinutes / 60).round()} planned hours this week · completed sessions only count toward progress',
            style: const TextStyle(color: AppColors.muted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTaskCard extends StatelessWidget {
  const _ScheduleTaskCard({
    required this.task,
    required this.onToggle,
    required this.onEdit,
    required this.onReschedule,
  });

  final ScheduledStudyTask task;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onReschedule;

  @override
  Widget build(BuildContext context) {
    final today = asiaKolkataToday();
    final overdue = task.date.isBefore(today) && !task.isComplete;
    final upcoming = task.date.isAfter(today) && !task.isComplete;
    final endMinutes =
        (int.parse(task.startTime.substring(0, 2)) * 60 +
            int.parse(task.startTime.substring(3, 5)) +
            task.durationMinutes) %
        (24 * 60);
    final endTime =
        '${(endMinutes ~/ 60).toString().padLeft(2, '0')}:${(endMinutes % 60).toString().padLeft(2, '0')}';
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
      child: Row(
        children: [
          Checkbox(
            value: task.isComplete,
            onChanged: (value) => onToggle(value ?? false),
            activeColor: AppColors.lime,
            checkColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: overdue
                  ? AppColors.pink.withValues(alpha: 0.12)
                  : AppColors.cyan.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  task.startTime,
                  style: TextStyle(
                    color: overdue ? AppColors.pink : AppColors.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  endTime,
                  style: const TextStyle(color: AppColors.muted, fontSize: 8),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        task.subject.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.cyan,
                          fontSize: 8,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (overdue || upcoming) ...[
                      const SizedBox(width: 5),
                      Text(
                        overdue ? 'OVERDUE' : 'UPCOMING',
                        style: TextStyle(
                          color: overdue ? AppColors.pink : AppColors.lime,
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (task.isSample) ...[
                      const SizedBox(width: 5),
                      const Text(
                        'SAMPLE',
                        style: TextStyle(color: AppColors.muted, fontSize: 7),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  task.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${task.task} · ${_formatDuration(task.durationMinutes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 9),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.muted, size: 19),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'date') onReschedule();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit session')),
              PopupMenuItem(value: 'date', child: Text('Reschedule')),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskFormResult {
  const _TaskFormResult({
    required this.milestoneId,
    required this.subject,
    required this.topic,
    required this.startTime,
    required this.durationMinutes,
    required this.description,
  });

  final String milestoneId;
  final String subject;
  final String topic;
  final String startTime;
  final int durationMinutes;
  final String description;
}

class _TaskForm extends StatefulWidget {
  const _TaskForm({required this.milestones, this.existing});

  final List<RoadmapMilestone> milestones;
  final ScheduledStudyTask? existing;

  @override
  State<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<_TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late final _subject = TextEditingController(
    text: widget.existing?.subject ?? '',
  );
  late final _topic = TextEditingController(text: widget.existing?.topic ?? '');
  late final _time = TextEditingController(
    text: widget.existing?.startTime ?? '07:00',
  );
  late final _duration = TextEditingController(
    text: '${widget.existing?.durationMinutes ?? 60}',
  );
  late final _description = TextEditingController(
    text: widget.existing?.task ?? '',
  );
  late String _milestoneId =
      widget.existing?.milestoneId ??
      widget.milestones.firstOrNull?.id ??
      'm01';

  @override
  void dispose() {
    _subject.dispose();
    _topic.dispose();
    _time.dispose();
    _duration.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.existing == null
                      ? 'Add study session'
                      : 'Edit study session',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 15),
                if (widget.existing == null)
                  DropdownButtonFormField<String>(
                    initialValue: _milestoneId,
                    decoration: const InputDecoration(
                      labelText: 'Roadmap milestone',
                    ),
                    items: widget.milestones
                        .map(
                          (milestone) => DropdownMenuItem(
                            value: milestone.id,
                            child: Text(
                              'M${milestone.month} · ${milestone.title}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _milestoneId = value);
                    },
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _subject,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _topic,
                  decoration: const InputDecoration(labelText: 'Topic'),
                  validator: _required,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _time,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'Start (HH:mm)',
                        ),
                        validator: (value) {
                          if (value == null ||
                              !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$')
                                  .hasMatch(value)) {
                            return 'Use 24-hour time';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _duration,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Duration (minutes)',
                        ),
                        validator: (value) {
                          final duration = int.tryParse(value ?? '');
                          return duration == null ||
                                  duration < 1 ||
                                  duration > 720
                              ? 'Enter 1–720'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Task'),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      Navigator.pop(
                        context,
                        _TaskFormResult(
                          milestoneId: _milestoneId,
                          subject: _subject.text.trim(),
                          topic: _topic.text.trim(),
                          startTime: _time.text.trim(),
                          durationMinutes: int.parse(_duration.text),
                          description: _description.text.trim(),
                        ),
                      );
                    },
                    child: const Text('SAVE SESSION'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _prettyDate(DateTime date) =>
    '${date.day} ${_monthName(date.month)} ${date.year}';

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
  final remainder = minutes % 60;
  if (hours == 0) return '${remainder}m';
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}
