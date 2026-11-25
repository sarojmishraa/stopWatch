import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/study_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass_panel.dart';
import '../application/learning_controller.dart';

class RoadmapScreen extends ConsumerStatefulWidget {
  const RoadmapScreen({super.key});

  @override
  ConsumerState<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends ConsumerState<RoadmapScreen> {
  int _selected = 0;
  bool _accessibleList = false;
  double _yaw = 0;
  double _pitch = 0.1;
  double _zoom = 1;
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final learning = ref.watch(learningControllerProvider);
    final milestones = learning.milestones;
    if (milestones.isEmpty && learning.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (learning.error != null) {
      return Center(child: Text('Roadmap could not load: ${learning.error}'));
    }
    if (milestones.isEmpty) {
      return const Center(child: Text('No roadmap milestones are available.'));
    }
    _selected = _selected.clamp(0, milestones.length - 1);
    final selected = milestones[_selected];

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '12-MONTH ROADMAP',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.public_rounded, size: 17),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.view_list_rounded, size: 17),
                ),
              ],
              selected: {_accessibleList},
              onSelectionChanged: (value) =>
                  setState(() => _accessibleList = value.first),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '30 NOV 2026 — 28 NOV 2027 · SAMPLE PLAN',
          style: TextStyle(
            color: AppColors.cyan,
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 15),
        if (_accessibleList)
          _AccessibleMilestoneList(
            milestones: milestones,
            selected: _selected,
            onSelect: (index) => setState(() => _selected = index),
          )
        else
          _GlobeCard(
            milestones: milestones,
            selected: _selected,
            hovered: _hovered,
            yaw: _yaw,
            pitch: _pitch,
            zoom: _zoom,
            onSelect: (index) => setState(() => _selected = index),
            onHover: (index) => setState(() => _hovered = index),
            onRotate: (delta) => setState(() {
              _yaw += delta.dx * 0.008;
              _pitch = (_pitch + delta.dy * 0.008).clamp(-1.1, 1.1);
            }),
            onZoom: (scale) => setState(() {
              _zoom = (_zoom * scale).clamp(0.65, 1.6);
            }),
            onTap: (point, size) {
              final index = _hitMilestone(
                point,
                size,
                milestones.length,
                _yaw,
                _pitch,
                _zoom,
              );
              if (index != null) setState(() => _selected = index);
            },
          ),
        const SizedBox(height: 14),
        _MilestoneDetail(
          milestone: selected,
          onProgressChanged: (progress) {
            ref
                .read(learningControllerProvider.notifier)
                .updateMilestoneProgress(selected, progress.round());
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: milestones.asMap().entries.map((entry) {
            final item = entry.value;
            return ChoiceChip(
              label: Text('M${item.month.toString().padLeft(2, '0')}'),
              selected: entry.key == _selected,
              onSelected: (_) => setState(() => _selected = entry.key),
              selectedColor: AppColors.cyan,
              backgroundColor: AppColors.surface,
              labelStyle: TextStyle(
                color: entry.key == _selected
                    ? AppColors.background
                    : AppColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _GlobeCard extends StatelessWidget {
  const _GlobeCard({
    required this.milestones,
    required this.selected,
    required this.hovered,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.onSelect,
    required this.onHover,
    required this.onRotate,
    required this.onZoom,
    required this.onTap,
  });

  final List<RoadmapMilestone> milestones;
  final int selected;
  final int? hovered;
  final double yaw;
  final double pitch;
  final double zoom;
  final ValueChanged<int> onSelect;
  final ValueChanged<int?> onHover;
  final ValueChanged<Offset> onRotate;
  final ValueChanged<double> onZoom;
  final void Function(Offset point, Size size) onTap;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        children: [
          SizedBox(
            height: 292,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return MouseRegion(
                  onHover: (event) => onHover(
                    _hitMilestone(
                      event.localPosition,
                      size,
                      milestones.length,
                      yaw,
                      pitch,
                      zoom,
                    ),
                  ),
                  onExit: (_) => onHover(null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleUpdate: (details) {
                      if (details.pointerCount == 1) {
                        onRotate(details.focalPointDelta);
                      } else {
                        onZoom(details.scale);
                      }
                    },
                    onTapDown: (details) => onTap(details.localPosition, size),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: size,
                          painter: _RoadmapGlobePainter(
                            milestones: milestones,
                            selected: selected,
                            yaw: yaw,
                            pitch: pitch,
                            zoom: zoom,
                          ),
                        ),
                        if (hovered != null)
                          Positioned(
                            top: 8,
                            left: 10,
                            right: 10,
                            child: IgnorePointer(
                              child: _HoverCard(
                                milestone: milestones[hovered!],
                              ),
                            ),
                          ),
                        const Positioned(
                          bottom: 4,
                          child: Text(
                            'DRAG TO ROTATE  ·  PINCH TO ZOOM  ·  TAP A MILESTONE',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 8,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: () => onZoom(0.9),
                icon: const Icon(Icons.remove_circle_outline, size: 19),
                tooltip: 'Zoom out',
              ),
              Text(
                '${(zoom * 100).round()}%',
                style: const TextStyle(color: AppColors.muted, fontSize: 10),
              ),
              IconButton(
                onPressed: () => onZoom(1.1),
                icon: const Icon(Icons.add_circle_outline, size: 19),
                tooltip: 'Zoom in',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoadmapGlobePainter extends CustomPainter {
  const _RoadmapGlobePainter({
    required this.milestones,
    required this.selected,
    required this.yaw,
    required this.pitch,
    required this.zoom,
  });

  final List<RoadmapMilestone> milestones;
  final int selected;
  final double yaw;
  final double pitch;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 4);
    final baseRadius = math.min(size.width * 0.37, size.height * 0.43);
    final radius = baseRadius * zoom;
    final sphereRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.35),
          radius: 1,
          colors: [Color(0xFF2C6C88), Color(0xFF10263E), Color(0xFF071525)],
          stops: [0, 0.66, 1],
        ).createShader(sphereRect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = AppColors.cyan.withValues(alpha: 0.48),
    );

    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = AppColors.cyan.withValues(alpha: 0.18);
    for (final latitude in [-0.62, -0.3, 0.3, 0.62]) {
      _drawCurve(canvas, center, radius, yaw, pitch, wire, (angle) {
        final ring = math.sqrt(1 - latitude * latitude);
        return (math.cos(angle) * ring, latitude, math.sin(angle) * ring);
      });
    }
    for (var longitude = 0; longitude < 4; longitude++) {
      final angle = longitude * math.pi / 4 + yaw;
      _drawCurve(canvas, center, radius, 0, pitch, wire, (latitude) {
        final ring = math.cos(latitude);
        return (
          math.cos(angle) * ring,
          math.sin(latitude),
          math.sin(angle) * ring,
        );
      });
    }

    final points = _positions(
      center,
      baseRadius,
      milestones.length,
      yaw,
      pitch,
      zoom,
    );
    final order = List.generate(milestones.length, (index) => index)
      ..sort((a, b) => points[a].depth.compareTo(points[b].depth));
    for (final index in order) {
      final point = points[index];
      final front = point.depth > -0.15;
      final selectedNode = index == selected;
      final color = selectedNode
          ? AppColors.lime
          : index % 3 == 0
          ? AppColors.cyan
          : const Color(0xFF9A8BFF);
      final opacity = front ? 1.0 : 0.24;
      if (selectedNode) {
        canvas.drawCircle(
          point.position,
          12,
          Paint()..color = color.withValues(alpha: 0.22 * opacity),
        );
      }
      canvas.drawCircle(
        point.position,
        selectedNode ? 5.2 : 3.8,
        Paint()..color = color.withValues(alpha: opacity),
      );
      if (front) {
        final label = TextPainter(
          text: TextSpan(
            text: '${index + 1}',
            style: TextStyle(
              color: AppColors.text.withValues(alpha: 0.84),
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset(point.position.dx + 6, point.position.dy - 6),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoadmapGlobePainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.zoom != zoom ||
      oldDelegate.milestones != milestones;
}

void _drawCurve(
  Canvas canvas,
  Offset center,
  double radius,
  double yaw,
  double pitch,
  Paint paint,
  (double, double, double) Function(double angle) pointAt,
) {
  final path = Path();
  var started = false;
  for (var step = 0; step <= 80; step++) {
    final angle = step / 80 * math.pi * 2;
    final point = pointAt(angle);
    final projected = _project(
      point.$1,
      point.$2,
      point.$3,
      center,
      radius,
      yaw,
      pitch,
      1,
    );
    if (!started) {
      path.moveTo(projected.position.dx, projected.position.dy);
      started = true;
    } else {
      path.lineTo(projected.position.dx, projected.position.dy);
    }
  }
  canvas.drawPath(path, paint);
}

({Offset position, double depth}) _project(
  double x,
  double y,
  double z,
  Offset center,
  double radius,
  double yaw,
  double pitch,
  double zoom,
) {
  final rotatedX = x * math.cos(yaw) - z * math.sin(yaw);
  final rotatedZ = x * math.sin(yaw) + z * math.cos(yaw);
  final rotatedY = y * math.cos(pitch) - rotatedZ * math.sin(pitch);
  final depth = y * math.sin(pitch) + rotatedZ * math.cos(pitch);
  final perspective = 1 / (1.15 - depth * 0.18);
  return (
    position: Offset(
      center.dx + rotatedX * radius * perspective * zoom,
      center.dy + rotatedY * radius * perspective * zoom,
    ),
    depth: depth,
  );
}

List<({Offset position, double depth})> _positions(
  Offset center,
  double radius,
  int count,
  double yaw,
  double pitch,
  double zoom,
) {
  final goldenAngle = math.pi * (3 - math.sqrt(5));
  return List.generate(count, (index) {
    final y = 1 - (index + 0.5) * 2 / count;
    final ring = math.sqrt(1 - y * y);
    final angle = goldenAngle * index;
    return _project(
      math.cos(angle) * ring,
      y,
      math.sin(angle) * ring,
      center,
      radius,
      yaw,
      pitch,
      zoom,
    );
  });
}

int? _hitMilestone(
  Offset point,
  Size size,
  int count,
  double yaw,
  double pitch,
  double zoom,
) {
  final center = Offset(size.width / 2, size.height / 2 - 4);
  final radius = math.min(size.width * 0.37, size.height * 0.43);
  final positions = _positions(center, radius, count, yaw, pitch, zoom);
  for (var index = positions.length - 1; index >= 0; index--) {
    if ((positions[index].position - point).distance < 19) return index;
  }
  return null;
}

class _HoverCard extends StatelessWidget {
  const _HoverCard({required this.milestone});

  final RoadmapMilestone milestone;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MONTH ${milestone.month} · ${milestone.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${_date(milestone.startDate)} — ${_date(milestone.endDate)} · ${milestone.completion}% · ${milestone.skills.take(3).join(' · ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 8),
          ),
        ],
      ),
    );
  }
}

class _MilestoneDetail extends ConsumerWidget {
  const _MilestoneDetail({
    required this.milestone,
    required this.onProgressChanged,
  });

  final RoadmapMilestone milestone;
  final ValueChanged<double> onProgressChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateRange =
        '${_date(milestone.startDate)} — ${_date(milestone.endDate)}';
    return GlassPanel(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.cyan.withValues(alpha: 0.12),
                  border: Border.all(
                    color: AppColors.cyan.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'M${milestone.month}',
                  style: const TextStyle(
                    color: AppColors.cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      milestone.title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateRange,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${milestone.completion}%',
                style: const TextStyle(
                  color: AppColors.lime,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            milestone.description,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: milestone.skills
                .map(
                  (skill) => Chip(
                    label: Text(skill),
                    backgroundColor: AppColors.cyan.withValues(alpha: 0.08),
                    side: BorderSide(
                      color: AppColors.cyan.withValues(alpha: 0.16),
                    ),
                    labelStyle: const TextStyle(
                      color: AppColors.cyan,
                      fontSize: 9,
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Progress',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
              Expanded(
                child: Slider(
                  value: milestone.completion.toDouble(),
                  max: 100,
                  divisions: 20,
                  onChanged: onProgressChanged,
                ),
              ),
              IconButton(
                tooltip: 'Open learning plan',
                onPressed: () => _showPlan(context, ref, milestone),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                color: AppColors.cyan,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showPlan(
  BuildContext context,
  WidgetRef ref,
  RoadmapMilestone milestone,
) async {
  final tasks = await Future.wait(
    List.generate(
      milestone.endDate.difference(milestone.startDate).inDays + 1,
      (offset) => ref
          .read(learningControllerProvider.notifier)
          .getTasks(milestone.startDate.add(Duration(days: offset))),
    ),
  );
  if (!context.mounted) return;
  final allTasks = tasks.expand((items) => items).toList();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MONTH ${milestone.month} LEARNING PLAN',
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                milestone.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ListView.builder(
                  itemCount: allTasks.length,
                  itemBuilder: (context, index) {
                    final task = allTasks[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        task.isComplete
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: task.isComplete
                            ? AppColors.lime
                            : AppColors.cyan,
                      ),
                      title: Text('${_date(task.date)} · ${task.startTime}'),
                      subtitle: Text('${task.subject} · ${task.task}'),
                    );
                  },
                ),
              ),
              const Text(
                'Sample schedule — replace or reschedule items as your plan evolves.',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AccessibleMilestoneList extends StatelessWidget {
  const _AccessibleMilestoneList({
    required this.milestones,
    required this.selected,
    required this.onSelect,
  });

  final List<RoadmapMilestone> milestones;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: milestones.asMap().entries.map((entry) {
          final item = entry.value;
          return Semantics(
            button: true,
            selected: entry.key == selected,
            label:
                'Month ${item.month}, ${item.title}, ${item.completion} percent complete',
            child: ListTile(
              onTap: () => onSelect(entry.key),
              leading: CircleAvatar(
                backgroundColor: AppColors.cyan.withValues(alpha: 0.12),
                child: Text(
                  '${item.month}',
                  style: const TextStyle(color: AppColors.cyan),
                ),
              ),
              title: Text(item.title),
              subtitle: Text(
                '${item.skills.take(3).join(' · ')} · ${item.completion}%',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          );
        }).toList(),
      ),
    );
  }
}

String _date(DateTime date) =>
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
