import 'dart:async';

import '../domain/models.dart';

/// Minimal SOS payload. Only what a receiver needs, small enough for
/// constrained links (BLE characteristic, LoRa frame).
class EmergencyMessage {
  const EmergencyMessage({
    required this.eventId,
    required this.originAstronautId,
    required this.originDeviceId,
    required this.severity,
    required this.createdAt,
    required this.manual,
    this.heartRate,
    this.spo2,
  });

  /// UUID v4. Receivers use it to drop duplicates (the same event may arrive
  /// several times via retries and relays).
  final String eventId;
  final String originAstronautId;
  final String originDeviceId;
  final EmergencySeverity severity;
  final DateTime createdAt;
  final bool manual;
  final double? heartRate;
  final double? spo2;

  Map<String, Object?> toWire() => {
        'v': 1,
        'id': eventId,
        'who': originAstronautId,
        'dev': originDeviceId,
        'sev': severity.name,
        'ts': createdAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        'man': manual,
        if (heartRate != null) 'hr': heartRate,
        if (spo2 != null) 'spo2': spo2,
      };

  factory EmergencyMessage.fromWire(Map<String, Object?> m) => EmergencyMessage(
        eventId: m['id'] as String,
        originAstronautId: m['who'] as String,
        originDeviceId: (m['dev'] as String?) ?? 'unknown',
        severity: EmergencySeverity.values.firstWhere(
          (s) => s.name == m['sev'],
          orElse: () => EmergencySeverity.critical,
        ),
        createdAt: DateTime.fromMillisecondsSinceEpoch(((m['ts'] as num).toInt()) * 1000, isUtc: true),
        manual: (m['man'] as bool?) ?? true,
        heartRate: (m['hr'] as num?)?.toDouble(),
        spo2: (m['spo2'] as num?)?.toDouble(),
      );
}

class TransportCapabilities {
  const TransportCapabilities({this.supportsAck = false, this.supportsRelay = false, this.maxPayloadBytes});
  final bool supportsAck;
  final bool supportsRelay;
  final int? maxPayloadBytes;
}

enum TransportEventKind { delivered, acknowledged, failed }

class TransportEvent {
  const TransportEvent({
    required this.eventId,
    required this.recipientId,
    required this.kind,
    required this.at,
    this.via,
    this.error,
  });
  final String eventId;
  final String recipientId;
  final TransportEventKind kind;
  final DateTime at;
  final String? via;
  final String? error;
}

class TransportUnavailable implements Exception {
  TransportUnavailable(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Delivery mechanism for emergency messages. Implementations (future):
///  * BLE: a custom GATT service between paired devices. BLE is point-to-point;
///    it is NOT a mesh network. Multi-hop needs Bluetooth Mesh or an app-level relay.
///  * LoRa: an external radio module with its own firmware, bridged to the phone.
///  * Habitat Wi-Fi / base-station link.
/// The service reports outcomes through [events]; a send() that returns means
/// "handed to the transport", NOT "delivered".
abstract class EmergencyTransport {
  String get name;
  bool get isSimulated;
  bool get isAvailable;
  TransportCapabilities get capabilities;
  Stream<TransportEvent> get events;
  Future<void> send(EmergencyMessage message, List<String> recipientIds);
  void dispose();
}

/// Used when no real transport exists. Sending always fails explicitly.
class UnavailableTransport implements EmergencyTransport {
  @override
  String get name => 'No transport configured';
  @override
  bool get isSimulated => false;
  @override
  bool get isAvailable => false;
  @override
  TransportCapabilities get capabilities => const TransportCapabilities();
  @override
  Stream<TransportEvent> get events => const Stream.empty();
  @override
  Future<void> send(EmergencyMessage message, List<String> recipientIds) async {
    throw TransportUnavailable('No emergency transport is configured in this build.');
  }

  @override
  void dispose() {}
}

/// Simulated transport: every outcome is scripted and clearly labelled
/// SIMULATED in the timeline. It proves the workflow, not radio coverage.
class DemoTransport implements EmergencyTransport {
  DemoTransport({this.unreachable = const {'demo-astronaut-04'}, this.speed = 1.0});

  /// Recipients that never answer (simulates an offline device).
  final Set<String> unreachable;

  /// 1.0 = real-time delays (2-8 s); use a larger number in tests.
  final double speed;
  final StreamController<TransportEvent> _ctrl = StreamController.broadcast();
  final Set<String> _delivered = {};
  final List<Timer> _timers = [];

  @override
  String get name => 'Simulated transport (DEMO)';
  @override
  bool get isSimulated => true;
  @override
  bool get isAvailable => true;
  @override
  TransportCapabilities get capabilities =>
      const TransportCapabilities(supportsAck: true, supportsRelay: true, maxPayloadBytes: 240);
  @override
  Stream<TransportEvent> get events => _ctrl.stream;

  void _later(double seconds, TransportEvent e) {
    _timers.add(Timer(Duration(milliseconds: (seconds * 1000 / speed).round()), () {
      if (!_ctrl.isClosed) _ctrl.add(e);
    }));
  }

  @override
  Future<void> send(EmergencyMessage message, List<String> recipientIds) async {
    var i = 0;
    for (final r in recipientIds) {
      i++;
      final key = '${message.eventId}|$r';
      if (unreachable.contains(r)) {
        _later(2.0 + i * 0.5, TransportEvent(eventId: message.eventId, recipientId: r, kind: TransportEventKind.failed, at: DateTime.now(), error: 'No response (simulated: device offline)'));
        continue;
      }
      if (_delivered.contains(key)) continue; // duplicate send: ignore
      _delivered.add(key);
      final via = r == 'base'
          ? 'simulated direct link'
          : (r == 'demo-astronaut-03' ? 'simulated mesh relay via demo-astronaut-02' : 'simulated Bluetooth link');
      _later(1.5 + i * 0.7, TransportEvent(eventId: message.eventId, recipientId: r, kind: TransportEventKind.delivered, at: DateTime.now(), via: via));
      // Only some recipients acknowledge, to show partial states.
      if (r == 'base' || r == 'demo-astronaut-02') {
        _later(6.0 + i, TransportEvent(eventId: message.eventId, recipientId: r, kind: TransportEventKind.acknowledged, at: DateTime.now(), via: via));
      }
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _ctrl.close();
  }
}
