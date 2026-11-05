import 'dart:math' as math;

import '../domain/models.dart';
import 'sample_store.dart';

/// Descriptive statistics computed by the app itself. Nothing here is a
/// prediction and nothing here is a diagnosis.
class Summary {
  const Summary({required this.count, this.min, this.max, this.mean, this.latest, this.latestAt});
  final int count;
  final double? min;
  final double? max;
  final double? mean;
  final double? latest;
  final DateTime? latestAt;
  static const empty = Summary(count: 0);
}

Summary summarize(List<Sample> s) {
  if (s.isEmpty) return Summary.empty;
  var mn = s.first.v, mx = s.first.v, sum = 0.0;
  for (final x in s) {
    if (x.v < mn) mn = x.v;
    if (x.v > mx) mx = x.v;
    sum += x.v;
  }
  return Summary(count: s.length, min: mn, max: mx, mean: sum / s.length, latest: s.last.v, latestAt: s.last.t);
}

double? mean(List<Sample> s) => s.isEmpty ? null : s.fold<double>(0, (a, x) => a + x.v) / s.length;

double? stdDev(List<Sample> s) {
  if (s.length < 2) return null;
  final m = mean(s)!;
  final v = s.fold<double>(0, (a, x) => a + (x.v - m) * (x.v - m)) / (s.length - 1);
  return math.sqrt(v);
}

/// Bucket-average to at most [maxPoints] points (keeps charts fast on 24 h).
List<Sample> downsample(List<Sample> s, int maxPoints) {
  if (s.length <= maxPoints || maxPoints < 2) return s;
  final t0 = s.first.t.millisecondsSinceEpoch;
  final span = s.last.t.millisecondsSinceEpoch - t0;
  if (span <= 0) return [s.last];
  final bucketMs = span / maxPoints;
  final out = <Sample>[];
  var i = 0;
  for (var b = 0; b < maxPoints; b++) {
    final end = t0 + (b + 1) * bucketMs;
    var sum = 0.0, n = 0, lastRecv = s[i].receivedAt;
    var tSum = 0.0;
    while (i < s.length && (s[i].t.millisecondsSinceEpoch < end || b == maxPoints - 1)) {
      sum += s[i].v;
      tSum += s[i].t.millisecondsSinceEpoch;
      lastRecv = s[i].receivedAt;
      n++;
      i++;
    }
    if (n > 0) {
      out.add(Sample(DateTime.fromMillisecondsSinceEpoch((tSum / n).round(), isUtc: true), sum / n, DataQuality.good, lastRecv));
    }
    if (i >= s.length) break;
  }
  return out;
}

/// Least-squares slope in units per hour. Null when there is too little data
/// (fewer than [minN] samples or less than [minSpan] covered).
double? slopePerHour(List<Sample> s, {int minN = 5, Duration minSpan = const Duration(minutes: 5)}) {
  if (s.length < minN) return null;
  if (s.last.t.difference(s.first.t) < minSpan) return null;
  final t0 = s.first.t.millisecondsSinceEpoch;
  final xs = [for (final x in s) (x.t.millisecondsSinceEpoch - t0) / 3600000.0];
  final ys = [for (final x in s) x.v];
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var cov = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    cov += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  if (den == 0) return null;
  return cov / den;
}

// ---------------------------------------------------------------------------
// Baseline comparison
// ---------------------------------------------------------------------------
class BaselineComparison {
  const BaselineComparison({
    required this.type,
    required this.baselineMean,
    required this.baselineSd,
    required this.currentMean,
    required this.nBaseline,
    required this.nCurrent,
  });
  final VitalType type;
  final double baselineMean;
  final double? baselineSd;
  final double currentMean;
  final int nBaseline;
  final int nCurrent;

  double get delta => currentMean - baselineMean;
  double? get pct => baselineMean == 0 ? null : delta / baselineMean * 100;

  int get minCurrent => (type == VitalType.systolic || type == VitalType.diastolic) ? 2 : 10;
  int get minBaseline => (type == VitalType.systolic || type == VitalType.diastolic) ? 6 : 10;

  bool get hasEnoughData => nCurrent >= minCurrent && nBaseline >= minBaseline;

  /// A change is reported only when it is (a) backed by enough samples,
  /// (b) practically meaningful for this vital, and (c) larger than twice the
  /// spread seen in the baseline period. Otherwise it is treated as noise.
  bool get isNotable {
    if (!hasEnoughData) return false;
    if (delta.abs() < type.practicalDelta) return false;
    final sd = baselineSd;
    if (sd != null && delta.abs() <= 2 * sd) return false;
    return true;
  }
}

