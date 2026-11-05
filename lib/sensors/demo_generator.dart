import 'dart:math' as math;

import '../domain/models.dart';

/// Scripted storylines for the simulator. These produce SIMULATED data only.
enum DemoScenario { nominal, eva, developingWarning, sensorDropout }

extension DemoScenarioX on DemoScenario {
  String get label => switch (this) {
        DemoScenario.nominal => 'Nominal (resting)',
        DemoScenario.eva => 'EVA exertion',
        DemoScenario.developingWarning => 'Developing respiratory strain',
        DemoScenario.sensorDropout => 'Sensor dropout',
      };
}

class DemoConfig {
  const DemoConfig({
    this.seed = 42,
    this.noise = 1.0,
    this.dropoutRate = 0.01,
    this.glitchRate = 0.003,
    this.historyHours = 24,
    this.liveTickSeconds = 10,
    this.scenarios = const {},
  });

  final int seed;

  /// Multiplier on random jitter (0 = perfectly smooth).
  final double noise;

  /// Probability that a single reading is missing.
  final double dropoutRate;

  /// Probability of an obviously invalid reading (exercises validation).
  final double glitchRate;
  final int historyHours;
  final int liveTickSeconds;
  final Map<String, DemoScenario> scenarios;

  DemoConfig copyWith({
    int? seed,
    double? noise,
    double? dropoutRate,
    double? glitchRate,
    int? historyHours,
    int? liveTickSeconds,
    Map<String, DemoScenario>? scenarios,
  }) =>
      DemoConfig(
        seed: seed ?? this.seed,
        noise: noise ?? this.noise,
        dropoutRate: dropoutRate ?? this.dropoutRate,
        glitchRate: glitchRate ?? this.glitchRate,
        historyHours: historyHours ?? this.historyHours,
        liveTickSeconds: liveTickSeconds ?? this.liveTickSeconds,
        scenarios: scenarios ?? this.scenarios,
      );
}

class _Base {
  const _Base(this.hr, this.rr, this.spo2, this.temp, this.sys, this.dia);
  final double hr, rr, spo2, temp, sys, dia;
}

/// Deterministic, internally consistent simulator. One shared "activity" curve
/// drives heart rate, respiration, SpO2, temperature and blood pressure together,
/// so correlations between vitals are physiologically plausible. Every
/// observation it emits has source = demo and is labelled DEMO DATA in the UI.
class DemoGenerator {
  DemoGenerator({required this.config, DateTime? anchor}) : anchor = (anchor ?? DateTime.now()).toUtc();

  final DemoConfig config;

  /// "Now" of the storyline: scenario effects are defined relative to this.
  final DateTime anchor;

  static const crew = <Astronaut>[
    Astronaut(id: 'demo-astronaut-01', name: 'Amira Hassan', callsign: 'ATLAS', role: UserRole.commander, isDemo: true),
    Astronaut(id: 'demo-astronaut-02', name: 'Jonas Weber', callsign: 'BOREAS', role: UserRole.astronaut, isDemo: true),
    Astronaut(id: 'demo-astronaut-03', name: 'Mei Tanaka', callsign: 'CIRRUS', role: UserRole.astronaut, isDemo: true),
    Astronaut(id: 'demo-astronaut-04', name: 'Luca Romano', callsign: 'DELTA', role: UserRole.astronaut, isDemo: true),
  ];

  static const Map<String, DemoScenario> defaultScenarios = {
    'demo-astronaut-01': DemoScenario.nominal,
    'demo-astronaut-02': DemoScenario.eva,
    'demo-astronaut-03': DemoScenario.developingWarning,
    'demo-astronaut-04': DemoScenario.sensorDropout,
  };

  static const Map<String, _Base> _bases = {
    'demo-astronaut-01': _Base(62, 14, 98.2, 36.7, 116, 74),
    'demo-astronaut-02': _Base(68, 15, 97.8, 36.8, 122, 78),
    'demo-astronaut-03': _Base(66, 15, 98.0, 36.7, 112, 72),
    'demo-astronaut-04': _Base(60, 13, 98.5, 36.6, 118, 76),
  };

