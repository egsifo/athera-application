import '../analytics/insights.dart';
import '../analytics/sample_store.dart';
import '../analytics/stats.dart';
import '../domain/ai_models.dart';
import '../domain/models.dart';

/// Turns locally stored measurements into AI request payloads. Pure data
/// preparation: contains no inference logic.
class AiInputBuilder {
  const AiInputBuilder();

  /// [windowSize] rows of [intervalSec]-second bucket means ending at the last
  /// complete bucket before [now]. Buckets without data keep null values;
  /// nothing is interpolated or filled in.
  List<MeasurementDto> window(SampleStore store, String id, DateTime now, int windowSize, int intervalSec) {
    final nowUtc = now.toUtc();
    final endSec = (nowUtc.millisecondsSinceEpoch ~/ 1000) ~/ intervalSec * intervalSec;
    final out = <MeasurementDto>[];
    for (var i = 0; i < windowSize; i++) {
      final bEnd = DateTime.fromMillisecondsSinceEpoch(
        (endSec - (windowSize - 1 - i) * intervalSec) * 1000,
        isUtc: true,
      );
      final bStart = bEnd.subtract(Duration(seconds: intervalSec));
      final values = <VitalType, double?>{};
      for (final t in VitalType.values) {
        values[t] = mean(store.between(id, t, bStart, bEnd));
      }
      out.add(MeasurementDto(bEnd, values));
    }
    return out;
  }

  /// Fraction of window rows with at least one forecastable vital.
  double completeness(List<MeasurementDto> w) {
    if (w.isEmpty) return 0;
    final filled = w.where((m) => m.values.entries.any((e) => e.key.isForecastable && e.value != null)).length;
    return filled / w.length;
  }

  /// Latest valid reading per vital (blood pressure may be up to 30 min old,
  /// everything else up to 5 min); older values are reported as null.
  MeasurementDto current(SampleStore store, String id, DateTime now) {
    final n = now.toUtc();
    final values = <VitalType, double?>{};
    for (final t in VitalType.values) {
      final s = store.latest(id, t);
      final maxAge = t.nominalIntervalSec > 60 ? const Duration(minutes: 30) : const Duration(minutes: 5);
      values[t] = (s != null && n.difference(s.t) <= maxAge) ? s.v : null;
    }
    return MeasurementDto(n, values);
  }

  /// Descriptive features computed by the app (15-minute window). The model
  /// owner decides which of these are used; see AI_INTEGRATION.md.
  Map<String, double?> features(SampleStore store, String id, DateTime now) {
    final n = now.toUtc();
    const w = Duration(minutes: 15);
    final base = baselineFor(store, id, w, now: n);
    final out = <String, double?>{};
    for (final t in VitalType.values) {
      final cur = store.series(id, t, within: w, now: n);
      final s = summarize(cur);
      final k = t.apiField;
      out['${k}_mean_15m'] = s.mean;
      out['${k}_min_15m'] = s.min;
      out['${k}_max_15m'] = s.max;
      out['${k}_slope_per_hour_15m'] = slopePerHour(cur, minN: t.nominalIntervalSec > 60 ? 3 : 5);
      final cmp = base == null ? null : compareToBaseline(t, cur, store.between(id, t, base.from, base.to));
      out['${k}_delta_vs_baseline'] = cmp?.delta;
    }
    return out;
  }
}
