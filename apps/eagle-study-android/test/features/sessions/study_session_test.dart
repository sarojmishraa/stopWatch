import 'package:eagle_study/features/sessions/domain/study_session.dart';
import 'package:flutter_test/flutter_test.dart';

StudySessionRecord record({
  int duration = 600,
  Duration span = const Duration(minutes: 15),
  List<int> laps = const [],
  int? planned,
  String device = 'android-test',
}) {
  final start = DateTime.utc(2026, 12, 1, 4);
  return StudySessionRecord(
    id: '0b8c7f7e-1d1b-4c8e-9d3c-3a9a2f8d1e01',
    mode: SessionMode.stopwatch,
    startedAt: start,
    endedAt: start.add(span),
    durationSeconds: duration,
    plannedSeconds: planned,
    lapsSeconds: laps,
    sourceDevice: device,
    clientUpdatedAt: start.add(span),
  );
}

void main() {
  test('a normal session is valid', () {
    expect(record(laps: [120, 300]).validate(), isEmpty);
  });

  test('mirrors the server rules', () {
    expect(record(duration: 0).validate(), isNotEmpty);
    expect(
      record(duration: 86401, span: const Duration(days: 2)).validate(),
      isNotEmpty,
    );
    expect(
      record(duration: 1200).validate(),
      isNotEmpty,
      reason: 'focus > wall time',
    );
    expect(record(span: const Duration(minutes: -1)).validate(), isNotEmpty);
    expect(
      record(laps: [300, 100]).validate(),
      isNotEmpty,
      reason: 'laps out of order',
    );
    expect(
      record(laps: [700]).validate(),
      isNotEmpty,
      reason: 'lap after the end',
    );
    expect(record(planned: 0).validate(), isNotEmpty);
    expect(record(device: ' ').validate(), isNotEmpty);
  });

  test(
    'API body has exactly the fields PUT /v1/study-sessions/{id} accepts',
    () {
      expect(record().toApiJson().keys.toSet(), {
        'mode',
        'startedAt',
        'endedAt',
        'durationSeconds',
        'plannedSeconds',
        'subject',
        'notes',
        'lapsSeconds',
        'sourceDevice',
        'clientUpdatedAt',
      });
      expect(record().toApiJson()['startedAt'], '2026-12-01T04:00:00.000Z');
    },
  );
}
