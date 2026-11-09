import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
import '../wellness/brief.dart';
import '../wellness/check_in.dart';
import '../wellness/guidance.dart';
import '../wellness/mission_env.dart';
import '../wellness/routine.dart';
import 'app_controller.dart';

/// Self-reported health data (check-ins, routine) and the guidance built from
/// them plus live vitals and the AI result. Sensor data stays in [AppController].
class WellnessState extends ChangeNotifier {
  WellnessState(this._c, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    _c.sleepHoursProvider = sleepAt;
    _c.addListener(_onController);
    _onController();
  }

  final AppController _c;
  final DateTime Function() _clock;
  final Uuid _uuid = const Uuid();
  final GuidanceEngine _engine = const GuidanceEngine();

  String? _loadedFor;
  bool _loading = false;
  bool _disposed = false;

  List<CheckIn> checkIns = const []; // newest first
  List<RoutineLogEntry> routine = const [];
  String? error;

  MissionEnvironment get environment => _c.missionEnvironment;
  String get astronautId => _c.selected.id;

  DateTime get _now => _clock();
  String get _today => dayKey(_now);

  CheckIn? get todayCheckIn {
    for (final c in checkIns) {
      if (c.day == _today) return c;
    }
    return null;
  }

  Set<String> get doneToday => RoutineProgress.doneOn(routine, _today);
  int get pointsToday => RoutineProgress.pointsFor(doneToday);
  int get streak => RoutineProgress.streak(routine, _now);
  double get weeklyAdherence => RoutineProgress.adherence(routine, _now);
  double exerciseAdherence() => RoutineProgress.adherence(routine, _now, taskId: 'exercise');

  void _onController() {
    if (_disposed || _c.bootstrapping) return;
    final id = _c.selected.id;
    if (id != _loadedFor && !_loading) load(id);
  }

