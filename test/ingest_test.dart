import 'package:athera/domain/models.dart';
import 'package:athera/sensors/ingest.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 12);

  test('exact duplicates are dropped', () {
    final p = IngestPipeline();
    final o = obs(VitalType.heartRate, 70, now);
    final first = p.process([o], now: now);
    final second = p.process([o], now: now);
    expect(first.accepted.length, 1);
    expect(second.accepted, isEmpty);
    expect(second.duplicates, 1);
  });

  test('implausible values are kept but flagged invalid', () {
    final p = IngestPipeline();
    final res = p.process([
      obs(VitalType.heartRate, 400, now),
      obs(VitalType.spo2, 120, now),
      obs(VitalType.heartRate, double.nan, now.add(const Duration(seconds: 1))),
      obs(VitalType.heartRate, 70, now.add(const Duration(seconds: 2))),
    ], now: now);
    expect(res.invalid, 3);
    expect(res.accepted.where((o) => o.quality == DataQuality.invalid).length, 3);
    expect(res.accepted.where((o) => o.isUsable).length, 1);
  });

  test('readings timestamped in the future are invalid', () {
    final p = IngestPipeline();
    final res = p.process([obs(VitalType.heartRate, 70, now.add(const Duration(hours: 2)))], now: now);
    expect(res.accepted.single.quality, DataQuality.invalid);
  });

  test('late arrivals keep both timestamps and are downgraded to fair', () {
    final p = IngestPipeline();
    final measured = now.subtract(const Duration(minutes: 10));
    final res = p.process([obs(VitalType.heartRate, 70, measured, received: now)], now: now);
    final o = res.accepted.single;
    expect(res.delayed, 1);
    expect(o.quality, DataQuality.fair);
    expect(o.measuredAt, measured);
    expect(o.receivedAt, now);
    expect(o.delay, const Duration(minutes: 10));
  });
}
