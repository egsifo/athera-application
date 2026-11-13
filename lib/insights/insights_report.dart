import '../analytics/sample_store.dart';
import '../domain/ai_models.dart';
import '../domain/models.dart';
import '../wellness/check_in.dart';
import 'anomaly.dart';
import 'data_quality.dart';
import 'trends.dart';

class InsightsInput {
  const InsightsInput({
    required this.now,
    required this.vitals,
    required this.checkIns,
    required this.risk,
    required this.simulated,
  });
  final DateTime now;

  /// Last days of samples per vital (all qualities), oldest first.
  final Map<VitalType, List<Sample>> vitals;

  /// Newest first.
  final List<CheckIn> checkIns;
  final RiskResult? risk;
  final bool simulated;
}

class ExplainedRisk {
  const ExplainedRisk({required this.reasons, required this.caveats, required this.reliable});
  final List<String> reasons;
  final List<String> caveats;
  final bool reliable;
}

class InsightsReport {
  InsightsReport({
    required this.quality,
    required this.checks,
    required this.anomalies,
    required this.trends,
    required this.explained,
    required this.simulated,
  });
  final QualityReport quality;
  final List<IndicatorCheck> checks;
  final List<Anomaly> anomalies;
  final List<TrendResult> trends;
  final ExplainedRisk? explained;
  final bool simulated;

  static const _vitalIndicators = <VitalType, Indicator>{
    VitalType.heartRate: Indicator(id: 'hr', label: 'Heart rate', unit: 'bpm', floor: 3, minObservations: 30),
    VitalType.spo2: Indicator(id: 'spo2', label: 'Blood oxygen', unit: '%', floor: 0.5, minObservations: 30, higherIsWorse: false),
    VitalType.temperature: Indicator(id: 'temp', label: 'Temperature', unit: '°C', floor: 0.15, minObservations: 30),
    VitalType.respiratoryRate: Indicator(id: 'rr', label: 'Respiratory rate', unit: '/min', floor: 1, minObservations: 30),
    VitalType.systolic: Indicator(id: 'sys', label: 'Systolic pressure', unit: 'mmHg', floor: 4, minObservations: 30),
    VitalType.diastolic: Indicator(id: 'dia', label: 'Diastolic pressure', unit: 'mmHg', floor: 3, minObservations: 30),
  };

  static const _range = <VitalType, (double, double)>{
    VitalType.heartRate: (20, 250),
    VitalType.spo2: (50, 100),
    VitalType.temperature: (30, 44),
    VitalType.respiratoryRate: (2, 80),
    VitalType.systolic: (50, 280),
    VitalType.diastolic: (25, 180),
  };

  static const _required = [VitalType.heartRate, VitalType.spo2, VitalType.temperature];

  static const _sleep = Indicator(id: 'sleep', label: 'Sleep', unit: 'h', floor: 0.5, minObservations: 4, higherIsWorse: false);
  static const _fatigue = Indicator(id: 'fatigue', label: 'Fatigue', unit: '/5', floor: 0.5, minObservations: 4, higherIsWorse: true);
  static const _mood = Indicator(id: 'mood', label: 'Mood', unit: '/5', floor: 0.5, minObservations: 4, higherIsWorse: false);
  static const _stress = Indicator(id: 'stress', label: 'Stress', unit: '/5', floor: 0.5, minObservations: 4, higherIsWorse: true);

  static InsightsReport build(InsightsInput i, {AnomalyEngine engine = const AnomalyEngine()}) {
    final dq = const DataQualityEngine();
    final series = <SeriesInput>[];
    final readings = <IndicatorReading>[];

    for (final e in _vitalIndicators.entries) {
      final all = i.vitals[e.key] ?? const <Sample>[];
      if (all.isEmpty) continue;
      final (lo, hi) = _range[e.key]!;
      series.add(SeriesInput(
        name: e.value.label,
        times: [for (final s in all) s.t],
        values: [for (final s in all) s.v],
        validMin: lo,
        validMax: hi,
      ));
      final usable = [for (final s in all) if (s.usable && s.v >= lo && s.v <= hi) s];
      if (usable.isEmpty) continue;
      final latest = usable.last;
      if (i.now.difference(latest.t) > dq.staleAfter) continue; // stale: quality report says so, no anomaly on old data
      final cutoff = latest.t.subtract(const Duration(hours: 1));
      final history = [for (final s in usable) if (s.t.isBefore(cutoff)) s.v];
      readings.add(IndicatorReading(e.value, history, latest.v, latest.t, simulated: i.simulated));
    }

    final quality = dq.assess(series, now: i.now, required: [for (final t in _required) _vitalIndicators[t]!.label]);

    final anomalies = <Anomaly>[];
    final checks = <IndicatorCheck>[for (final r in readings) engine.check(r)];
    anomalies.addAll(engine.detect(readings, now: i.now));

    final trends = <TrendResult>[];
    final ci = i.checkIns;
    if (ci.isNotEmpty) {
      final newest = ci.first;
      final older = ci.skip(1).toList();
      final chron = ci.reversed.toList();
      final defs = <(Indicator, double Function(CheckIn), bool, double)>[
        (_sleep, (c) => c.sleepHours, true, 0.2),
        (_fatigue, (c) => c.fatigue.toDouble(), false, 0.15),
        (_mood, (c) => c.mood.toDouble(), true, 0.15),
        (_stress, (c) => c.stress.toDouble(), false, 0.15),
      ];
      for (final (ind, f, higherBetter, meaningful) in defs) {
        final r = IndicatorReading(ind, [for (final c in older) f(c)], f(newest), newest.at, simulated: i.simulated);
        final chk = engine.check(r);
        checks.add(chk);
        anomalies.addAll(engine.detect([r], now: i.now));
        final recent = [for (final c in chron) f(c)];
        final p = engine.persistent(ind, [for (final c in older.skip(3)) f(c)], recent, newest.at, simulated: i.simulated);
        if (p != null) anomalies.add(p);
        trends.add(const TrendEngine().analyse(
          ind.label,
          [for (final c in chron) TrendPoint(c.at, f(c))],
          higherIsBetter: higherBetter,
          meaningfulPerDay: meaningful,
          unit: ind.unit,
        ));
      }
    }

    // Keep one entry per id, newest first.
    final seen = <String>{};
    anomalies.sort((a, b) => b.at.compareTo(a.at));
    final unique = [for (final a in anomalies) if (seen.add(a.id)) a];

    ExplainedRisk? explained;
    final r = i.risk;
    if (r != null) {
      final caveats = <String>[
        if (!quality.aiReliable) 'Data quality is ${quality.status.name}, so treat this prediction with extra caution.',
        if (r.inputSimulated) 'Some model inputs are simulated demo values, not sensor measurements.',
        if (r.contributingFeatures.isEmpty) 'The model did not report which factors drove this result.',
      ];
      explained = ExplainedRisk(
        reasons: [for (final f in r.contributingFeatures) f.feature],
        caveats: caveats,
        reliable: quality.aiReliable && !r.inputSimulated,
      );
    }

    return InsightsReport(quality: quality, checks: checks, anomalies: unique, trends: trends, explained: explained, simulated: i.simulated);
  }
}
