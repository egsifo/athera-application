import 'package:athera/data/memory_repository.dart';
import 'package:athera/domain/models.dart';
import 'package:athera/emergency/sos_service.dart';
import 'package:athera/emergency/transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const origin = Astronaut(id: 'a1', name: 'Test Astronaut', callsign: 'TEST', role: UserRole.astronaut);

  test('without a transport the SOS is recorded locally and honestly reported as not delivered', () async {
    final repo = MemoryRepository();
    final raised = <AlertCategory>[];
    final sos = SosService(repo: repo, transport: UnavailableTransport(), onAlert: (c, s, e, d) => raised.add(c));
    addTearDown(sos.dispose);

    final e = await sos.trigger(
      origin: origin,
      deviceId: 'dev1',
      recipients: const [Recipient('base', 'Base station')],
      severity: EmergencySeverity.critical,
      manual: true,
    );

    expect(e.status, EmergencyStatus.failed);
    expect(e.deliveries.every((d) => d.state == DeliveryState.failed), isTrue);
    expect(e.timeline.any((t) => t.text.contains('NOT SENT')), isTrue);
    expect(raised, [AlertCategory.sosInitiated]);
    expect((await repo.emergencies()).length, 1);
  });

  test('each SOS gets a unique event id', () async {
    final sos = SosService(repo: MemoryRepository(), transport: UnavailableTransport(), onAlert: (c, s, e, d) {});
    addTearDown(sos.dispose);
    Future<EmergencyEvent> go() => sos.trigger(
          origin: origin,
          deviceId: 'dev1',
          recipients: const [Recipient('base', 'Base')],
          severity: EmergencySeverity.high,
          manual: true,
        );
    final a = await go();
    final b = await go();
    expect(a.id, isNot(b.id));
    expect(sos.events.length, 2);
  });

  test('the wire message is minimal and round-trips', () {
    final m = EmergencyMessage(
      eventId: 'e1',
      originAstronautId: 'a1',
      originDeviceId: 'dev1',
      severity: EmergencySeverity.critical,
      createdAt: DateTime.utc(2026, 10, 19, 12),
      manual: true,
      heartRate: 120,
    );
    final wire = m.toWire();
    expect(wire.keys.toSet(), {'v', 'id', 'who', 'dev', 'sev', 'ts', 'man', 'hr'});
    final back = EmergencyMessage.fromWire(wire);
    expect(back.eventId, 'e1');
    expect(back.heartRate, 120);
    expect(back.spo2, isNull);
    expect(back.createdAt, m.createdAt);
  });
}
