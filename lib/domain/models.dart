import 'dart:convert';

// ---------------------------------------------------------------------------
// Vital signs
// ---------------------------------------------------------------------------
enum VitalType { heartRate, spo2, temperature, respiratoryRate, systolic, diastolic }

VitalType? vitalFromKey(String key) {
  for (final v in VitalType.values) {
    if (v.name == key) return v;
  }
  return null;
}

extension VitalTypeX on VitalType {
  String get label => switch (this) {
        VitalType.heartRate => 'Heart rate',
        VitalType.spo2 => 'Blood oxygen (SpO₂)',
        VitalType.temperature => 'Core temperature',
        VitalType.respiratoryRate => 'Respiratory rate',
        VitalType.systolic => 'Systolic pressure',
        VitalType.diastolic => 'Diastolic pressure',
      };

  String get shortLabel => switch (this) {
        VitalType.heartRate => 'HR',
        VitalType.spo2 => 'SpO₂',
        VitalType.temperature => 'Temp',
        VitalType.respiratoryRate => 'RR',
        VitalType.systolic => 'SYS',
        VitalType.diastolic => 'DIA',
      };

  String get unit => switch (this) {
        VitalType.heartRate => 'bpm',
        VitalType.spo2 => '%',
        VitalType.temperature => '°C',
        VitalType.respiratoryRate => 'br/min',
        VitalType.systolic => 'mmHg',
        VitalType.diastolic => 'mmHg',
      };

  int get decimals => switch (this) {
        VitalType.temperature => 1,
        VitalType.spo2 => 0,
        _ => 0,
      };

  /// Physically plausible sensor range. Outside = invalid reading (sensor error),
  /// not a medical finding. Mirrors the gateway schema limits.
  double get validMin => switch (this) {
        VitalType.heartRate => 20,
        VitalType.spo2 => 50,
        VitalType.temperature => 30,
        VitalType.respiratoryRate => 4,
        VitalType.systolic => 50,
        VitalType.diastolic => 20,
      };

  double get validMax => switch (this) {
        VitalType.heartRate => 250,
        VitalType.spo2 => 100,
        VitalType.temperature => 45,
        VitalType.respiratoryRate => 60,
        VitalType.systolic => 260,
        VitalType.diastolic => 160,
      };

  /// App-configured attention thresholds (rule-based, NOT a diagnosis).
  double get alertLow => switch (this) {
        VitalType.heartRate => 45,
        VitalType.spo2 => 94,
        VitalType.temperature => 35.8,
        VitalType.respiratoryRate => 10,
        VitalType.systolic => 90,
        VitalType.diastolic => 55,
      };

  double get alertHigh => switch (this) {
        VitalType.heartRate => 120,
        VitalType.spo2 => 101, // upper bound not applicable
        VitalType.temperature => 37.8,
        VitalType.respiratoryRate => 22,
        VitalType.systolic => 140,
        VitalType.diastolic => 90,
      };

  double get critLow => switch (this) {
        VitalType.heartRate => 40,
        VitalType.spo2 => 90,
        VitalType.temperature => 35,
        VitalType.respiratoryRate => 8,
        VitalType.systolic => 80,
        VitalType.diastolic => 45,
      };

  double get critHigh => switch (this) {
        VitalType.heartRate => 150,
        VitalType.spo2 => 101,
        VitalType.temperature => 39,
        VitalType.respiratoryRate => 30,
        VitalType.systolic => 180,
        VitalType.diastolic => 110,
      };

  /// Smallest change vs baseline worth reporting as an insight.
  double get practicalDelta => switch (this) {
        VitalType.heartRate => 6,
        VitalType.spo2 => 1.5,
        VitalType.temperature => 0.3,
        VitalType.respiratoryRate => 2,
        VitalType.systolic => 8,
        VitalType.diastolic => 5,
      };

  /// Nominal sampling interval used for gap / coverage detection.
  int get nominalIntervalSec => (this == VitalType.systolic || this == VitalType.diastolic) ? 300 : 60;

  String get apiField => switch (this) {
        VitalType.heartRate => 'heart_rate_bpm',
        VitalType.spo2 => 'spo2_percent',
        VitalType.temperature => 'temperature_celsius',
        VitalType.respiratoryRate => 'respiratory_rate_bpm',
        VitalType.systolic => 'systolic_mmhg',
        VitalType.diastolic => 'diastolic_mmhg',
      };

  bool get isForecastable => this != VitalType.systolic && this != VitalType.diastolic;
}

enum DataQuality { good, fair, poor, invalid }

enum ObservationSource { demo, ble, gateway, manual }

