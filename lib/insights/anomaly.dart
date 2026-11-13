import 'baseline.dart';

/// How far an observation is from the astronaut's own usual pattern.
/// This is NOT a medical severity: only approved threshold rules escalate.
enum AnomalySeverity { normal, unusual, attention }

enum AnomalyKind {
  /// One reading far from the personal baseline.
  deviation,

  /// Several consecutive observations drifting the same way.
  persistent,

  /// Two or more indicators deviating at the same time.
  multivariate,
}

class Indicator {
  const Indicator({
    required this.id,
    required this.label,
    required this.unit,
    required this.floor,
    required this.minObservations,
    this.higherIsWorse,
  });
  final String id, label, unit;
  final double floor;
  final int minObservations;

  /// true: rising is the concerning direction; false: falling is; null: either.
  final bool? higherIsWorse;
}

class IndicatorReading {
  const IndicatorReading(this.indicator, this.history, this.current, this.measuredAt, {this.simulated = false});
  final Indicator indicator;

  /// Earlier observations used to learn the baseline (must not include [current]).
  final List<double> history;
  final double current;
  final DateTime measuredAt;
  final bool simulated;
}

class Anomaly {
  const Anomaly({
    required this.id,
    required this.at,
    required this.kind,
    required this.severity,
    required this.indicators,
    required this.observed,
    required this.baseline,
    required this.deviation,
    required this.method,
    required this.confidence,
    required this.explanation,
    required this.action,
    required this.simulated,
  });
  final String id;
  final DateTime at;
  final AnomalyKind kind;
  final AnomalySeverity severity;
  final List<String> indicators;
  final Map<String, double> observed;
  final Map<String, double> baseline;

  /// Robust z-score per indicator.
  final Map<String, double> deviation;
  final String method;
  final double confidence;
  final String explanation;
  final String action;
  final bool simulated;
}

/// Result for one indicator, including "not enough data" so the UI can say so.
class IndicatorCheck {
  const IndicatorCheck({required this.reading, required this.baseline, required this.z, required this.severity});
  final IndicatorReading reading;
  final PersonalBaseline? baseline;
  final double? z;
  final AnomalySeverity severity;
  bool get hasBaseline => baseline != null;
}

class AnomalyEngine {
  const AnomalyEngine({this.unusualZ = 2.5, this.attentionZ = 3.5});
  final double unusualZ, attentionZ;

  static const methodName = 'Personal robust z-score (median and MAD of own history)';

  IndicatorCheck check(IndicatorReading r) {
    final b = PersonalBaseline.compute(r.history, minObservations: r.indicator.minObservations, floor: r.indicator.floor);
    if (b == null) return IndicatorCheck(reading: r, baseline: null, z: null, severity: AnomalySeverity.normal);
    final z = b.z(r.current);
    final dirOk = switch (r.indicator.higherIsWorse) {
      true => z > 0,
      false => z < 0,
      null => true,
    };
    final a = z.abs();
    final sev = !dirOk
        ? AnomalySeverity.normal
        : a >= attentionZ
            ? AnomalySeverity.attention
            : a >= unusualZ
                ? AnomalySeverity.unusual
                : AnomalySeverity.normal;
    return IndicatorCheck(reading: r, baseline: b, z: z, severity: sev);
  }

  /// Finds anomalies. Needs real history: indicators without a baseline are skipped, never guessed.
  List<Anomaly> detect(List<IndicatorReading> readings, {required DateTime now}) {
    final checks = [for (final r in readings) check(r)];
    final flagged = [for (final c in checks) if (c.severity != AnomalySeverity.normal) c];
    final out = <Anomaly>[];
    for (final c in flagged) {
      final i = c.reading.indicator;
      final dir = c.z! > 0 ? 'higher' : 'lower';
      out.add(Anomaly(
        id: 'dev-${i.id}-${c.reading.measuredAt.millisecondsSinceEpoch}',
        at: c.reading.measuredAt,
        kind: AnomalyKind.deviation,
        severity: c.severity,
        indicators: [i.id],
        observed: {i.id: c.reading.current},
        baseline: {i.id: c.baseline!.median},
        deviation: {i.id: c.z!},
        method: methodName,
        confidence: c.baseline!.confidence,
        explanation: '${i.label} is $dir than your usual pattern: ${_n(c.reading.current)} ${i.unit} '
            'against a personal median of ${_n(c.baseline!.median)} ${i.unit} (${c.baseline!.n} earlier observations).',
        action: c.severity == AnomalySeverity.attention
            ? 'Measure again under the same conditions. If it stays different, tell your crew or the flight surgeon.'
            : 'Note it and re-measure at the next scheduled check.',
        simulated: c.reading.simulated,
      ));
    }
    if (flagged.length >= 2) {
      final worst = flagged.map((c) => c.severity.index).reduce((a, b) => a > b ? a : b);
      out.add(Anomaly(
        id: 'multi-${now.millisecondsSinceEpoch}',
        at: now,
        kind: AnomalyKind.multivariate,
        severity: AnomalySeverity.values[worst],
        indicators: [for (final c in flagged) c.reading.indicator.id],
        observed: {for (final c in flagged) c.reading.indicator.id: c.reading.current},
        baseline: {for (final c in flagged) c.reading.indicator.id: c.baseline!.median},
        deviation: {for (final c in flagged) c.reading.indicator.id: c.z!},
        method: '$methodName, combined',
        confidence: flagged.map((c) => c.baseline!.confidence).reduce((a, b) => a < b ? a : b),
        explanation: '${flagged.length} indicators differ from your usual pattern at the same time: '
            '${flagged.map((c) => c.reading.indicator.label).join(', ')}. Changes together matter more than one alone, '
            'but this does not tell the cause.',
        action: 'Check how you feel and re-measure. Share the brief with the flight surgeon if it continues.',
        simulated: flagged.any((c) => c.reading.simulated),
      ));
    }
    return out;
  }

  /// Persistent drift: the last [run] values all sit on the same side of the baseline beyond [z].
  Anomaly? persistent(Indicator i, List<double> history, List<double> recent, DateTime at, {int run = 3, double z = 1.5, bool simulated = false}) {
    final b = PersonalBaseline.compute(history, minObservations: i.minObservations, floor: i.floor);
    if (b == null || recent.length < run) return null;
    final last = recent.sublist(recent.length - run);
    final zs = [for (final v in last) b.z(v)];
    final up = zs.every((x) => x >= z), down = zs.every((x) => x <= -z);
    if (!up && !down) return null;
    if (i.higherIsWorse == true && down) return null;
    if (i.higherIsWorse == false && up) return null;
    return Anomaly(
      id: 'persist-${i.id}-${at.millisecondsSinceEpoch}',
      at: at,
      kind: AnomalyKind.persistent,
      severity: AnomalySeverity.unusual,
      indicators: [i.id],
      observed: {i.id: last.last},
      baseline: {i.id: b.median},
      deviation: {i.id: zs.last},
      method: '$methodName, $run in a row',
      confidence: b.confidence,
      explanation: '${i.label} has been ${up ? 'above' : 'below'} your usual pattern in the last $run observations '
          '(${last.map(_n).join(', ')} ${i.unit}; your median is ${_n(b.median)} ${i.unit}).',
      action: 'A repeated change is worth attention. Keep measuring and mention it at your next health check.',
      simulated: simulated,
    );
  }

  static String _n(double v) => v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
