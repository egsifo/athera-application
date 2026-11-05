import 'package:athera/analytics/sample_store.dart';
import 'package:athera/analytics/stats.dart';
import 'package:athera/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Sample s(DateTime t, double v) => Sample(t, v, DataQuality.good, t);

void main() {
  final t0 = DateTime.utc(2026, 10, 19, 12);

  test('summarize reports min, max, mean and latest', () {
    final r = summarize([s(t0, 60), s(t0.add(const Duration(minutes: 1)), 80), s(t0.add(const Duration(minutes: 2)), 70)]);
    expect(r.count, 3);
    expect(r.min, 60);
    expect(r.max, 80);
    expect(r.mean, closeTo(70, 1e-9));
    expect(r.latest, 70);
    expect(summarize(const []).count, 0);
  });

  test('slopePerHour recovers a known linear trend and refuses tiny samples', () {
    final rising = [for (var i = 0; i < 30; i++) s(t0.add(Duration(minutes: i)), 60 + 0.5 * i)];
    expect(slopePerHour(rising), closeTo(30, 0.01));
    expect(slopePerHour(rising.take(3).toList()), isNull);
  });

  test('baseline comparison only calls a change notable when large and backed by data', () {
    final base = [for (var i = 0; i < 20; i++) s(t0.add(Duration(minutes: i)), 60 + (i.isEven ? 1 : -1))];
    final up = [for (var i = 0; i < 20; i++) s(t0.add(Duration(hours: 8, minutes: i)), 75)];
    final same = [for (var i = 0; i < 20; i++) s(t0.add(Duration(hours: 8, minutes: i)), 61)];
    expect(compareToBaseline(VitalType.heartRate, up, base)!.isNotable, isTrue);
    expect(compareToBaseline(VitalType.heartRate, same, base)!.isNotable, isFalse);
    // Too few current samples: never notable.
    expect(compareToBaseline(VitalType.heartRate, up.take(3).toList(), base)!.isNotable, isFalse);
  });

  test('correlate finds association, and returns null for constant or short series', () {
    final a = [for (var i = 0; i < 40; i++) s(t0.add(Duration(minutes: i)), 60.0 + i)];
    final b = [for (var i = 0; i < 40; i++) s(t0.add(Duration(minutes: i)), 14.0 + i * 0.1)];
    final c = correlate(VitalType.heartRate, a, VitalType.respiratoryRate, b);
    expect(c, isNotNull);
    expect(c!.r, closeTo(1, 1e-9));
    final flat = [for (var i = 0; i < 40; i++) s(t0.add(Duration(minutes: i)), 98)];
    expect(correlate(VitalType.heartRate, a, VitalType.spo2, flat), isNull);
    expect(correlate(VitalType.heartRate, a.take(10).toList(), VitalType.respiratoryRate, b.take(10).toList()), isNull);
  });

  test('downsample caps the point count and keeps the overall mean', () {
    final raw = [for (var i = 0; i < 1000; i++) s(t0.add(Duration(seconds: 60 * i)), 70 + (i % 10).toDouble())];
    final d = downsample(raw, 100);
    expect(d.length, lessThanOrEqualTo(100));
    expect(mean(d)!, closeTo(mean(raw)!, 0.5));
  });

  test('SampleStore keeps samples sorted when delayed data arrives out of order', () {
    final store = SampleStore();
    Observation o(int min) => Observation(
          astronautId: 'a1',
          deviceId: 'd',
          type: VitalType.heartRate,
          value: 60.0 + min,
          unit: 'bpm',
          measuredAt: t0.add(Duration(minutes: min)),
          receivedAt: t0.add(const Duration(minutes: 30)),
          source: ObservationSource.ble,
        );
    store.addAll([o(1), o(3), o(2), o(2)]);
    final series = store.series('a1', VitalType.heartRate, now: t0.add(const Duration(hours: 1)));
    expect([for (final x in series) x.v], [61, 62, 63]);
  });
}