  Future<void> load(String id) async {
    _loading = true;
    try {
      if (_c.demoMode) await _seedDemo(id);
      final since = dayKey(_now.subtract(const Duration(days: 40)));
      checkIns = await _c.repo.checkIns(id);
      routine = await _c.repo.routineLog(id, sinceDay: since);
      error = null;
    } catch (e) {
      error = 'Could not load wellness data: $e';
    } finally {
      _loadedFor = id;
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Sleep for the day of [at]: that day's check-in, else the latest earlier
  /// one within 48 hours. Null when there is none (no value is invented).
  double? sleepAt(String id, DateTime at) {
    if (id != _loadedFor) return null;
    final day = dayKey(at);
    for (final c in checkIns) {
      if (c.day == day) return c.sleepHours;
    }
    for (final c in checkIns) {
      if (!c.at.isAfter(at) && at.difference(c.at) <= const Duration(hours: 48)) return c.sleepHours;
    }
    return null;
  }

  /// Saves today's check-in. Returns an error message, or null on success.
  Future<String?> submitCheckIn({
    required double sleepHours,
    required int mood,
    required int fatigue,
    required int stress,
    double? glucoseMgDl,
    String note = '',
  }) async {
    final problem = CheckIn.validate(
        sleepHours: sleepHours, mood: mood, fatigue: fatigue, stress: stress, glucoseMgDl: glucoseMgDl);
    if (problem != null) return problem;
    final existing = todayCheckIn;
    final c = CheckIn(
      id: existing?.id ?? _uuid.v4(),
      astronautId: astronautId,
      at: _now.toUtc(),
      sleepHours: sleepHours,
      mood: mood,
      fatigue: fatigue,
      stress: stress,
      glucoseMgDl: glucoseMgDl,
      note: note.trim(),
      isDemo: _c.demoMode,
    );
    try {
      await _c.repo.saveCheckIn(c);
      await _c.repo.setRoutineDone(
          RoutineLogEntry(astronautId: astronautId, taskId: 'checkin', day: _today, doneAt: _now.toUtc(), isDemo: _c.demoMode),
          true);
    } catch (e) {
      return 'Could not save the check-in: $e';
    }
    await load(astronautId);
    return null;
  }

  Future<void> toggleTask(String taskId) async {
    final done = doneToday.contains(taskId);
    final e = RoutineLogEntry(
        astronautId: astronautId, taskId: taskId, day: _today, doneAt: _now.toUtc(), isDemo: _c.demoMode);
    try {
      await _c.repo.setRoutineDone(e, !done);
      await load(astronautId);
    } catch (err) {
      error = 'Could not update the routine: $err';
      notifyListeners();
    }
  }

  // ---- guidance and brief ---------------------------------------------------
  Map<VitalType, double> _latest() {
    final out = <VitalType, double>{};
    final now = _now.toUtc();
    for (final t in VitalType.values) {
      final s = _c.samples.latest(astronautId, t);
      // Only readings from the last 30 minutes count as "current".
      if (s != null && now.difference(s.t) <= const Duration(minutes: 30)) out[t] = s.v;
    }
    return out;
  }

  Guidance get guidance {
    final risk = _c.aiOf(astronautId).risk;
    return _engine.evaluate(GuidanceInput(
      latest: _latest(),
      aiPredicted: risk?.riskClass,
      aiNow: risk?.currentClass,
      aiHorizonMinutes: risk?.horizonMinutes,
      aiSimulatedInput: risk?.inputSimulated ?? false,
      aiScore: risk?.riskScore,
      checkIn: todayCheckIn,
      recentCheckIns: checkIns,
      environment: environment,
      sensorsStale: _c.connectionOf(astronautId) == Connection.disconnected,
    ));
  }

  String buildBrief() {
    final now = _now;
    final lines = <VitalLine>[];
    for (final t in VitalType.values) {
      final latest = _c.samples.latest(astronautId, t);
      if (latest == null) continue;
      final day = _c.samples.series(astronautId, t, within: const Duration(hours: 24), now: now.toUtc());
      double? lo, hi, avg;
      if (day.isNotEmpty) {
        lo = day.map((s) => s.v).reduce((a, b) => a < b ? a : b);
        hi = day.map((s) => s.v).reduce((a, b) => a > b ? a : b);
        avg = day.map((s) => s.v).reduce((a, b) => a + b) / day.length;
      }
      lines.add(VitalLine(t, latest.v, latest.t, min: lo, max: hi, mean: avg));
    }
    return FlightSurgeonBrief.build(
      astronaut: _c.selected,
      now: now,
      environment: environment,
      vitals: lines,
      guidance: guidance,
      simulated: _c.isSimulated,
      checkIn: todayCheckIn,
      risk: _c.aiOf(astronautId).risk,
      openAlerts: [for (final a in _c.openAlertsFor(astronautId)) '${a.severity.name}: ${a.title}'],
      fahrenheit: _c.settings.fahrenheit,
    );
  }

  // ---- demo seed ----------------------------------------------------------------
  Future<void> _seedDemo(String id) async {
    if ((await _c.repo.checkIns(id)).isNotEmpty) return;
    var seed = 17;
    for (final u in id.codeUnits) {
      seed = (seed * 31 + u) & 0x7fffffff;
    }
    int next(int n) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return (seed >> 8) % n;
    }

    final now = _now;
    for (var d = 7; d >= 1; d--) {
      final day = DateTime(now.year, now.month, now.day - d, 21);
      final key = dayKey(day);
      await _c.repo.saveCheckIn(CheckIn(
        id: _uuid.v4(),
        astronautId: id,
        at: day.toUtc(),
        sleepHours: 6.0 + next(20) / 10,
        mood: 3 + next(3),
        fatigue: 1 + next(3),
        stress: 1 + next(3),
        glucoseMgDl: next(3) == 0 ? 88.0 + next(14) : null,
        isDemo: true,
      ));
      for (final t in kRoutine) {
        // Mostly complete, with a few realistic misses.
        if (t.id == 'exercise' && d == 3) continue;
        if (next(10) == 0) continue;
        await _c.repo.setRoutineDone(
            RoutineLogEntry(astronautId: id, taskId: t.id, day: key, doneAt: day.toUtc(), isDemo: true), true);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _c.removeListener(_onController);
    if (_c.sleepHoursProvider == sleepAt) _c.sleepHoursProvider = null;
    super.dispose();
  }
}