/// One measured value. `measuredAt` (sensor clock) and `receivedAt` (app clock)
/// are deliberately separate so delayed delivery is visible.
class Observation {
  const Observation({
    required this.astronautId,
    required this.deviceId,
    required this.type,
    required this.value,
    required this.unit,
    required this.measuredAt,
    required this.receivedAt,
    required this.source,
    this.quality = DataQuality.good,
  });

  final String astronautId;
  final String deviceId;
  final VitalType type;
  final double value;
  final String unit;
  final DateTime measuredAt;
  final DateTime receivedAt;
  final ObservationSource source;
  final DataQuality quality;

  /// Natural key used for duplicate detection.
  String get id => '$astronautId|$deviceId|${type.name}|${measuredAt.toUtc().millisecondsSinceEpoch}';
  bool get isSimulated => source == ObservationSource.demo;
  bool get isUsable => quality != DataQuality.invalid;
  Duration get delay => receivedAt.difference(measuredAt);

  Observation withQuality(DataQuality q) => Observation(
        astronautId: astronautId,
        deviceId: deviceId,
        type: type,
        value: value,
        unit: unit,
        measuredAt: measuredAt,
        receivedAt: receivedAt,
        source: source,
        quality: q,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'astronaut_id': astronautId,
        'device_id': deviceId,
        'type': type.name,
        'value': value,
        'unit': unit,
        'measured_at': measuredAt.toUtc().millisecondsSinceEpoch,
        'received_at': receivedAt.toUtc().millisecondsSinceEpoch,
        'source': source.name,
        'quality': quality.name,
        'synced': 0,
      };

  static Observation? fromRow(Map<String, Object?> r) {
    final type = vitalFromKey(r['type'] as String);
    if (type == null) return null;
    return Observation(
      astronautId: r['astronaut_id'] as String,
      deviceId: r['device_id'] as String,
      type: type,
      value: (r['value'] as num).toDouble(),
      unit: r['unit'] as String,
      measuredAt: DateTime.fromMillisecondsSinceEpoch(r['measured_at'] as int, isUtc: true),
      receivedAt: DateTime.fromMillisecondsSinceEpoch(r['received_at'] as int, isUtc: true),
      source: ObservationSource.values.firstWhere(
        (s) => s.name == r['source'],
        orElse: () => ObservationSource.gateway,
      ),
      quality: DataQuality.values.firstWhere(
        (q) => q.name == r['quality'],
        orElse: () => DataQuality.good,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// People and devices
// ---------------------------------------------------------------------------
enum UserRole { astronaut, commander, missionControl }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.astronaut => 'Astronaut',
        UserRole.commander => 'Commander',
        UserRole.missionControl => 'Mission control',
      };
}

class Astronaut {
  const Astronaut({
    required this.id,
    required this.name,
    required this.callsign,
    required this.role,
    this.isDemo = false,
  });
  final String id;
  final String name;
  final String callsign;
  final UserRole role;
  final bool isDemo;

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'callsign': callsign,
        'role': role.name,
        'is_demo': isDemo ? 1 : 0,
      };

  factory Astronaut.fromRow(Map<String, Object?> r) => Astronaut(
        id: r['id'] as String,
        name: r['name'] as String,
        callsign: r['callsign'] as String,
        role: UserRole.values.firstWhere((x) => x.name == r['role'], orElse: () => UserRole.astronaut),
        isDemo: (r['is_demo'] as int? ?? 0) == 1,
      );
}

enum DeviceStatus { online, offline, unknown }

class Device {
  const Device({
    required this.id,
    required this.astronautId,
    required this.name,
    required this.measures,
    this.isDemo = false,
  });
  final String id;
  final String astronautId;
  final String name;
  final List<VitalType> measures;
  final bool isDemo;

  Map<String, Object?> toRow() => {
        'id': id,
        'astronaut_id': astronautId,
        'name': name,
        'measures': measures.map((m) => m.name).join(','),
        'is_demo': isDemo ? 1 : 0,
      };

