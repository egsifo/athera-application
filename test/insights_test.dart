import 'package:athera/analytics/sample_store.dart';
import 'package:athera/domain/models.dart';
import 'package:athera/insights/anomaly.dart';
import 'package:athera/insights/baseline.dart';
import 'package:athera/insights/data_quality.dart';
import 'package:athera/insights/insights_report.dart';
import 'package:athera/insights/robust.dart';
import 'package:athera/insights/trends.dart';
import 'package:athera/wellness/check_in.dart';
import 'package:flutter_test/flutter_test.dart';

const hr = Indicator(id: 'hr', label: 'Heart rate', unit: 'bpm', floor: 3, minObservations: 10);
final t0 = DateTime.utc(2030, 1, 1, 12);

List<double> steady(int n, {double base = 60}) => [for (var i = 0; i < n; i++) base + (i % 5) - 2];

void main() {
  group('robust stats', () {
    test('median and MAD', () {
      expect(median([3, 1, 2]), 2);
      expect(median([1, 2, 3, 4]), 2.5);
      expect(madScale([1, 2, 3, 4, 100]), closeTo(1.4826 * 1, 1e-9)); // outlier does not inflate it
    });
    test('slope and pearson', () {
      expect(slope([0, 1, 2], [1, 3, 5]), closeTo(2, 1e-9));
      expect(slope([1, 1], [1, 2]), isNull);
      expect(pearson([1, 2, 3], [2, 4, 6]), closeTo(1, 1e-9));
      expect(pearson([1, 1, 1], [1, 2, 3]), isNull);
    });
  });

  group('PersonalBaseline', () {
    test('refuses to learn from too little data', () {
      expect(PersonalBaseline.compute([60, 61], minObservations: 10, floor: 1), isNull);
    });
    test('floor stops absurd z-scores on a flat history', () {
      final b = PersonalBaseline.compute(List.filled(20, 60.0), minObservations: 10, floor: 3)!;
      expect(b.scale, 3);
      expect(b.z(66), 2);
    });
    test('confidence grows with data and caps at 1', () {
      final a = PersonalBaseline.compute(steady(10), minObservations: 10, floor: 1)!;
      final b = PersonalBaseline.compute(steady(60), minObservations: 10, floor: 1)!;
      expect(a.confidence, lessThan(b.confidence));
      expect(b.confidence, 1);
    });
  });

  group('AnomalyEngine', () {
    const e = AnomalyEngine();
    IndicatorReading r(double now, {List<double>? h, Indicator ind = hr}) => IndicatorReading(ind, h ?? steady(40), now, t0);

    test('a usual value is normal', () => expect(e.check(r(61)).severity, AnomalySeverity.normal));
    test('a far value is flagged', () {
      final c = e.check(r(95));
      expect(c.severity, AnomalySeverity.attention);
      expect(c.z, greaterThan(3.5));
    });
    test('no baseline means no judgement', () {
      final c = e.check(r(95, h: [60, 61]));
      expect(c.hasBaseline, isFalse);
      expect(c.severity, AnomalySeverity.normal);
      expect(e.detect([r(95, h: [60, 61])], now: t0), isEmpty);
    });
    test('direction matters when only one side is concerning', () {
      const spo2 = Indicator(id: 'spo2', label: 'SpO2', unit: '%', floor: 0.5, minObservations: 10, higherIsWorse: false);
      final h = [for (var i = 0; i < 40; i++) 97.0 + (i % 3) * 0.3];
      expect(e.check(IndicatorReading(spo2, h, 99.5, t0)).severity, AnomalySeverity.normal);
      expect(e.check(IndicatorReading(spo2, h, 92, t0)).severity, AnomalySeverity.attention);
    });
    test('two flagged indicators also produce a combined anomaly', () {
      const temp = Indicator(id: 'temp', label: 'Temperature', unit: '°C', floor: 0.15, minObservations: 10);
      final out = e.detect([
        r(95),
        IndicatorReading(temp, [for (var i = 0; i < 40; i++) 36.6 + (i % 3) * 0.1], 38.2, t0),
      ], now: t0);
      expect(out.where((a) => a.kind == AnomalyKind.deviation).length, 2);
      final m = out.singleWhere((a) => a.kind == AnomalyKind.multivariate);
      expect(m.indicators, containsAll(['hr', 'temp']));
      expect(m.explanation, contains('does not tell the cause'));
    });
    test('every anomaly carries the required fields', () {
      final a = e.detect([r(95)], now: t0).single;
      expect(a.baseline['hr'], isNotNull);
      expect(a.deviation['hr'], greaterThan(0));
      expect(a.method, isNotEmpty);
      expect(a.action, isNotEmpty);
      expect(a.confidence, inInclusiveRange(0, 1));
    });
    test('persistent drift needs a full run on one side', () {
      expect(e.persistent(hr, steady(40), [60, 80, 82], t0), isNull);
      final p = e.persistent(hr, steady(40), [60, 80, 82, 85], t0);
      expect(p, isNotNull);
      expect(p!.kind, AnomalyKind.persistent);
    });
  });

  group('DataQualityEngine', () {
    const q = DataQualityEngine();
    final now = t0.add(const Duration(minutes: 5));
    SeriesInput s(String n, List<double> v, {DateTime? end, double lo = 20, double hi = 250}) => SeriesInput(
          name: n,
          times: [for (var i = 0; i < v.length; i++) (end ?? t0).subtract(Duration(minutes: v.length - 1 - i))],
          values: v,
          validMin: lo,
          validMax: hi,
        );

    test('clean fresh data is reliable', () {
      final r = q.assess([s('HR', steady(30)), s('SpO2', [for (var i = 0; i < 30; i++) 97.0 + i % 2], lo: 50, hi: 100)], now: now, required: ['HR', 'SpO2']);
      expect(r.status, QualityStatus.reliable);
      expect(r.aiReliable, isTrue);
    });
    test('missing required data is insufficient and listed', () {
      final r = q.assess([s('HR', steady(30))], now: now, required: ['HR', 'SpO2']);
      expect(r.missing, ['SpO2']);
      expect(r.status, QualityStatus.insufficient);
    });
    test('stale data lowers the score', () {
      final r = q.assess([s('HR', steady(30))], now: t0.add(const Duration(hours: 5)), required: ['HR']);
      expect(r.issues.any((i) => i.message.contains('old')), isTrue);
      expect(r.status, isNot(QualityStatus.reliable));
    });
    test('impossible values and stuck sensors are reported', () {
      final r = q.assess([s('HR', [...steady(10), 400, ...List.filled(9, 70.0)])], now: now, required: ['HR']);
      expect(r.issues.any((i) => i.message.contains('outside')), isTrue);
      expect(r.issues.any((i) => i.message.contains('repeated')), isTrue);
      expect(r.aiReliable, isFalse);
    });
    test('score stays within 0..100', () {
      final r = q.assess([], now: now, required: ['A', 'B', 'C', 'D', 'E']);
      expect(r.score, inInclusiveRange(0, 100));
    });
  });

  group('TrendEngine', () {
    const e = TrendEngine();
    List<TrendPoint> pts(List<double> v) => [for (var i = 0; i < v.length; i++) TrendPoint(t0.add(Duration(days: i)), v[i])];

    test('too few points -> exact insufficient message', () {
      final r = e.analyse('Sleep', pts([7, 7, 7]), higherIsBetter: true, meaningfulPerDay: 0.2, unit: 'h');
      expect(r.direction, TrendDirection.insufficient);
      expect(r.summary, 'Insufficient historical data to establish a reliable trend.');
    });
    test('falling sleep is declining, falling fatigue is improving', () {
      expect(e.analyse('Sleep', pts([8, 7.5, 7, 6.5, 6]), higherIsBetter: true, meaningfulPerDay: 0.2, unit: 'h').direction, TrendDirection.declining);
      expect(e.analyse('Fatigue', pts([4, 3.5, 3, 2.5, 2]), higherIsBetter: false, meaningfulPerDay: 0.15, unit: '/5').direction, TrendDirection.improving);
    });
    test('flat is stable', () {
      expect(e.analyse('Sleep', pts([7, 7.1, 6.9, 7, 7.05]), higherIsBetter: true, meaningfulPerDay: 0.2, unit: 'h').direction, TrendDirection.stable);
    });
  });

  group('InsightsReport', () {
    CheckIn ci(int d, {double sleep = 7, int fatigue = 2}) => CheckIn(
        id: 'c$d', astronautId: 'a', at: t0.subtract(Duration(days: d)), sleepHours: sleep, mood: 3, fatigue: fatigue, stress: 2);

    test('with no data nothing is invented', () {
      final r = InsightsReport.build(InsightsInput(now: t0, vitals: const {}, checkIns: const [], risk: null, simulated: false));
      expect(r.checks, isEmpty);
      expect(r.anomalies, isEmpty);
      expect(r.trends, isEmpty);
      expect(r.explained, isNull);
      expect(r.quality.status, QualityStatus.insufficient);
    });
    test('a sharp drop in sleep is found from check-ins and a declining trend reported', () {
      final list = [ci(0, sleep: 3.5), ci(1, sleep: 6.5), ci(2, sleep: 7), ci(3, sleep: 7.2), ci(4, sleep: 7), ci(5, sleep: 7.1), ci(6, sleep: 6.9)];
      final r = InsightsReport.build(InsightsInput(now: t0, vitals: const {}, checkIns: list, risk: null, simulated: true));
      expect(r.anomalies.any((a) => a.indicators.contains('sleep')), isTrue);
      expect(r.anomalies.every((a) => a.simulated), isTrue);
      expect(r.trends.firstWhere((t) => t.label == 'Sleep').direction, TrendDirection.declining);
    });
    test('vitals: baseline from earlier samples, stale vitals are not judged', () {
      Sample sm(DateTime t, double v) => Sample(t, v, DataQuality.good, t);
      final base = [for (var i = 0; i < 120; i++) sm(t0.subtract(Duration(minutes: 300 - i)), 60.0 + (i % 5) - 2)];
      final high = [...base, sm(t0, 110)];
      final r = InsightsReport.build(InsightsInput(now: t0, vitals: {VitalType.heartRate: high}, checkIns: const [], risk: null, simulated: false));
      expect(r.anomalies.single.indicators, ['hr']);
      final stale = InsightsReport.build(InsightsInput(
          now: t0.add(const Duration(hours: 3)), vitals: {VitalType.heartRate: high}, checkIns: const [], risk: null, simulated: false));
      expect(stale.anomalies, isEmpty);
    });
  });
}
