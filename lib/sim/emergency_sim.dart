import 'dart:math' as math;

import '../emergency/knowledge_base.dart';
import '../insights/robust.dart';

/// Mission Emergency Simulator. Everything here is SIMULATED, deterministic and
/// parametric. Curves are plausible illustrations, not clinical models, and no
/// rule ever infers death: the strongest statement is "suspected loss of consciousness".

enum SimScenario { healthy, nearFaint, fainting, hypoxia, chestPain, arrhythmia, respiratory, stroke, heat, allergy, psych, critical, radiation, lost, lostDegraded }

extension SimScenarioX on SimScenario {
  String get label => switch (this) {
        SimScenario.healthy => 'A. Healthy astronaut',
        SimScenario.nearFaint => 'G1. Feels faint',
        SimScenario.chestPain => 'G3. Chest pain',
        SimScenario.arrhythmia => 'G4. Abnormal heart rhythm',
        SimScenario.respiratory => 'G5. Severe breathing difficulty',
        SimScenario.stroke => 'G6. Stroke warning signs',
        SimScenario.heat => 'G7. Heat stress',
        SimScenario.allergy => 'G8. Allergic emergency',
        SimScenario.psych => 'G9. Severe psychological distress',
        SimScenario.fainting => 'B. Fainting',
        SimScenario.hypoxia => 'C. Severe hypoxia',
        SimScenario.critical => 'D. Critical medical emergency',
        SimScenario.radiation => 'E. Radiation emergency',
        SimScenario.lost => 'F. Lost astronaut (EVA)',
        SimScenario.lostDegraded => 'F2. Lost astronaut, degraded navigation',
      };
  bool get isNav => this == SimScenario.lost || this == SimScenario.lostDegraded;
  /// The first-aid guide this scenario opens, or null when it has none.
  EmergencyKind? get guide => switch (this) {
        SimScenario.nearFaint || SimScenario.fainting => EmergencyKind.syncope,
        SimScenario.hypoxia => EmergencyKind.hypoxia,
        SimScenario.chestPain => EmergencyKind.chestPain,
        SimScenario.arrhythmia => EmergencyKind.arrhythmia,
        SimScenario.respiratory => EmergencyKind.respiratory,
        SimScenario.stroke => EmergencyKind.stroke,
        SimScenario.heat => EmergencyKind.heat,
        SimScenario.allergy => EmergencyKind.allergy,
        SimScenario.psych => EmergencyKind.psychological,
        SimScenario.radiation => EmergencyKind.radiation,
        _ => null,
      };

  /// Simulated self-reports: (second, text, severity, kind the report points to).
  List<(int, String, int, EmergencyKind)> get symptoms => switch (this) {
        SimScenario.nearFaint => [(50, 'Reported: dizziness', 2, EmergencyKind.syncope), (70, 'Reported: vision narrowing', 2, EmergencyKind.syncope)],
        SimScenario.chestPain => [(45, 'Reported: chest pressure spreading to the left arm', 3, EmergencyKind.chestPain), (70, 'Reported: cold sweat and nausea', 3, EmergencyKind.chestPain)],
        SimScenario.arrhythmia => [(100, 'Reported: palpitations and dizziness', 2, EmergencyKind.arrhythmia)],
        SimScenario.respiratory => [(40, 'Reported: severe shortness of breath', 3, EmergencyKind.respiratory), (90, 'Reported: cannot speak full sentences', 3, EmergencyKind.respiratory)],
        SimScenario.stroke => [(60, 'Reported: facial droop', 3, EmergencyKind.stroke), (75, 'Reported: arm weakness', 3, EmergencyKind.stroke), (90, 'Reported: slurred speech', 3, EmergencyKind.stroke)],
        SimScenario.heat => [(100, 'Reported: heavy sweating and weakness', 2, EmergencyKind.heat), (150, 'Reported: confusion', 3, EmergencyKind.heat)],
        SimScenario.allergy => [(40, 'Reported: widespread hives', 3, EmergencyKind.allergy), (60, 'Reported: throat tightness', 3, EmergencyKind.allergy), (90, 'Reported: dizziness', 3, EmergencyKind.allergy)],
        SimScenario.psych => [(60, 'Reported: panic, cannot calm down', 2, EmergencyKind.psychological), (120, 'Reported: thoughts of self-harm', 3, EmergencyKind.psychological)],
        _ => const [],
      };