  /// Modular devices: no single wearable is assumed to measure everything.
  static String deviceIdFor(String astronautId, VitalType t) {
    final n = astronautId.split('-').last;
    return switch (t) {
      VitalType.heartRate || VitalType.spo2 => 'demo-$n-pulseox',
      VitalType.temperature => 'demo-$n-coretemp',
      VitalType.respiratoryRate => 'demo-$n-chest',
      VitalType.systolic || VitalType.diastolic => 'demo-$n-bpcuff',
    };
  }

  static List<Device> devicesFor(Astronaut a) {
    final n = a.id.split('-').last;
    return [
      Device(id: 'demo-$n-pulseox', astronautId: a.id, name: 'Pulse oximeter (demo)', measures: const [VitalType.heartRate, VitalType.spo2], isDemo: true),
      Device(id: 'demo-$n-coretemp', astronautId: a.id, name: 'Core temp sensor (demo)', measures: const [VitalType.temperature], isDemo: true),
      Device(id: 'demo-$n-chest', astronautId: a.id, name: 'Chest strap (demo)', measures: const [VitalType.respiratoryRate], isDemo: true),
      Device(id: 'demo-$n-bpcuff', astronautId: a.id, name: 'BP cuff (demo)', measures: const [VitalType.systolic, VitalType.diastolic], isDemo: true),
    ];
  }

  DemoScenario scenarioOf(String id) => config.scenarios[id] ?? defaultScenarios[id] ?? DemoScenario.nominal;

  bool deviceOnline(String id, DateTime t) {
    if (scenarioOf(id) != DemoScenario.sensorDropout) return true;
    return t.toUtc().isBefore(anchor.subtract(const Duration(minutes: 25)));
  }

  _Base _baseOf(String id) => _bases[id] ?? const _Base(64, 14, 98, 36.7, 118, 76);

