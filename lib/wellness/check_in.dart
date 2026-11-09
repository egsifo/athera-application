/// A self-reported daily wellbeing check-in (user input, not a sensor reading).
class CheckIn {
  CheckIn({
    required this.id,
    required this.astronautId,
    required this.at,
    required this.sleepHours,
    required this.mood,
    required this.fatigue,
    required this.stress,
    this.glucoseMgDl,
    this.note = '',
    this.isDemo = false,
  });

  final String id;
  final String astronautId;
  final DateTime at;

  /// Hours slept in the last sleep period (0-24).
  final double sleepHours;

  /// 1 = very low ... 5 = very good.
  final int mood;

  /// 1 = not tired ... 5 = exhausted.
  final int fatigue;

  /// 1 = calm ... 5 = very stressed.
  final int stress;

  /// Optional capillary/CGM glucose in mg/dL.
  final double? glucoseMgDl;
  final String note;
  final bool isDemo;

  /// Returns a human-readable problem, or null when the values are plausible.
  static String? validate({
    required double sleepHours,
    required int mood,
    required int fatigue,
    required int stress,
    double? glucoseMgDl,
  }) {
    if (!sleepHours.isFinite || sleepHours < 0 || sleepHours > 24) return 'Sleep must be between 0 and 24 hours.';
    for (final (name, v) in [('Mood', mood), ('Fatigue', fatigue), ('Stress', stress)]) {
      if (v < 1 || v > 5) return '$name must be between 1 and 5.';
    }
    if (glucoseMgDl != null && (!glucoseMgDl.isFinite || glucoseMgDl < 20 || glucoseMgDl > 600)) {
      return 'Blood glucose must be between 20 and 600 mg/dL (check the reading).';
    }
    return null;
  }

  /// Calendar day (local) as yyyy-mm-dd; used to find "today's" check-in.
  String get day => dayKey(at);

  Map<String, Object?> toJson() => {
        'id': id,
        'astronaut_id': astronautId,
        'at': at.toUtc().toIso8601String(),
        'sleep_hours': sleepHours,
        'mood': mood,
        'fatigue': fatigue,
        'stress': stress,
        if (glucoseMgDl != null) 'glucose_mg_dl': glucoseMgDl,
        'note': note,
        'is_demo': isDemo,
      };

  factory CheckIn.fromJson(Map<String, Object?> m) => CheckIn(
        id: m['id'] as String,
        astronautId: m['astronaut_id'] as String,
        at: DateTime.parse(m['at'] as String).toUtc(),
        sleepHours: (m['sleep_hours'] as num).toDouble(),
        mood: (m['mood'] as num).toInt(),
        fatigue: (m['fatigue'] as num).toInt(),
        stress: (m['stress'] as num).toInt(),
        glucoseMgDl: (m['glucose_mg_dl'] as num?)?.toDouble(),
        note: (m['note'] as String?) ?? '',
        isDemo: m['is_demo'] == true,
      );
}

String dayKey(DateTime t) {
  final l = t.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}
