import '../domain/ai_models.dart';
import '../domain/models.dart';
import '../wellness/check_in.dart';
import '../wellness/routine.dart';

class PersistenceException implements Exception {
  PersistenceException(this.message);
  final String message;
  @override
  String toString() => 'PersistenceException: $message';
}

/// Single data-access boundary. UI and controllers never touch SQL.
abstract class AtheraRepository {
  String get backendName;
  Future<void> init();

  // Crew
  Future<void> saveAstronauts(List<Astronaut> items);
  Future<List<Astronaut>> astronauts();
  Future<void> saveDevices(List<Device> items);
  Future<List<Device>> devices();

  // Observations
  Future<void> insertObservations(List<Observation> items);
  Future<List<Observation>> observations(
    String astronautId, {
    DateTime? since,
    DateTime? until,
    bool excludeSimulated = false,
  });
  Future<int> pendingSyncCount();
  Future<void> markAllSynced();
  Future<void> pruneObservations(DateTime before);

  // AI results
  Future<void> saveForecast(ForecastResult f);
  Future<ForecastResult?> latestForecast(String astronautId);
  Future<void> saveRisk(RiskResult r);
  Future<List<RiskResult>> riskHistory(String astronautId, {int limit = 200});

  // Alerts
  Future<void> upsertAlert(AlertEvent a);
  Future<List<AlertEvent>> alerts({
    String? astronautId,
    AlertCategory? category,
    AlertSeverity? severity,
    DateTime? since,
    bool openOnly = false,
    int limit = 500,
  });

  // Emergency
  Future<void> saveEmergency(EmergencyEvent e);
  Future<List<EmergencyEvent>> emergencies({int limit = 100});

  // Wellness (user-entered, not sensor data)
  Future<void> saveCheckIn(CheckIn c);
  Future<List<CheckIn>> checkIns(String astronautId, {int limit = 60});
  Future<void> setRoutineDone(RoutineLogEntry e, bool done);
  Future<List<RoutineLogEntry>> routineLog(String astronautId, {String? sinceDay});

  // Sync records
  Future<void> addSyncRecord(SyncRecord r);
  Future<List<SyncRecord>> syncRecords({int limit = 20});

  /// Removes simulated data only (observations, AI results, alerts, SOS).
  Future<void> deleteDemoData();
}
