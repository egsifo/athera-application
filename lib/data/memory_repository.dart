import '../domain/ai_models.dart';
import '../domain/models.dart';
import '../wellness/check_in.dart';
import '../wellness/routine.dart';
import 'repository.dart';

/// In-memory implementation: used for tests and as an explicit fallback when
/// SQLite cannot be opened (the UI then shows "not persisted").
class MemoryRepository implements AtheraRepository {
  final Map<String, Astronaut> _astronauts = {};
  final Map<String, Device> _devices = {};
  final Map<String, Observation> _obs = {};
  final Set<String> _synced = {};
  final List<ForecastResult> _forecasts = [];
  final List<RiskResult> _risks = [];
  final Map<String, AlertEvent> _alerts = {};
  final Map<String, EmergencyEvent> _emergencies = {};
  final List<SyncRecord> _sync = [];
  final Map<String, CheckIn> _checkIns = {};
  final Map<String, RoutineLogEntry> _routine = {};

  @override
  String get backendName => 'memory (not persisted)';

  @override
  Future<void> init() async {}

  @override
  Future<void> saveAstronauts(List<Astronaut> items) async {
    for (final a in items) {
      _astronauts[a.id] = a;
    }
  }

  @override
  Future<List<Astronaut>> astronauts() async => _astronauts.values.toList();

  @override
  Future<void> saveDevices(List<Device> items) async {
    for (final d in items) {
      _devices[d.id] = d;
    }
  }

  @override
  Future<List<Device>> devices() async => _devices.values.toList();

  @override
  Future<void> insertObservations(List<Observation> items) async {
    for (final o in items) {
      _obs.putIfAbsent(o.id, () => o);
    }
  }

  @override
  Future<List<Observation>> observations(
    String astronautId, {
    DateTime? since,
    DateTime? until,
    bool excludeSimulated = false,
  }) async {
    final list = _obs.values.where((o) {
      if (o.astronautId != astronautId) return false;
      if (since != null && o.measuredAt.isBefore(since)) return false;
      if (until != null && o.measuredAt.isAfter(until)) return false;
      if (excludeSimulated && o.isSimulated) return false;
      return true;
    }).toList();
    list.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return list;
  }

  @override
  Future<int> pendingSyncCount() async => _obs.keys.where((k) => !_synced.contains(k)).length;

  @override
  Future<void> markAllSynced() async => _synced.addAll(_obs.keys);

  @override
  Future<void> pruneObservations(DateTime before) async {
    _obs.removeWhere((_, o) => o.measuredAt.isBefore(before));
  }

  @override
  Future<void> saveForecast(ForecastResult f) async => _forecasts.add(f);

  @override
  Future<ForecastResult?> latestForecast(String astronautId) async {
    final l = _forecasts.where((f) => f.astronautId == astronautId).toList();
    if (l.isEmpty) return null;
    l.sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
    return l.last;
  }

  @override
  Future<void> saveRisk(RiskResult r) async => _risks.add(r);

  @override
  Future<List<RiskResult>> riskHistory(String astronautId, {int limit = 200}) async {
    final l = _risks.where((r) => r.astronautId == astronautId).toList();
    l.sort((a, b) => a.generatedAt.compareTo(b.generatedAt));
    return l.length > limit ? l.sublist(l.length - limit) : l;
  }

  @override
  Future<void> upsertAlert(AlertEvent a) async => _alerts[a.id] = a;

  @override
  Future<List<AlertEvent>> alerts({
    String? astronautId,
    AlertCategory? category,
    AlertSeverity? severity,
    DateTime? since,
    bool openOnly = false,
    int limit = 500,
  }) async {
    final l = _alerts.values.where((a) {
      if (astronautId != null && a.astronautId != astronautId) return false;
      if (category != null && a.category != category) return false;
      if (severity != null && a.severity != severity) return false;
      if (since != null && a.createdAt.isBefore(since)) return false;
      if (openOnly && !a.isOpen) return false;
      return true;
    }).toList();
    l.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l.length > limit ? l.sublist(0, limit) : l;
  }

  @override
  Future<void> saveEmergency(EmergencyEvent e) async => _emergencies[e.id] = e;

  @override
  Future<List<EmergencyEvent>> emergencies({int limit = 100}) async {
    final l = _emergencies.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l.length > limit ? l.sublist(0, limit) : l;
  }

  @override
  Future<void> addSyncRecord(SyncRecord r) async => _sync.insert(0, r);

  @override
  Future<List<SyncRecord>> syncRecords({int limit = 20}) async =>
      _sync.length > limit ? _sync.sublist(0, limit) : List.of(_sync);

  @override
  Future<void> saveCheckIn(CheckIn c) async => _checkIns[c.id] = c;

  @override
  Future<List<CheckIn>> checkIns(String astronautId, {int limit = 60}) async {
    final l = _checkIns.values.where((c) => c.astronautId == astronautId).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return l.take(limit).toList();
  }

  String _rk(RoutineLogEntry e) => '${e.astronautId}|${e.taskId}|${e.day}';

  @override
  Future<void> setRoutineDone(RoutineLogEntry e, bool done) async {
    if (done) {
      _routine[_rk(e)] = e;
    } else {
      _routine.remove(_rk(e));
    }
  }

  @override
  Future<List<RoutineLogEntry>> routineLog(String astronautId, {String? sinceDay}) async => [
        for (final e in _routine.values)
          if (e.astronautId == astronautId && (sinceDay == null || e.day.compareTo(sinceDay) >= 0)) e,
      ];

  @override
  Future<void> deleteDemoData() async {
    _checkIns.removeWhere((_, c) => c.isDemo);
    _routine.removeWhere((_, e) => e.isDemo);
    _obs.removeWhere((_, o) => o.isSimulated);
    _forecasts.removeWhere((f) => f.isMock);
    _risks.removeWhere((r) => r.isMock || r.inputSimulated);
    _alerts.removeWhere((_, a) => a.isDemo);
    _emergencies.removeWhere((_, e) => e.simulated);
  }
}
