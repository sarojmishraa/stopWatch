import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/study_calendar.dart';
import '../../../core/widgets/glass_panel.dart';
import '../data/session_repository.dart';
import '../domain/study_session.dart';
import 'session_format.dart';

/// Every saved session, grouped by day in the study timezone.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const _pageSize = 50;

  final _sessions = <StudySessionRecord>[];
  bool _loading = true;
  bool _hasMore = true;
  Object? _error;

  SessionRepository get _repository => ref.read(sessionRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repository.history(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _sessions
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _sessions.isEmpty) return;
    setState(() => _loading = true);
    try {
      final page = await _repository.history(
        limit: _pageSize,
        before: _sessions.last.startedAt,
      );
      if (!mounted) return;
      setState(() {
        _sessions.addAll(page);
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(StudySessionRecord session) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _SessionSheet(session: session),
    );
    if (changed == true) {
      ref.invalidate(studySummaryProvider);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final calendar = ref.watch(studyCalendarProvider);
    final groups = <String, List<StudySessionRecord>>{};
    for (final s in _sessions) {
      groups.putIfAbsent(calendar.dayKey(s.startedAt), () => []).add(s);
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Session history'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: _body(calendar, groups),
      ),
    );
  }

  Widget _body(
    StudyCalendar calendar,
    Map<String, List<StudySessionRecord>> groups,
  ) {
    if (_error != null && _sessions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text("Couldn't load your sessions."),
          const SizedBox(height: 8),
          Text('$_error', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _reload, child: const Text('TRY AGAIN')),
        ],
      );
    }
    if (_loading && _sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_sessions.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: const [
          Icon(Icons.history_rounded, size: 48, color: AppColors.muted),
          SizedBox(height: 12),
          Text(
            'No sessions yet. Finish a stopwatch or focus timer and it will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final entry in groups.entries) ...[
            _DayHeader(
              label: dayLabel(calendar.local(entry.value.first.startedAt)),
              totalSeconds: entry.value.fold(
                0,
                (sum, s) => sum + s.durationSeconds,
              ),
            ),
            for (final s in entry.value)
              _SessionTile(
                session: s,
                calendar: calendar,
                onTap: () => _open(s),
              ),
          ],
          if (_hasMore)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.totalSeconds});

  final String label;
  final int totalSeconds;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            formatDuration(totalSeconds),
            style: const TextStyle(color: AppColors.cyan, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.calendar,
    required this.onTap,
  });

  final StudySessionRecord session;
  final StudyCalendar calendar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = calendar.local(session.startedAt);
    final end = calendar.local(session.endedAt);
    final laps = session.lapsSeconds.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        child: ListTile(
          onTap: onTap,
          leading: Icon(
            session.mode == SessionMode.countdown
                ? Icons.hourglass_bottom_rounded
                : Icons.timer_outlined,
            color: AppColors.cyan,
          ),
          title: Text(
            session.subject ?? 'No subject',
            style: const TextStyle(color: AppColors.text, fontSize: 14),
          ),
          subtitle: Text(
            '${clockTime(start)} – ${clockTime(end)}'
            '${laps > 0 ? ' · $laps lap${laps == 1 ? '' : 's'}' : ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          trailing: Text(
            formatDuration(session.durationSeconds),
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Details, laps, edit subject/notes, delete. Pops `true` if anything changed.
class _SessionSheet extends ConsumerStatefulWidget {
  const _SessionSheet({required this.session});

  final StudySessionRecord session;

  @override
  ConsumerState<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends ConsumerState<_SessionSheet> {
  late String? _subject = widget.session.subject;
  late final _notes = TextEditingController(text: widget.session.notes ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionRepositoryProvider)
          .updateDetails(
            widget.session.id,
            subject: _subject,
            notes: _notes.text,
          );
      if (mounted) Navigator.pop(context, true);
    } on InvalidSessionException catch (e) {
      _fail(e.problems.join(' '));
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this session?'),
        content: Text(
          '${formatDuration(widget.session.durationSeconds)} will be removed '
          'from your totals.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.pink),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(sessionRepositoryProvider).delete(widget.session.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _fail('$e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Couldn't save: $message")));
  }

  @override
  Widget build(BuildContext context) {
    final calendar = ref.watch(studyCalendarProvider);
    final s = widget.session;
    final start = calendar.local(s.startedAt);
    final end = calendar.local(s.endedAt);
    final subjects = {...studySubjects, ?s.subject}.toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatDuration(s.durationSeconds),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${dayLabel(start)} · ${clockTime(start)} – ${clockTime(end)} · '
              '${s.mode == SessionMode.countdown ? 'Focus timer' : 'Stopwatch'}'
              '${s.plannedSeconds != null ? ' (planned ${formatDuration(s.plannedSeconds!)})' : ''}',
              style: const TextStyle(color: AppColors.muted),
            ),
            if (s.lapsSeconds.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'LAPS',
                style: TextStyle(fontSize: 11, letterSpacing: 1.2),
              ),
              for (var i = 0; i < s.lapsSeconds.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(
                        'Lap ${i + 1}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const Spacer(),
                      Text(
                        '+${formatClock(s.lapsSeconds[i] - (i == 0 ? 0 : s.lapsSeconds[i - 1]))}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(width: 16),
                      Text(formatClock(s.lapsSeconds[i])),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 18),
            DropdownButtonFormField<String?>(
              initialValue: _subject,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Subject',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('No subject')),
                for (final subject in subjects)
                  DropdownMenuItem(value: subject, child: Text(subject)),
              ],
              onChanged: _saving ? null : (v) => setState(() => _subject = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              enabled: !_saving,
              maxLength: maxNotesLength,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'What did you cover?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('DELETE'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.pink),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
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
