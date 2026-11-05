import '../core/format.dart';
import '../domain/models.dart';
import 'sample_store.dart';
import 'stats.dart';

enum InsightKind { baselineChange, rateOfChange, dataQuality }

/// A factual statement computed by the app from measured data. Always
/// descriptive: no insight claims a cause or a medical condition.
class Insight {
  const Insight(this.kind, this.vital, this.title, this.detail, {this.severityHint = 0});
  final InsightKind kind;
  final VitalType vital;
  final String title;
  final String detail;

  /// 0 = informational, 1 = worth a look. Not a clinical severity.
  final int severityHint;
}

class BaselineInfo {
  const BaselineInfo(this.from, this.to);
  final DateTime from;
  final DateTime to;
}

/// The baseline is the FIRST 6 HOURS of stored data for that astronaut (the
/// individual's own established reference). Returns null if the stored history
/// is too short for the baseline not to overlap the comparison window.
BaselineInfo? baselineFor(SampleStore store, String astronautId, Duration window, {DateTime? now}) {
  final first = store.firstSeen(astronautId);
  if (first == null) return null;
  final to = first.add(const Duration(hours: 6));
  final windowStart = (now ?? DateTime.now()).toUtc().subtract(window);
  if (windowStart.isBefore(to)) return null;
  return BaselineInfo(first, to);
}

class BaselineRow {
  const BaselineRow(this.type, this.comparison, this.slopePerHour);
  final VitalType type;
  final BaselineComparison? comparison;
  final double? slopePerHour;
}

List<BaselineRow> baselineRows(SampleStore store, String astronautId, Duration window, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toUtc();
  final base = baselineFor(store, astronautId, window, now: n);
  final rows = <BaselineRow>[];
  for (final t in VitalType.values) {
    final cur = store.series(astronautId, t, within: window, now: n);
    final cmp = base == null ? null : compareToBaseline(t, cur, store.between(astronautId, t, base.from, base.to));
    rows.add(BaselineRow(t, cmp, slopePerHour(cur, minN: t.nominalIntervalSec > 60 ? 3 : 5)));
  }
  return rows;
}

List<Insight> buildInsights(SampleStore store, String astronautId, Duration window, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toUtc();
  final out = <Insight>[];
  final windowLabel = fmtDuration(window);

  for (final row in baselineRows(store, astronautId, window, now: n)) {
    final t = row.type;
    final c = row.comparison;
    if (c != null && c.isNotable) {
      final up = c.delta > 0;
      final pct = c.pct == null ? '' : ', ${c.pct! >= 0 ? '+' : ''}${c.pct!.toStringAsFixed(0)}%';
      out.add(Insight(
        InsightKind.baselineChange,
        t,
        '${t.label} has ${up ? 'increased' : 'decreased'} relative to the baseline',
        '${fmtNum(c.baselineMean, t == VitalType.temperature ? 2 : 1)} → ${fmtNum(c.currentMean, t == VitalType.temperature ? 2 : 1)} ${t.unit} '
        '(${c.delta >= 0 ? '+' : ''}${fmtNum(c.delta, t == VitalType.temperature ? 2 : 1)}$pct). '
        'Mean of the last $windowLabel (${c.nCurrent} readings) vs the first 6 h of stored data (${c.nBaseline} readings).',
        severityHint: 1,
      ));
    }
    final slope = row.slopePerHour;
    if (slope != null) {
      final changeOverWindow = slope * window.inMinutes / 60.0;
      if (changeOverWindow.abs() >= t.practicalDelta) {
        out.add(Insight(
          InsightKind.rateOfChange,
          t,
          '${t.label} is ${slope > 0 ? 'rising' : 'falling'} over the last $windowLabel',
          'Linear trend ≈ ${slope >= 0 ? '+' : ''}${slope.toStringAsFixed(t == VitalType.temperature ? 2 : 1)} ${t.unit} per hour.',
        ));
      }
    }
    final q = assessQuality(store, astronautId, t, window, now: n);
    if (q.hasData && q.coverage < 0.8) {
      out.add(Insight(
        InsightKind.dataQuality,
        t,
        '${t.label}: incomplete data',
        'Only ${(q.coverage * 100).round()}% of expected readings arrived in the last $windowLabel '
        '(longest gap ${fmtDuration(q.longestGap)}). Insights for this vital may be less reliable.',
      ));
    }
    if (q.invalidCount > 0) {
      out.add(Insight(
        InsightKind.dataQuality,
        t,
        '${t.label}: ${q.invalidCount} invalid reading(s) excluded',
        'Values outside the physically plausible sensor range were ignored in all statistics.',
      ));
    }
  }
  return out;
}

/// Standard pairs examined for association.
const correlationPairs = <(VitalType, VitalType)>[
  (VitalType.heartRate, VitalType.respiratoryRate),
  (VitalType.heartRate, VitalType.spo2),
  (VitalType.respiratoryRate, VitalType.spo2),
  (VitalType.heartRate, VitalType.temperature),
];

List<Correlation> buildCorrelations(SampleStore store, String astronautId, {Duration window = const Duration(hours: 6), DateTime? now}) {
  final n = (now ?? DateTime.now()).toUtc();
  final out = <Correlation>[];
  for (final (a, b) in correlationPairs) {
    final c = correlate(
      a,
      store.series(astronautId, a, within: window, now: n),
      b,
      store.series(astronautId, b, within: window, now: n),
    );
    if (c != null) out.add(c);
  }
  return out;
}
