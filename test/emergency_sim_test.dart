import 'package:athera/sim/emergency_sim.dart';
import 'package:flutter_test/flutter_test.dart';

SimEngine run(SimScenario s, {int? until}) {
  final e = SimEngine(s);
  final n = until ?? s.durationSeconds;
  while (e.history.length < n && e.step()) {}
  return e;
}

bool has(SimEngine e, String part) => e.events.any((x) => x.title.contains(part));

void main() {
  test('healthy: stable vitals, no alerts', () {
    final e = run(SimScenario.healthy);
    expect(e.done, isTrue);
    expect(e.events.where((x) => x.severity >= 1), isEmpty);
    expect(e.history.every((s) => s.spo2 > 96 && s.hr > 65 && s.hr < 80), isTrue);
  });

  test('fainting: detected only after the person stops moving, never as death', () {
    final e = run(SimScenario.fainting);
    expect(has(e, 'Suspected loss of consciousness'), isTrue);
    final loc = e.events.firstWhere((x) => x.title.contains('Suspected loss'));
    expect(loc.t, greaterThan(100));
    expect(loc.detail, contains('NOT confirmed'));
    expect(has(e, 'Mission control notified'), isTrue);
    for (final x in e.events) {
      expect('${x.title} ${x.detail}'.toLowerCase(), isNot(contains('dead')));
      expect('${x.title} ${x.detail}'.toLowerCase(), isNot(contains('death')));
    }
  });

  test('hypoxia: SpO2 falls, alerts escalate in order, trend supports a threshold estimate', () {
    final e = run(SimScenario.hypoxia);
    expect(e.history.last.spo2, lessThan(85));
    final order = ['SpO₂ below 94%', 'SpO₂ below 90%', 'SpO₂ below 85%'].map((k) => e.events.firstWhere((x) => x.title.contains(k)).t).toList();
    expect(order[0] < order[1] && order[1] < order[2], isTrue);
    final mid = run(SimScenario.hypoxia, until: 120);
    final eta = mid.spo2SecondsTo(90);
    expect(eta, isNotNull);
    expect(eta, greaterThan(0));
  });

  test('threshold estimate is unavailable without enough data or a trend', () {
    expect(secondsToThreshold([97, 96.9], 90), isNull);
    expect(secondsToThreshold(List.filled(40, 97.0), 90), isNull);
    expect(secondsToThreshold([for (var i = 0; i < 40; i++) 90 + i * 0.1], 85), isNull); // moving away
    expect(secondsToThreshold([for (var i = 0; i < 40; i++) 97 - i * 0.1], 90), closeTo(30.0, 0.5));
  });

  test('critical: multiple indicators trigger emergency status', () {
    final e = run(SimScenario.critical);
    expect(has(e, 'Multiple critical indicators'), isTrue);
    expect(e.events.any((x) => x.severity == 3), isTrue);
  });

  test('radiation: dose rate and cumulative dose are separate, dose only grows', () {
    final e = run(SimScenario.radiation);
    final peak = e.history.map((s) => s.doseRate).reduce((a, b) => a > b ? a : b);
    expect(peak, greaterThan(300));
    for (var i = 1; i < e.history.length; i++) {
      expect(e.history[i].cumDoseUGy, greaterThanOrEqualTo(e.history[i - 1].cumDoseUGy));
    }
    expect(e.history.last.cumDoseUGy, isNot(closeTo(e.history.last.doseRate, 1)));
    expect(has(e, 'Radiation emergency'), isTrue);
    expect(e.report().lines.join(' '), contains('µGy'));
  });

  test('lost astronaut: separates, navigation activates, returns to the spacecraft', () {
    final e = run(SimScenario.lost);
    expect(has(e, 'Separation detected'), isTrue);
    expect(has(e, 'Suit alert'), isTrue);
    expect(has(e, 'Returned to the spacecraft'), isTrue);
    expect(e.history.last.distance, lessThanOrEqualTo(2));
    expect(e.history.every((s) => s.commOk && s.navSigma != null), isTrue);
  });

  test('degraded navigation: no fix means no guidance, and the app says so', () {
    final e = run(SimScenario.lostDegraded);
    final out = e.history.where((s) => !s.commOk).toList();
    expect(out, isNotEmpty);
    expect(out.every((s) => s.navSigma == null), isTrue);
    final deg = e.events.firstWhere((x) => x.title == 'Navigation unavailable');
    expect(deg.detail, 'Navigation unavailable. Follow approved mission emergency procedures and contact mission support.');
    expect(has(e, 'Link restored'), isTrue);
  });

  test('deterministic: two runs give identical results', () {
    final a = run(SimScenario.hypoxia), b = run(SimScenario.hypoxia);
    expect(a.history.map((s) => s.spo2).toList(), b.history.map((s) => s.spo2).toList());
    expect(a.events.length, b.events.length);
  });

  test('every scenario ends, labels itself simulated and reports', () {
    for (final s in SimScenario.values) {
      final e = run(s);
      expect(e.done, isTrue, reason: s.name);
      expect(e.report().lines.join(' '), contains('SIMULATED'));
    }
  });
}
