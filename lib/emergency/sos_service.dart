import 'dart:async';

import 'package:uuid/uuid.dart';

import '../data/repository.dart';
import '../domain/models.dart';
import 'transport.dart';

class Recipient {
  const Recipient(this.id, this.name);
  final String id;
  final String name;
}

typedef AlertSink = void Function(AlertCategory category, AlertSeverity severity, EmergencyEvent event, String detail);

/// Emergency workflow: record locally -> hand to transport -> track delivery
/// and acknowledgement -> keep history. It never reports "delivered" unless the
/// transport said so.
class SosService {
  SosService({
    required this.repo,
    required EmergencyTransport transport,
    required this.onAlert,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(seconds: 8),
    Uuid? uuid,
  })  : _transport = transport,
        _uuid = uuid ?? const Uuid() {
    _bind();
  }

  final AtheraRepository repo;
  final AlertSink onAlert;
  final int maxAttempts;
  final Duration retryDelay;
  final Uuid _uuid;

  EmergencyTransport _transport;
  StreamSubscription<TransportEvent>? _sub;
  final Map<String, EmergencyEvent> _events = {};
  final Map<String, EmergencyMessage> _messages = {};
  final Set<String> _seenIds = {};
  final Set<String> _alerted = {};
  final List<Timer> _timers = [];

  /// Called after any state change so the UI can rebuild.
  void Function()? onChanged;

  EmergencyTransport get transport => _transport;

  List<EmergencyEvent> get events {
    final l = _events.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return l;
  }

  EmergencyEvent? get active {
    for (final e in events) {
      if (!e.closed) return e;
    }
    return null;
  }

  Future<void> load() async {
    for (final e in await repo.emergencies()) {
      _events[e.id] = e;
      _seenIds.add(e.id);
    }
    onChanged?.call();
  }

  void setTransport(EmergencyTransport t) {
    _sub?.cancel();
    _transport = t;
    _bind();
  }

  void _bind() {
    _sub = _transport.events.listen(_onTransportEvent);
  }