BaselineComparison? compareToBaseline(VitalType type, List<Sample> current, List<Sample> baseline) {
  final cm = mean(current);
  final bm = mean(baseline);
  if (cm == null || bm == null) return null;
  return BaselineComparison(
    type: type,
    baselineMean: bm,
    baselineSd: stdDev(baseline),
    currentMean: cm,
    nBaseline: baseline.length,
    nCurrent: current.length,
  );
}

// ---------------------------------------------------------------------------
// Correlation
// ---------------------------------------------------------------------------
class Correlation {
  const Correlation(this.a, this.b, this.r, this.n);
  final VitalType a;
  final VitalType b;
  final double r;
  final int n;

  String get strength {
    final x = r.abs();
    if (x < 0.3) return 'weak';
    if (x < 0.6) return 'moderate';
    return 'strong';
  }
}

/// Pearson r between two series aligned on 1-minute buckets. Returns null if
/// fewer than [minN] aligned pairs exist or either series is constant.
/// Time series are autocorrelated, so no p-values are reported; r is only a
/// description of association, never evidence of causation.
Correlation? correlate(VitalType a, List<Sample> sa, VitalType b, List<Sample> sb, {int minN = 30}) {
  Map<int, double> bucket(List<Sample> s) {
    final sums = <int, double>{};
    final cnt = <int, int>{};
    for (final x in s) {
      final k = x.t.millisecondsSinceEpoch ~/ 60000;
      sums[k] = (sums[k] ?? 0) + x.v;
      cnt[k] = (cnt[k] ?? 0) + 1;
    }
    return {for (final k in sums.keys) k: sums[k]! / cnt[k]!};
  }

  final ma = bucket(sa), mb = bucket(sb);
  final xs = <double>[], ys = <double>[];
  for (final k in ma.keys) {
    final y = mb[k];
    if (y != null) {
      xs.add(ma[k]!);
      ys.add(y);
    }
  }
  if (xs.length < minN) return null;
  final n = xs.length;
  final mx = xs.reduce((p, q) => p + q) / n;
  final my = ys.reduce((p, q) => p + q) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (xs[i] - mx) * (ys[i] - my);
    sxx += (xs[i] - mx) * (xs[i] - mx);
    syy += (ys[i] - my) * (ys[i] - my);
  }
  if (sxx == 0 || syy == 0) return null;
  return Correlation(a, b, sxy / math.sqrt(sxx * syy), n);
}

// ---------------------------------------------------------------------------
// Data quality
// ---------------------------------------------------------------------------
class QualityReport {
  const QualityReport({
    required this.type,
    required this.coverage,
    required this.gapCount,
    required this.longestGap,
    required this.invalidCount,
    required this.delayedCount,
    required this.sampleCount,
  });
  final VitalType type;

  /// Fraction (0..1) of nominal-interval buckets in the window that contain at
  /// least one valid reading.
  final double coverage;
  final int gapCount;
  final Duration longestGap;
  final int invalidCount;
  final int delayedCount;
  final int sampleCount;

  bool get hasData => sampleCount > 0;
  bool get isPoor => !hasData || coverage < 0.6 || invalidCount >= 3;
  bool get isFair => !isPoor && (coverage < 0.9 || invalidCount > 0 || gapCount > 0);
}

QualityReport assessQuality(
  SampleStore store,
  String astronautId,
  VitalType type,
  Duration window, {
  DateTime? now,
}) {
  final end = (now ?? DateTime.now()).toUtc();
  final start = end.subtract(window);
  final valid = store.between(astronautId, type, start, end.add(const Duration(seconds: 1)));
  final interval = type.nominalIntervalSec;
  final buckets = math.max(1, window.inSeconds ~/ interval);
  final covered = <int>{};
  for (final s in valid) {
    covered.add(s.t.difference(start).inSeconds ~/ interval);
  }
  final gapLimit = Duration(seconds: math.max(interval * 3, 180));
  var gaps = 0;
  var longest = Duration.zero;
  DateTime prev = start;
  for (final s in valid) {
    final g = s.t.difference(prev);
    if (g > gapLimit) gaps++;
    if (g > longest) longest = g;
    prev = s.t;
  }
  final tail = end.difference(prev);
  if (valid.isNotEmpty && tail > gapLimit) gaps++;
  if (tail > longest) longest = tail;
  return QualityReport(
    type: type,
    coverage: (covered.length / buckets).clamp(0.0, 1.0),
    gapCount: gaps,
    longestGap: longest,
    invalidCount: store.invalidCount(astronautId, type, window, now: end),
    delayedCount: store.delayedCount(astronautId, type, window, const Duration(minutes: 2), now: end),
    sampleCount: valid.length,
  );
}