  factory Device.fromRow(Map<String, Object?> r) => Device(
        id: r['id'] as String,
        astronautId: r['astronaut_id'] as String,
        name: r['name'] as String,
        measures: (r['measures'] as String)
            .split(',')
            .map(vitalFromKey)
            .whereType<VitalType>()
            .toList(),
        isDemo: (r['is_demo'] as int? ?? 0) == 1,
      );
}

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------
enum AlertSeverity { info, warning, critical }

enum AlertStatus { active, acknowledged, resolved }

enum AlertCategory {
  earlyWarning,
  criticalAlert,
  sensorDisconnection,
  poorDataQuality,
  aiServiceUnavailable,
  sosInitiated,
  sosDelivered,
  sosAcknowledged,
}

extension AlertCategoryX on AlertCategory {
  String get label => switch (this) {
        AlertCategory.earlyWarning => 'Early warning',
        AlertCategory.criticalAlert => 'Critical alert',
        AlertCategory.sensorDisconnection => 'Sensor disconnection',
        AlertCategory.poorDataQuality => 'Poor data quality',
        AlertCategory.aiServiceUnavailable => 'AI service unavailable',
        AlertCategory.sosInitiated => 'SOS initiated',
        AlertCategory.sosDelivered => 'SOS delivered',
        AlertCategory.sosAcknowledged => 'SOS acknowledged',
      };
}

class AlertEvent {
  AlertEvent({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.detail,
    required this.source,
    required this.createdAt,
    this.astronautId,
    this.status = AlertStatus.active,
    this.dedupeKey,
    this.data = const {},
    this.isDemo = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final AlertCategory category;
  final AlertSeverity severity;
  final String title;
  final String detail;

  /// Who produced it: 'ATHERA rules', 'AI service', 'Sensor layer', 'SOS service'.
  final String source;
  final DateTime createdAt;
  final String? astronautId;
  final String? dedupeKey;
  final Map<String, Object?> data;
  final bool isDemo;
  AlertStatus status;
  DateTime updatedAt;

  bool get isOpen => status != AlertStatus.resolved;

  Map<String, Object?> toRow() => {
        'id': id,
        'category': category.name,
        'severity': severity.name,
        'astronaut_id': astronautId,
        'source': source,
        'status': status.name,
        'title': title,
        'detail': detail,
        'dedupe_key': dedupeKey,
        'data': jsonEncode(data),
        'is_demo': isDemo ? 1 : 0,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
      };

  factory AlertEvent.fromRow(Map<String, Object?> r) {
    Map<String, Object?> data = const {};
    try {
      final d = jsonDecode((r['data'] as String?) ?? '{}');
      if (d is Map) data = Map<String, Object?>.from(d);
    } catch (_) {}
    return AlertEvent(
      id: r['id'] as String,
      category: AlertCategory.values.firstWhere((c) => c.name == r['category']),
      severity: AlertSeverity.values.firstWhere((c) => c.name == r['severity']),
      astronautId: r['astronaut_id'] as String?,
      source: r['source'] as String,
      status: AlertStatus.values.firstWhere((c) => c.name == r['status']),
      title: r['title'] as String,
      detail: r['detail'] as String,
      dedupeKey: r['dedupe_key'] as String?,
      data: data,
      isDemo: (r['is_demo'] as int? ?? 0) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int, isUtc: true),
    );
  }
}

// ---------------------------------------------------------------------------
// Emergency
// ---------------------------------------------------------------------------
enum EmergencySeverity { high, critical }

enum DeliveryState { pending, sending, delivered, acknowledged, failed }

enum EmergencyStatus { recorded, sending, partiallyDelivered, delivered, acknowledged, failed, closed }

extension EmergencyStatusX on EmergencyStatus {
  String get label => switch (this) {
        EmergencyStatus.recorded => 'Recorded locally',
        EmergencyStatus.sending => 'Sending',
        EmergencyStatus.partiallyDelivered => 'Partially delivered',
        EmergencyStatus.delivered => 'Delivered',
        EmergencyStatus.acknowledged => 'Acknowledged',
        EmergencyStatus.failed => 'Not delivered',
        EmergencyStatus.closed => 'Closed',
      };
}

class Delivery {
  Delivery({
    required this.recipientId,
    required this.recipientName,
    this.state = DeliveryState.pending,
    this.attempts = 0,
    this.via,
    this.lastError,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  final String recipientId;
  final String recipientName;
  DeliveryState state;
  int attempts;
  String? via;
  String? lastError;
  DateTime updatedAt;

  Map<String, Object?> toJson() => {
        'recipient_id': recipientId,
        'recipient_name': recipientName,
        'state': state.name,
        'attempts': attempts,
        'via': via,
        'last_error': lastError,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
        recipientId: j['recipient_id'] as String,
        recipientName: j['recipient_name'] as String,
        state: DeliveryState.values.firstWhere((s) => s.name == j['state'], orElse: () => DeliveryState.pending),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        via: j['via'] as String?,
        lastError: j['last_error'] as String?,
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class TimelineEntry {
  TimelineEntry(this.at, this.text);
  final DateTime at;
  final String text;
  Map<String, Object?> toJson() => {'at': at.toUtc().toIso8601String(), 'text': text};
  factory TimelineEntry.fromJson(Map<String, dynamic> j) =>
      TimelineEntry(DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(), j['text'] as String? ?? '');
}

class EmergencyEvent {
  EmergencyEvent({
    required this.id,
    required this.astronautId,
    required this.deviceId,
    required this.severity,
    required this.manual,
    required this.createdAt,
    required this.deliveries,
    required this.transportName,
    required this.simulated,
    this.snapshot = const {},
    this.closed = false,
    this.transportAvailable = true,
    List<TimelineEntry>? timeline,
  }) : timeline = timeline ?? [];

  /// UUID v4, also used as the wire event id for duplicate detection.
  final String id;
  final String astronautId;
  final String deviceId;
  final EmergencySeverity severity;
  final bool manual;
  final DateTime createdAt;
  final List<Delivery> deliveries;
  final String transportName;
  final bool simulated;
  final bool transportAvailable;

  /// Minimal vitals snapshot: key -> {value, unit, at}.
  final Map<String, Object?> snapshot;
  final List<TimelineEntry> timeline;
  bool closed;

  EmergencyStatus get status {
    if (closed) return EmergencyStatus.closed;
    if (!transportAvailable) return EmergencyStatus.failed;
    if (deliveries.isEmpty) return EmergencyStatus.recorded;
    if (deliveries.any((d) => d.state == DeliveryState.acknowledged)) return EmergencyStatus.acknowledged;
    if (deliveries.every((d) => d.state == DeliveryState.delivered)) return EmergencyStatus.delivered;
    if (deliveries.any((d) => d.state == DeliveryState.delivered)) return EmergencyStatus.partiallyDelivered;
    if (deliveries.every((d) => d.state == DeliveryState.failed)) return EmergencyStatus.failed;
    return EmergencyStatus.sending;
  }

  void log(String text) => timeline.add(TimelineEntry(DateTime.now(), text));

  Map<String, Object?> toRow() => {
        'id': id,
        'astronaut_id': astronautId,
        'created_at': createdAt.toUtc().millisecondsSinceEpoch,
        'is_demo': simulated ? 1 : 0,
        'json': jsonEncode({
          'device_id': deviceId,
          'severity': severity.name,
          'manual': manual,
          'transport_name': transportName,
          'simulated': simulated,
          'transport_available': transportAvailable,
          'closed': closed,
          'snapshot': snapshot,
          'deliveries': deliveries.map((d) => d.toJson()).toList(),
          'timeline': timeline.map((t) => t.toJson()).toList(),
        }),
      };

  factory EmergencyEvent.fromRow(Map<String, Object?> r) {
    final j = jsonDecode(r['json'] as String) as Map<String, dynamic>;
    return EmergencyEvent(
      id: r['id'] as String,
      astronautId: r['astronaut_id'] as String,
      deviceId: j['device_id'] as String? ?? 'unknown',
      severity: EmergencySeverity.values.firstWhere(
        (s) => s.name == j['severity'],
        orElse: () => EmergencySeverity.critical,
      ),
      manual: j['manual'] as bool? ?? true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int, isUtc: true),
      transportName: j['transport_name'] as String? ?? 'unknown',
      simulated: j['simulated'] as bool? ?? false,
      transportAvailable: j['transport_available'] as bool? ?? true,
      closed: j['closed'] as bool? ?? false,
      snapshot: Map<String, Object?>.from((j['snapshot'] as Map?) ?? const {}),
      deliveries: ((j['deliveries'] as List?) ?? const [])
          .map((e) => Delivery.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      timeline: ((j['timeline'] as List?) ?? const [])
          .map((e) => TimelineEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Connectivity
// ---------------------------------------------------------------------------
enum LinkTransport { bluetooth, localNetwork, meshRelay, baseStation }

extension LinkTransportX on LinkTransport {
  String get label => switch (this) {
        LinkTransport.bluetooth => 'Bluetooth',
        LinkTransport.localNetwork => 'Local network',
        LinkTransport.meshRelay => 'Mesh relay',
        LinkTransport.baseStation => 'Base station',
      };
}

/// Topology/transport info for one crew member. Whether the member is actually
/// connected is derived from data freshness by the controller, never faked here.
class CrewLink {
  const CrewLink({
    required this.astronautId,
    required this.transport,
    this.viaId,
    this.linkQuality,
    this.distanceMeters,
    this.lastSyncAt,
    this.simulated = false,
  });
  final String astronautId;
  final LinkTransport transport;

  /// Node this member links through (another astronaut id, or 'base').
  final String? viaId;

  /// 0..1 — only present if a real transport reports it (or demo, flagged).
  final double? linkQuality;

  /// Only present when real positioning data exists.
  final double? distanceMeters;
  final DateTime? lastSyncAt;
  final bool simulated;
}

class SyncRecord {
  const SyncRecord({
    required this.id,
    required this.kind,
    required this.startedAt,
    required this.count,
    required this.status,
    this.note = '',
  });
  final String id;
  final String kind;
  final DateTime startedAt;
  final int count;
  final String status;
  final String note;
}
