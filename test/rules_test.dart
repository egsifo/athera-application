import 'package:athera/analytics/rules.dart';
import 'package:athera/analytics/sample_store.dart';
import 'package:athera/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 12);
  const engine = RuleEngine();

  SampleStore storeWith(VitalType t, double v, {int minutes = 6, Duration endAgo = Duration.zero}) {
    final s = SampleStore();
    for (var i = 0; i < minutes; i++) {
      s.add(obs(t, v, now.subtract(endAgo).subtract(Duration(minutes: i))));
    }
    return s;
  }

  test('nominal readings produce no findings', () {
    final f = engine.evaluate(storeWith(VitalType.heartRate, 70), 'a1', now: now);
    expect(f, isEmpty);
  });

  test('a sustained high heart rate raises an early warning, not a critical alert', () {
    final f = engine.evaluate(storeWith(VitalType.heartRate, 130), 'a1', now: now);
    expect(f.length, 1);
    expect(f.single.key, 'vital:a1:heartRate');
    expect(f.single.severity, AlertSeverity.warning);
    expect(f.single.category, AlertCategory.earlyWarning);
    expect(f.single.detail, contains('not a diagnosis'));
  });

  test('a very low SpO2 is critical', () {
    final f = engine.evaluate(storeWith(VitalType.spo2, 86), 'a1', now: now);
    expect(f.single.severity, AlertSeverity.critical);
  });

  test('one stray spike does not raise an alert', () {
    final s = storeWith(VitalType.heartRate, 70);
    s.add(obs(VitalType.heartRate, 190, now.subtract(const Duration(seconds: 20))));
    expect(engine.evaluate(s, 'a1', now: now), isEmpty);
  });

  test('stopped data reports a sensor disconnection and suppresses threshold findings', () {
    final s = storeWith(VitalType.heartRate, 190, endAgo: const Duration(minutes: 30));
    final f = engine.evaluate(s, 'a1', now: now);
    expect(f.single.category, AlertCategory.sensorDisconnection);
  });

  test('monitoring status follows open alerts and no-data', () {
    final s = storeWith(VitalType.heartRate, 70);
    expect(engine.statusFrom(SampleStore(), 'a1', const []), MonitoringStatus.noData);
    expect(engine.statusFrom(s, 'a1', const []), MonitoringStatus.nominal);
    final crit = AlertEvent(
      id: '1',
      category: AlertCategory.criticalAlert,
      severity: AlertSeverity.critical,
      title: 't',
      detail: 'd',
      source: 'x',
      createdAt: now,
      astronautId: 'a1',
    );
    expect(engine.statusFrom(s, 'a1', [crit]), MonitoringStatus.critical);
  });
}
