import '../core/format.dart';
import '../domain/models.dart';

String _iso(DateTime t) => t.toUtc().toIso8601String();

/// CSV of raw observations. `is_simulated` is always included so demo data can
/// never be mistaken for measurements.
String observationsCsv(List<Observation> items) {
  final b = StringBuffer(
    'astronaut_id,device_id,measurement,value,unit,measured_at_utc,received_at_utc,source,quality,is_simulated\n',
  );
  for (final o in items) {
    b.writeln([
      o.astronautId,
      o.deviceId,
      o.type.name,
      o.value,
      o.unit,
      _iso(o.measuredAt),
      _iso(o.receivedAt),
      o.source.name,
      o.quality.name,
      o.isSimulated,
    ].map(csvEscape).join(','));
  }
  return b.toString();
}

String alertsCsv(List<AlertEvent> items) {
  final b = StringBuffer('id,created_at_utc,category,severity,status,astronaut_id,source,title,detail,is_simulated\n');
  for (final a in items) {
    b.writeln([
      a.id,
      _iso(a.createdAt),
      a.category.name,
      a.severity.name,
      a.status.name,
      a.astronautId,
      a.source,
      a.title,
      a.detail,
      a.isDemo,
    ].map(csvEscape).join(','));
  }
  return b.toString();
}

String emergenciesCsv(List<EmergencyEvent> items) {
  final b = StringBuffer('event_id,created_at_utc,astronaut_id,severity,status,manual,transport,is_simulated,recipients\n');
  for (final e in items) {
    b.writeln([
      e.id,
      _iso(e.createdAt),
      e.astronautId,
      e.severity.name,
      e.status.name,
      e.manual,
      e.transportName,
      e.simulated,
      e.deliveries.map((d) => '${d.recipientId}:${d.state.name}').join(';'),
    ].map(csvEscape).join(','));
  }
  return b.toString();
}