  int get durationSeconds => switch (this) {
        SimScenario.healthy => 180,
        SimScenario.nearFaint ||
        SimScenario.chestPain ||
        SimScenario.arrhythmia ||
        SimScenario.respiratory ||
        SimScenario.stroke ||
        SimScenario.heat ||
        SimScenario.allergy ||
        SimScenario.psych =>
          240,
        SimScenario.fainting => 240,
        SimScenario.hypoxia => 300,
        SimScenario.critical => 300,
        SimScenario.radiation => 300,
        SimScenario.lost => 360,
        SimScenario.lostDegraded => 420,
      };
}

class SimParams {
  const SimParams({this.baselineHr = 72, this.baselineSpo2 = 97.5, this.baselineRr = 15, this.baselineTemp = 36.8, this.baselineDoseRate = 6});
  final double baselineHr, baselineSpo2, baselineRr, baselineTemp;

  /// Simulated quiet dose rate in µGy/h (order of magnitude of ISS quiet-time measurements).
  final double baselineDoseRate;
}

class SimSnapshot {
  const SimSnapshot({
    required this.t,
    required this.hr,
    required this.spo2,
    required this.rr,
    required this.temp,
    required this.activity,
    required this.doseRate,
    required this.cumDoseUGy,
    required this.x,
    required this.y,
    required this.distance,
    required this.commOk,
    required this.navSigma,
  });
  final int t;
  final double hr, spo2, rr, temp;

  /// 0..1 movement.
  final double activity;

  /// Dose rate µGy/h and cumulative absorbed dose µGy: two different quantities.
  final double doseRate, cumDoseUGy;

  /// Simulated position relative to the spacecraft in metres.
  final double x, y, distance;
  final bool commOk;

  /// Position uncertainty (1 sigma, metres). Null when there is no navigation fix.
  final double? navSigma;
}

class SimEvent {
  const SimEvent(this.t, this.title, this.detail, this.severity);
  final int t;
  final String title, detail;

  /// 0 info, 1 attention, 2 serious, 3 critical.
  final int severity;
}

class SimReport {
  const SimReport({required this.lines, required this.eventCount, required this.firstAlertAt});
  final List<String> lines;
  final int eventCount;
  final int? firstAlertAt;
}

/// Linear time-to-threshold estimate from the recent trend. Returns null unless
/// the data supports it: at least [minPoints] samples and a trend heading toward the threshold.
/// This is a simple extrapolation, NOT a validated prediction.
double? secondsToThreshold(List<double> values, double threshold, {int window = 30, int minPoints = 20, double minAbsSlope = 0.02}) {
  if (values.length < minPoints) return null;
  final v = values.sublist(math.max(0, values.length - window));
  final x = [for (var i = 0; i < v.length; i++) i.toDouble()];
  final s = slope(x, v);
  if (s == null || s.abs() < minAbsSlope) return null;
  final now = v.last;
  if ((threshold - now) * s <= 0) return null; // moving away, or already past
  return (threshold - now) / s;
}

class SimEngine {
  SimEngine(this.scenario, {this.params = const SimParams()});
  final SimScenario scenario;
  final SimParams params;

  final List<SimSnapshot> history = [];
  final List<SimEvent> events = [];
  final Set<String> _fired = {};
  double _cum = 0;
  int _stillSince = -1;

  bool get done => history.isNotEmpty && history.last.t >= scenario.durationSeconds - 1;
  SimSnapshot? get now => history.isEmpty ? null : history.last;

