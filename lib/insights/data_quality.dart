/// Is the data good enough for analysis to be trusted? Transparent, rule-based.
enum QualityStatus { reliable, limited, insufficient }

class SeriesInput {
  const SeriesInput({
    required this.name,
    required this.times,
    required this.values,
    required this.validMin,
    required this.validMax,
    this.expectedIntervalSeconds,
  });
  final String name;

  /// Oldest first.
  final List<DateTime> times;
  final List<double> values;

  /// Physically plausible bounds (sensor faults), not clinical limits.
  final double validMin, validMax;

  /// Nominal sampling interval, when known, to detect gaps.
  final int? expectedIntervalSeconds;
}

class QualityIssue {
  const QualityIssue(this.series, this.message, this.penalty);
  final String series, message;
  final int penalty;
}

class QualityReport {
  const QualityReport({required this.score, required this.status, required this.issues, required this.missing, required this.lastMeasurement});
  final int score;
  final QualityStatus status;
  final List<QualityIssue> issues;
  final List<String> missing;
  final DateTime? lastMeasurement;

  /// Whether the AI risk analysis should be treated as reliable right now.
  bool get aiReliable => status == QualityStatus.reliable;

  String get headline => switch (status) {
        QualityStatus.reliable => 'Data quality: reliable',
        QualityStatus.limited => 'Data quality: limited',
        QualityStatus.insufficient => 'Data quality: insufficient',
      };
}

class DataQualityEngine {
  const DataQualityEngine({this.staleAfter = const Duration(minutes: 30), this.flatlineRun = 8});
  final Duration staleAfter;
  final int flatlineRun;

  QualityReport assess(List<SeriesInput> inputs, {required DateTime now, required List<String> required}) {
    final issues = <QualityIssue>[];
    final missing = <String>[];
    DateTime? last;
    final byName = {for (final s in inputs) s.name: s};

    for (final name in required) {
      final s = byName[name];
      if (s == null || s.values.isEmpty) {
        missing.add(name);
        issues.add(QualityIssue(name, 'no measurement', 25));
      }
    }
    for (final s in inputs) {
      if (s.values.isEmpty) continue;
      if (s.times.length != s.values.length) {
        issues.add(QualityIssue(s.name, 'timestamps and values do not match', 30));
        continue;
      }
      final lastT = s.times.last;
      if (last == null || lastT.isAfter(last)) last = lastT;
      final age = now.difference(lastT);
      if (age > staleAfter) issues.add(QualityIssue(s.name, 'last reading is ${_dur(age)} old', age > staleAfter * 4 ? 25 : 12));
      final bad = s.values.where((v) => !v.isFinite || v < s.validMin || v > s.validMax).length;
      if (bad > 0) issues.add(QualityIssue(s.name, '$bad value${bad == 1 ? '' : 's'} outside the physically possible range', bad > 2 ? 25 : 12));
      var run = 1, maxRun = 1;
      for (var i = 1; i < s.values.length; i++) {
        run = s.values[i] == s.values[i - 1] ? run + 1 : 1;
        if (run > maxRun) maxRun = run;
      }
      if (maxRun >= flatlineRun) issues.add(QualityIssue(s.name, 'same value repeated $maxRun times (stuck sensor?)', 15));
      var outOfOrder = 0;
      for (var i = 1; i < s.times.length; i++) {
        if (!s.times[i].isAfter(s.times[i - 1])) outOfOrder++;
      }
      if (outOfOrder > 0) issues.add(QualityIssue(s.name, '$outOfOrder timestamp${outOfOrder == 1 ? '' : 's'} out of order or repeated', 15));
      final exp = s.expectedIntervalSeconds;
      if (exp != null && s.times.length > 2) {
        var gaps = 0;
        for (var i = 1; i < s.times.length; i++) {
          if (s.times[i].difference(s.times[i - 1]).inSeconds > exp * 3) gaps++;
        }
        if (gaps > 0) issues.add(QualityIssue(s.name, '$gaps gap${gaps == 1 ? '' : 's'} longer than 3x the usual interval', gaps > 3 ? 15 : 8));
      }
    }

    final penalty = issues.fold<int>(0, (a, i) => a + i.penalty);
    final score = (100 - penalty).clamp(0, 100);
    final status = missing.length >= (required.length / 2).ceil() && required.isNotEmpty
        ? QualityStatus.insufficient
        : score >= 80
            ? QualityStatus.reliable
            : score >= 50
                ? QualityStatus.limited
                : QualityStatus.insufficient;
    return QualityReport(score: score, status: status, issues: issues, missing: missing, lastMeasurement: last);
  }

  static String _dur(Duration d) => d.inHours >= 1 ? '${d.inHours} h' : '${d.inMinutes} min';
}