  /// Start an emergency. Returns the recorded event whatever the transport does.
  Future<EmergencyEvent> trigger({
    required Astronaut origin,
    required String deviceId,
    required List<Recipient> recipients,
    required EmergencySeverity severity,
    required bool manual,
    Map<String, Object?> snapshot = const {},
    double? heartRate,
    double? spo2,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final event = EmergencyEvent(
      id: id,
      astronautId: origin.id,
      deviceId: deviceId,
      severity: severity,
      manual: manual,
      createdAt: now,
      deliveries: [for (final r in recipients) Delivery(recipientId: r.id, recipientName: r.name)],
      transportName: _transport.name,
      simulated: _transport.isSimulated,
      snapshot: snapshot,
      transportAvailable: _transport.isAvailable,
    );
    event.log(manual ? 'SOS initiated manually by ${origin.callsign}' : 'Emergency detected automatically');
    event.log('Event recorded locally (id ${id.substring(0, 8)})');
    _events[id] = event;
    _seenIds.add(id);
    await repo.saveEmergency(event);
    onAlert(AlertCategory.sosInitiated, AlertSeverity.critical, event,
        '${origin.name} initiated an SOS (${severity.name}).${_transport.isSimulated ? ' SIMULATED transport.' : ''}');
    onChanged?.call();

    if (!_transport.isAvailable) {
      event.log('NOT SENT: no emergency transport is configured. The event exists only on this device.');
      for (final d in event.deliveries) {
        d.state = DeliveryState.failed;
        d.lastError = 'No transport';
      }
      await _persist(event);
      return event;
    }

    final message = EmergencyMessage(
      eventId: id,
      originAstronautId: origin.id,
      originDeviceId: deviceId,
      severity: severity,
      createdAt: now,
      manual: manual,
      heartRate: heartRate,
      spo2: spo2,
    );
    _messages[id] = message;
    await _attempt(event, message, event.deliveries);
    return event;
  }

  Future<void> _attempt(EmergencyEvent event, EmergencyMessage message, List<Delivery> targets) async {
    for (final d in targets) {
      d.state = DeliveryState.sending;
      d.attempts += 1;
      d.updatedAt = DateTime.now();
    }
    event.log(
      'Handing message to "${_transport.name}" for ${targets.map((d) => d.recipientName).join(', ')} '
      '(attempt ${targets.first.attempts}/$maxAttempts)${_transport.isSimulated ? ' — SIMULATED' : ''}',
    );
    await _persist(event);
    try {
      await _transport.send(message, targets.map((d) => d.recipientId).toList());
    } on TransportUnavailable catch (e) {
      for (final d in targets) {
        d.state = DeliveryState.failed;
        d.lastError = e.reason;
      }
      event.log('Transport refused the message: ${e.reason}');
      await _persist(event);
    } catch (e) {
      for (final d in targets) {
        d.state = DeliveryState.failed;
        d.lastError = e.toString();
      }
      event.log('Transport error: $e');
      await _persist(event);
    }
  }

  void _onTransportEvent(TransportEvent te) {
    final event = _events[te.eventId];
    if (event == null) return;
    Delivery? d;
    for (final x in event.deliveries) {
      if (x.recipientId == te.recipientId) d = x;
    }
    if (d == null) return;
    final sim = event.simulated ? ' (SIMULATED)' : '';
    switch (te.kind) {
      case TransportEventKind.delivered:
        if (d.state == DeliveryState.acknowledged) return; // duplicate/late event
        d.state = DeliveryState.delivered;
        d.via = te.via;
        d.lastError = null;
        event.log('Delivered to ${d.recipientName}${te.via != null ? ' via ${te.via}' : ''}$sim');
        if (_alerted.add('${event.id}:delivered')) {
          onAlert(AlertCategory.sosDelivered, AlertSeverity.warning, event, 'SOS reached ${d.recipientName}$sim.');
        }
      case TransportEventKind.acknowledged:
        d.state = DeliveryState.acknowledged;
        d.via = te.via ?? d.via;
        event.log('Acknowledged by ${d.recipientName}$sim');
        if (_alerted.add('${event.id}:ack')) {
          onAlert(AlertCategory.sosAcknowledged, AlertSeverity.info, event, '${d.recipientName} acknowledged the SOS$sim.');
        }
      case TransportEventKind.failed:
        d.lastError = te.error;
        if (d.attempts < maxAttempts && _messages.containsKey(event.id)) {
          d.state = DeliveryState.sending;
          event.log('Delivery to ${d.recipientName} failed (${te.error ?? 'no response'}). Retrying in ${retryDelay.inSeconds}s.');
          final target = d;
          _timers.add(Timer(retryDelay, () {
            if (event.closed) return;
            _attempt(event, _messages[event.id]!, [target]).then((_) => onChanged?.call());
          }));
        } else {
          d.state = DeliveryState.failed;
          event.log('Delivery to ${d.recipientName} failed after ${d.attempts} attempt(s). Giving up.');
        }
    }
    d.updatedAt = DateTime.now();
    _persist(event);
  }

  /// Handle a message that arrived FROM another device. Returns false when it
  /// is a duplicate (same event id) and was ignored.
  Future<bool> receive(EmergencyMessage m, {required String via, required String receiverId}) async {
    if (_seenIds.contains(m.eventId)) return false;
    _seenIds.add(m.eventId);
    final event = EmergencyEvent(
      id: m.eventId,
      astronautId: m.originAstronautId,
      deviceId: m.originDeviceId,
      severity: m.severity,
      manual: m.manual,
      createdAt: m.createdAt,
      deliveries: const [],
      transportName: via,
      simulated: _transport.isSimulated,
      snapshot: {
        if (m.heartRate != null) 'heartRate': {'value': m.heartRate, 'unit': 'bpm'},
        if (m.spo2 != null) 'spo2': {'value': m.spo2, 'unit': '%'},
      },
    );
    event.log('Received from ${m.originAstronautId} via $via');
    _events[m.eventId] = event;
    await _persist(event);
    onAlert(AlertCategory.sosInitiated, AlertSeverity.critical, event, 'Incoming SOS from ${m.originAstronautId} via $via.');
    return true;
  }

  Future<void> close(String eventId) async {
    final e = _events[eventId];
    if (e == null) return;
    e.closed = true;
    e.log('Event closed locally by operator (no cancellation was sent to recipients)');
    await _persist(e);
  }

  Future<void> _persist(EmergencyEvent e) async {
    try {
      await repo.saveEmergency(e);
    } catch (_) {
      // Persistence failure must never break the live workflow.
    }
    onChanged?.call();
  }

  void dispose() {
    _sub?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
  }
}