  static double _ramp(num t, num a, num b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();
  static double _lerp(double a, double b, double p) => a + (b - a) * p;

  SimSnapshot _sample(int t) {
    final p = params;
    var hr = p.baselineHr + 2 * math.sin(t / 7), spo2 = p.baselineSpo2 + 0.3 * math.sin(t / 11);
    var rr = p.baselineRr + 0.6 * math.sin(t / 9), temp = p.baselineTemp, act = 0.3 + 0.05 * math.sin(t / 13);
    var rate = p.baselineDoseRate;
    var x = 3.0, y = 0.0;
    var comm = true;
    double? sigma = 0.2;

    switch (scenario) {
      case SimScenario.healthy:
        break;
      case SimScenario.nearFaint:
        hr = _lerp(hr, 105, _ramp(t, 40, 90));
        spo2 = _lerp(spo2, 95.5, _ramp(t, 50, 100));
        act = _lerp(act, 0.1, _ramp(t, 60, 100));
      case SimScenario.chestPain:
        hr = _lerp(hr, 112, _ramp(t, 40, 100));
        spo2 = _lerp(spo2, 95.5, _ramp(t, 50, 120));
        act = _lerp(act, 0.1, _ramp(t, 45, 80));
      case SimScenario.arrhythmia:
        if (t > 60) hr = 135 + 30 * math.sin(t * 1.3) * math.cos(t * 0.4);
        act = _lerp(act, 0.15, _ramp(t, 90, 130));
      case SimScenario.respiratory:
        rr = _lerp(rr, 32, _ramp(t, 30, 120));
        spo2 = _lerp(spo2, 88, _ramp(t, 40, 160));
        hr = _lerp(hr, 118, _ramp(t, 40, 140));
        act = _lerp(act, 0.1, _ramp(t, 50, 100));
      case SimScenario.stroke:
        hr = _lerp(hr, 84, _ramp(t, 50, 100));
      case SimScenario.heat:
        temp = _lerp(temp, 39.4, _ramp(t, 30, 200));
        hr = _lerp(hr, 118, _ramp(t, 40, 200));
        act = _lerp(act, 0.1, _ramp(t, 120, 200));
      case SimScenario.allergy:
        spo2 = _lerp(spo2, 90, _ramp(t, 40, 160));
        hr = _lerp(hr, 125, _ramp(t, 40, 120));
        rr = _lerp(rr, 26, _ramp(t, 50, 140));
      case SimScenario.psych:
        hr = _lerp(hr, 104, _ramp(t, 50, 110));
        rr = _lerp(rr, 22, _ramp(t, 50, 110));
      case SimScenario.fainting:
        // Prodrome: dizziness, rising HR, slight SpO2 dip; then HR falls and movement stops.
        hr = _lerp(hr, 108, _ramp(t, 50, 95));
        hr = _lerp(hr, 46, _ramp(t, 95, 115));
        spo2 = _lerp(spo2, 94.5, _ramp(t, 70, 120));
        act = _lerp(act, 0.15, _ramp(t, 60, 95));
        act = _lerp(act, 0.0, _ramp(t, 95, 110));
        hr = _lerp(hr, p.baselineHr + 8, _ramp(t, 190, 240)); // slow return if the person recovers
        act = _lerp(act, 0.2, _ramp(t, 190, 240));
      case SimScenario.hypoxia:
        spo2 = _lerp(spo2, 79, _ramp(t, 30, 250));
        hr = _lerp(hr, 122, _ramp(t, 40, 250));
        rr = _lerp(rr, 28, _ramp(t, 40, 250));
        act = _lerp(act, 0.1, _ramp(t, 150, 260));
      case SimScenario.critical:
        hr = _lerp(hr, 152, _ramp(t, 30, 140));
        hr = _lerp(hr, 42, _ramp(t, 200, 260));
        spo2 = _lerp(spo2, 82, _ramp(t, 40, 220));
        rr = _lerp(rr, 8, _ramp(t, 120, 260));
        temp = _lerp(temp, 39.2, _ramp(t, 30, 200));
        act = _lerp(act, 0.0, _ramp(t, 90, 150));
      case SimScenario.radiation:
        // Simulated solar-particle-event-like profile: fast rise, slow decay.
        final up = _ramp(t, 40, 120);
        final down = _ramp(t, 160, 300);
        rate = p.baselineDoseRate + 600 * up * (1 - 0.8 * down);
      case SimScenario.lost:
      case SimScenario.lostDegraded:
        // Starts near the spacecraft, drifts away, separation, then a controlled return along a straight line.
        final drift = t < 120 ? 3 + 0.35 * t : 3 + 0.35 * 120; // 45 m at t=120
        const returnStart = 150;
        const returnSpeed = 0.3; // m/s, simulated
        final d = t < returnStart ? drift : math.max(0.0, drift - returnSpeed * (t - returnStart));
        final ang = 0.6 + 0.002 * t;
        x = d * math.cos(ang);
        y = d * math.sin(ang);
        act = t < returnStart ? 0.2 : 0.35;
        if (scenario == SimScenario.lostDegraded && t >= 130 && t < 250) {
          comm = false;
          sigma = null; // no ranging fix: navigation is unavailable until the link returns
        } else {
          sigma = 0.3 + (scenario == SimScenario.lostDegraded && t >= 250 ? 0.8 * math.exp(-(t - 250) / 40.0) : 0);
        }
    }
    const dtHours = 1 / 3600;
    _cum += rate * dtHours; // µGy
    return SimSnapshot(
      t: t, hr: hr, spo2: spo2.clamp(50, 100).toDouble(), rr: rr, temp: temp, activity: act.clamp(0, 1).toDouble(),
      doseRate: rate, cumDoseUGy: _cum, x: x, y: y, distance: math.sqrt(x * x + y * y), commOk: comm, navSigma: sigma,
    );
  }

  void _fire(String key, int t, String title, String detail, int sev) {
    if (_fired.add(key)) events.add(SimEvent(t, title, detail, sev));
  }

  /// Advances one simulated second. Returns false when the scenario has finished.
  bool step() {
    if (done) return false;
    final t = history.length;
    final s = _sample(t);
    history.add(s);
    _evaluate(s);
    return !done;
  }

  void _evaluate(SimSnapshot s) {
    final t = s.t;
    if (t == 0) _fire('start', t, 'Simulation started', 'All values are SIMULATED.', 0);

    for (final sy in scenario.symptoms) {
      if (sy.$1 == t) _fire('sym${sy.$1}', t, sy.$2, 'Simulated self-report. It is a possible sign, not a diagnosis.', sy.$3);
    }
    if (s.spo2 < 94) _fire('spo2a', t, 'SpO₂ below 94%', 'Blood oxygen ${s.spo2.toStringAsFixed(1)}%. Re-measure and check the oxygen system.', 1);
    if (s.spo2 < 90) _fire('spo2b', t, 'SpO₂ below 90%', 'Blood oxygen ${s.spo2.toStringAsFixed(1)}%. Escalate: crew and mission control (simulated).', 2);
    if (s.spo2 < 85) _fire('spo2c', t, 'SpO₂ below 85%: critical', 'Follow the approved hypoxia emergency procedure. Mission control notified (simulated).', 3);
    if (s.hr > 120) _fire('hrhi', t, 'Heart rate above 120 bpm', 'Heart rate ${s.hr.round()} bpm.', 2);
    if (s.hr < 50) _fire('hrlo', t, 'Heart rate below 50 bpm', 'Heart rate ${s.hr.round()} bpm.', 2);
    if (s.temp > 38.5) _fire('temp', t, 'Temperature above 38.5 °C', '${s.temp.toStringAsFixed(1)} °C.', 2);
    if (s.rr < 10 || s.rr > 25) _fire('rr', t, 'Respiratory rate out of range', '${s.rr.round()} breaths/min.', 2);

    if (s.activity < 0.05) {
      if (_stillSince < 0) _stillSince = t;
    } else {
      _stillSince = -1;
    }
    if (_stillSince >= 0 && t - _stillSince >= 10 && (s.hr < 55 || s.hr > 130 || s.spo2 < 92)) {
      _fire('loc', t, 'Suspected loss of consciousness',
          'No movement for ${t - _stillSince} s with abnormal vitals. NOT confirmed. Check responsiveness; call crew and mission control; follow the approved emergency protocol. Do not instruct movement.', 3);
      _fire('mc', t, 'Mission control notified (simulated)', 'Emergency timeline and last valid measurements sent over the simulated link.', 2);
    }
    final bad = [s.spo2 < 90, s.hr > 130 || s.hr < 50, s.temp > 38.5, s.rr < 10 || s.rr > 25].where((b) => b).length;
    if (bad >= 3) {
      _fire('multi', t, 'Multiple critical indicators', '$bad indicators out of range together. Emergency status. Mission control notified (simulated). This does not establish a cause.', 3);
    }

    if (scenario == SimScenario.radiation) {
      final base = params.baselineDoseRate;
      if (s.doseRate > 5 * base) _fire('r1', t, 'Dose rate elevated', '${s.doseRate.toStringAsFixed(0)} µGy/h, over 5x the quiet level.', 1);
      if (s.doseRate > 50 * base) {
        _fire('r2', t, 'Radiation emergency', '${s.doseRate.toStringAsFixed(0)} µGy/h. Move to the designated shelter area per mission procedure (simulated).', 3);
      }
    }

    if (scenario.isNav) {
      if (s.distance > 30) _fire('sep', t, 'Separation detected', 'Distance ${s.distance.round()} m exceeds the 30 m safety radius (SIMULATED position).', 2);
      if (t == 90) {
        _fire('emerg', t, 'Suit alert: emergency declared', 'Navigation module activated. Crew and mission control notified (simulated).', 3);
      }
      if (!s.commOk) _fire('comm', t, 'Communication lost', 'No ranging link. Last known position is kept; no new route is invented.', 3);
      if (!s.commOk) _fire('deg', t, 'Navigation unavailable', 'Navigation unavailable. Follow approved mission emergency procedures and contact mission support.', 3);
      if (s.commOk && _fired.contains('comm')) _fire('regain', t, 'Link restored', 'Ranging fix regained. Position uncertainty is shrinking.', 1);
      if (t >= 150 && s.distance <= 2) _fire('home', t, 'Returned to the spacecraft', 'Distance under 2 m (SIMULATED).', 0);
    }
    if (done) _fire('end', t, 'Simulation finished', 'See the scenario report.', 0);
  }

  /// Time until [threshold] if the recent SpO2 trend continues. Null unless supported.
  double? spo2SecondsTo(double threshold) => secondsToThreshold([for (final h in history) h.spo2], threshold);

  SimReport report() {
    final h = history;
    if (h.isEmpty) return const SimReport(lines: ['Nothing simulated yet.'], eventCount: 0, firstAlertAt: null);
    double minSpo2 = h.map((e) => e.spo2).reduce(math.min);
    double maxHr = h.map((e) => e.hr).reduce(math.max), minHr = h.map((e) => e.hr).reduce(math.min);
    final alerts = events.where((e) => e.severity >= 1).toList();
    final lines = <String>[
      'SIMULATED scenario: ${scenario.label}, ${h.length} s simulated.',
      'Lowest SpO₂ ${minSpo2.toStringAsFixed(1)}%, heart rate ${minHr.round()} to ${maxHr.round()} bpm.',
      'Alerts raised: ${alerts.length}${alerts.isEmpty ? '' : ', first at ${alerts.first.t} s'}.',
      if (scenario == SimScenario.radiation)
        'Peak dose rate ${h.map((e) => e.doseRate).reduce(math.max).toStringAsFixed(0)} µGy/h; accumulated absorbed dose ${h.last.cumDoseUGy.toStringAsFixed(1)} µGy.',
      if (scenario.isNav) 'Greatest distance ${h.map((e) => e.distance).reduce(math.max).round()} m; final distance ${h.last.distance.toStringAsFixed(1)} m.',
      if (scenario.guide != null) 'Guide opened: ${protocolFor(scenario.guide!).title.en} (general first-aid reference, not clinically reviewed).',
      'These are illustrations, not clinical or orbital data.',
    ];
    return SimReport(lines: lines, eventCount: events.length, firstAlertAt: alerts.isEmpty ? null : alerts.first.t);
  }
}