  int _hash(String s) {
    var h = 7;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  double _u(String id, VitalType type, DateTime t, int salt) {
    final sec = t.toUtc().millisecondsSinceEpoch ~/ 1000;
    final h = (config.seed * 73856093) ^ (_hash(id) * 19349663) ^ (type.index * 83492791) ^ (sec * 2654435761) ^ (salt * 40503);
    return math.Random(h & 0x7fffffff).nextDouble();
  }

  double _jit(String id, VitalType type, DateTime t) => (_u(id, type, t, 0) * 2 - 1) * config.noise;

  double _phase(String id) => (_hash(id) % 628) / 100.0;

  double _mins(DateTime t) => t.toUtc().difference(anchor).inSeconds / 60.0;

  double activity(String id, DateTime t) {
    final m = _mins(t);
    final ph = _phase(id);
    switch (scenarioOf(id)) {
      case DemoScenario.eva:
        final a = 0.55 + 0.30 * math.sin(2 * math.pi * m / 37 + ph) + 0.10 * math.sin(2 * math.pi * m / 9);
        return a.clamp(0.15, 1.0);
      case DemoScenario.developingWarning:
      case DemoScenario.nominal:
      case DemoScenario.sensorDropout:
        return 0.10 + 0.06 * math.sin(2 * math.pi * m / 23 + ph);
    }
  }

  /// 0..1 ramp for the developing-warning storyline (reaches ~0.88 at "now").
  double _ramp(String id, DateTime t) {
    if (scenarioOf(id) != DemoScenario.developingWarning) return 0;
    final r = ((_mins(t) + 75) / 85).clamp(0.0, 1.0);
    return r * r * (3 - 2 * r); // smoothstep
  }

  /// Ground-truth value of the simulator at time [t] (null = reading missing).
  double? value(String id, VitalType type, DateTime t) {
    if (_u(id, type, t, 1) < config.dropoutRate) return null;
    if (_u(id, type, t, 2) < config.glitchRate) {
      if (type == VitalType.spo2) return 0;
      if (type == VitalType.heartRate) return 255;
    }
    final b = _baseOf(id);
    final act = activity(id, t);
    final r = _ramp(id, t);
    final hour = t.toUtc().hour + t.toUtc().minute / 60.0;
    final circ = math.sin(2 * math.pi * (hour - 4) / 24);
    final j = _jit(id, type, t);
    switch (type) {
      case VitalType.heartRate:
        return (b.hr + 40 * act + 3 * circ + 28 * r + 1.5 * j).roundToDouble();
      case VitalType.respiratoryRate:
        return double.parse((b.rr + 8 * act + 10 * r + 0.8 * j).toStringAsFixed(1));
      case VitalType.spo2:
        return double.parse(math.min(100.0, b.spo2 - 1.2 * act - 5 * r + 0.4 * j).toStringAsFixed(1));
      case VitalType.temperature:
        return double.parse((b.temp + 0.35 * act + 0.15 * math.sin(2 * math.pi * (hour - 16) / 24) + 1.0 * r + 0.04 * j).toStringAsFixed(2));
      case VitalType.systolic:
        return (b.sys + 22 * act + 6 * r + 2 * j).roundToDouble();
      case VitalType.diastolic:
        return (b.dia + 9 * act + 3 * r + 1.5 * j).roundToDouble();
    }
  }

  Observation? observe(Astronaut a, VitalType type, DateTime t, {DateTime? receivedAt}) {
    final v = value(a.id, type, t);
    if (v == null) return null;
    final delayed = _u(a.id, type, t, 3) < 0.01;
    return Observation(
      astronautId: a.id,
      deviceId: deviceIdFor(a.id, type),
      type: type,
      value: v,
      unit: type.unit,
      measuredAt: t.toUtc(),
      receivedAt: (receivedAt ?? t.add(const Duration(seconds: 2))).toUtc().add(delayed ? const Duration(minutes: 6) : Duration.zero),
      source: ObservationSource.demo,
    );
  }

  /// One-minute samples for [historyHours] ending at [end]. Blood pressure is
  /// sampled every 5 minutes (cuff-like), everything else every minute.
  List<Observation> history(Astronaut a, DateTime end) {
    final e = end.toUtc();
    final endMin = DateTime.utc(e.year, e.month, e.day, e.hour, e.minute);
    final start = endMin.subtract(Duration(hours: config.historyHours));
    final out = <Observation>[];
    var i = 0;
    for (var t = start; !t.isAfter(endMin); t = t.add(const Duration(minutes: 1)), i++) {
      if (!deviceOnline(a.id, t)) continue;
      for (final type in VitalType.values) {
        final bp = type == VitalType.systolic || type == VitalType.diastolic;
        if (bp && i % 5 != 0) continue;
        final o = observe(a, type, t);
        if (o != null) out.add(o);
      }
    }
    return out;
  }

  /// A fresh reading for "now" (live tick).
  List<Observation> liveSample(Astronaut a, DateTime t, {required bool includeBp}) {
    if (!deviceOnline(a.id, t)) return const [];
    final out = <Observation>[];
    for (final type in VitalType.values) {
      final bp = type == VitalType.systolic || type == VitalType.diastolic;
      if (bp && !includeBp) continue;
      final o = observe(a, type, t, receivedAt: t);
      if (o != null) out.add(o);
    }
    return out;
  }

  /// The four non-vital inputs the ATHERA model needs, SIMULATED. Units and
  /// scales here are placeholders (see AI_INTEGRATION.md): they must be matched
  /// to the model's training data before any real use.
  Map<String, double> modelContext(String id, DateTime t) {
    final act = activity(id, t);
    final r = _ramp(id, t);
    final j = _u(id, VitalType.heartRate, t, 9) * 2 - 1;
    double c(double v, double lo, double hi) => double.parse(v.clamp(lo, hi).toStringAsFixed(2));
    return {
      'HRV_Stress_Index': c(30 + 35 * act + 40 * r + 3 * j * config.noise, 0, 100),
      'Radiation_Level': c(0.35 + 0.10 * act + 0.02 * j * config.noise, 0, 10),
      'Sleep_Hours': c(7.2 - 2.5 * r + 0.1 * j * config.noise, 0, 12),
      'Physical_Activity_Load': c(100 * act, 0, 100),
    };
  }

  /// Synthetic ECG strip (mV). SIMULATED: only used in demo mode, always
  /// labelled DEMO DATA. Real ECG needs an ECG-capable device.
  List<double> ecgWaveform(double heartRate, {int sampleRateHz = 125, double seconds = 6}) {
    final n = (sampleRateHz * seconds).round();
    final beat = 60.0 / heartRate.clamp(30, 220);
    double g(double x, double c, double w, double amp) => amp * math.exp(-math.pow((x - c) / w, 2));
    return List<double>.generate(n, (i) {
      final x = ((i / sampleRateHz) % beat) / beat;
      return g(x, .18, .035, .12) + g(x, .36, .010, -.12) + g(x, .39, .012, 1.0) + g(x, .42, .014, -.25) + g(x, .65, .055, .30);
    });
  }
}
