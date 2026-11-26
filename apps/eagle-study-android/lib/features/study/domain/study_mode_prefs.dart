/// Do Not Disturb choice for Study Mode. "Total silence" is deliberately not
/// offered: it would also mute the focus timer's completion alarm.
enum DndMode {
  off('Off', 'Notifications behave as usual'),
  alarms('Alarms only', 'Silences everything except alarms (recommended)'),
  priority('Priority only', 'Allows calls and messages you marked as priority');

  const DndMode(this.label, this.description);
  final String label;
  final String description;

  static DndMode parse(String? name) => DndMode.values.firstWhere(
    (m) => m.name == name,
    orElse: () => DndMode.off,
  );
}

class StudyModePrefs {
  const StudyModePrefs({
    this.keepScreenOn = true,
    this.sessionNotification = true,
    this.dnd = DndMode.off,
  });

  /// Keep the screen on while the Study Mode screen is open.
  final bool keepScreenOn;

  /// Ongoing notification with Pause/Resume/Finish while a session runs.
  final bool sessionNotification;

  /// Applied when Study Mode opens, restored when it closes.
  final DndMode dnd;

  StudyModePrefs copyWith({
    bool? keepScreenOn,
    bool? sessionNotification,
    DndMode? dnd,
  }) => StudyModePrefs(
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    sessionNotification: sessionNotification ?? this.sessionNotification,
    dnd: dnd ?? this.dnd,
  );

  Map<String, Object?> toJson() => {
    'keepScreenOn': keepScreenOn,
    'sessionNotification': sessionNotification,
    'dnd': dnd.name,
  };

  factory StudyModePrefs.fromJson(Map<String, dynamic> json) => StudyModePrefs(
    keepScreenOn: json['keepScreenOn'] as bool? ?? true,
    sessionNotification: json['sessionNotification'] as bool? ?? true,
    dnd: DndMode.parse(json['dnd'] as String?),
  );
}
