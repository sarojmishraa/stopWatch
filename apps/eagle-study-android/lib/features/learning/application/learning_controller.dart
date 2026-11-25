import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/study_database.dart';
import '../../../core/providers.dart';

final learningControllerProvider =
    NotifierProvider<LearningController, LearningState>(LearningController.new);

DateTime asiaKolkataToday([DateTime? instant]) {
  final indiaTime = (instant ?? DateTime.now()).toUtc().add(
    const Duration(hours: 5, minutes: 30),
  );
  return DateTime(indiaTime.year, indiaTime.month, indiaTime.day);
}

Duration? minimumOvernightRest(List<ScheduledStudyTask> tasks) {
  if (tasks.length < 2) return null;
  final sessions = tasks.map((task) {
    final parts = task.startTime.split(':').map(int.parse).toList();
    final start = DateTime(
      task.date.year,
      task.date.month,
      task.date.day,
      parts[0],
      parts[1],
    );
    return (
      start: start,
      end: start.add(Duration(minutes: task.durationMinutes)),
    );
  }).toList()..sort((a, b) => a.start.compareTo(b.start));
  Duration? minimum;
  for (var index = 0; index < sessions.length - 1; index++) {
    final previous = sessions[index];
    final next = sessions[index + 1];
    final crossesDate =
        previous.start.year != next.start.year ||
        previous.start.month != next.start.month ||
        previous.start.day != next.start.day;
    if (!crossesDate) continue;
    final gap = next.start.difference(previous.end);
    if (minimum == null || gap < minimum) minimum = gap;
  }
  return minimum;
}

class LearningState {
  const LearningState({
    this.isLoading = true,
    this.error,
    this.milestones = const [],
    this.selectedDate,
    this.dayTasks = const [],
    this.weekTasks = const [],
    this.upcomingTasks = const [],
    this.calendarTasks = const [],
  });

  final bool isLoading;
  final Object? error;
  final List<RoadmapMilestone> milestones;
  final DateTime? selectedDate;
  final List<ScheduledStudyTask> dayTasks;
  final List<ScheduledStudyTask> weekTasks;
  final List<ScheduledStudyTask> upcomingTasks;
  final List<ScheduledStudyTask> calendarTasks;

  LearningState copyWith({
    bool? isLoading,
    Object? error,
    bool clearError = false,
    List<RoadmapMilestone>? milestones,
    DateTime? selectedDate,
    List<ScheduledStudyTask>? dayTasks,
    List<ScheduledStudyTask>? weekTasks,
    List<ScheduledStudyTask>? upcomingTasks,
    List<ScheduledStudyTask>? calendarTasks,
  }) {
    return LearningState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
      milestones: milestones ?? this.milestones,
      selectedDate: selectedDate ?? this.selectedDate,
      dayTasks: dayTasks ?? this.dayTasks,
      weekTasks: weekTasks ?? this.weekTasks,
      upcomingTasks: upcomingTasks ?? this.upcomingTasks,
      calendarTasks: calendarTasks ?? this.calendarTasks,
    );
  }
}

class LearningController extends Notifier<LearningState> {
  StudyDatabase get _database => ref.read(studyDatabaseProvider);

  @override
  LearningState build() {
    unawaited(_load());
    return LearningState(selectedDate: asiaKolkataToday());
  }

  Future<void> _load() async {
    try {
      final milestones = await _database.loadMilestones();
      await _loadDate(state.selectedDate ?? asiaKolkataToday(), milestones);
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(isLoading: false, error: error);
      }
    }
  }

  Future<void> selectDate(DateTime date) async {
    final selected = DateTime(date.year, date.month, date.day);
    state = state.copyWith(selectedDate: selected, isLoading: true);
    try {
      await _loadDate(selected, state.milestones);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<List<ScheduledStudyTask>> getTasks(DateTime date) =>
      _database.loadTasks(date);

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  Future<void> _loadDate(
    DateTime date,
    List<RoadmapMilestone> milestones,
  ) async {
    final monday = date.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
    final sunday = monday.add(const Duration(days: 6));
    final dayTasks = await _database.loadTasks(date);
    final weekTasks = await _database.loadTasksBetween(monday, sunday);
    final upcomingTasks = await _database.loadTasksBetween(
      date,
      date.add(const Duration(days: 13)),
    );
    final monthStart = DateTime(date.year, date.month);
    final calendarTasks = await _database.loadTasksBetween(
      monthStart,
      DateTime(date.year, date.month + 1, 0),
    );
    if (!ref.mounted) return;
    state = state.copyWith(
      isLoading: false,
      clearError: true,
      milestones: milestones,
      selectedDate: date,
      dayTasks: dayTasks,
      weekTasks: weekTasks,
      upcomingTasks: upcomingTasks,
      calendarTasks: calendarTasks,
    );
  }

  Future<void> toggleTask(ScheduledStudyTask task, bool isComplete) async {
    await _database.updateTaskCompletion(task.id, isComplete);
    await refresh();
  }

  Future<void> rescheduleTask(ScheduledStudyTask task, DateTime date) async {
    await _database.rescheduleTask(task.id, date);
    await refresh();
  }

  Future<void> editTask({
    required ScheduledStudyTask task,
    required String startTime,
    required int durationMinutes,
    required String description,
    required String subject,
    required String topic,
  }) async {
    await _database.updateTask(
      id: task.id,
      startTime: startTime,
      durationMinutes: durationMinutes,
      task: description,
      subject: subject,
      topic: topic,
    );
    await refresh();
  }

  Future<void> addTask({
    required String milestoneId,
    required DateTime date,
    required String startTime,
    required String subject,
    required String topic,
    required int durationMinutes,
    required String description,
  }) async {
    await _database.addTask(
      milestoneId: milestoneId,
      date: date,
      startTime: startTime,
      subject: subject,
      topic: topic,
      durationMinutes: durationMinutes,
      task: description,
    );
    await refresh();
  }

  Future<void> updateMilestoneProgress(
    RoadmapMilestone milestone,
    int progress,
  ) async {
    await _database.updateMilestoneCompletion(milestone.id, progress);
    await refresh();
  }
}
