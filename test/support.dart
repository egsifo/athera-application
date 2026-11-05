import 'package:athera/domain/models.dart';

Observation obs(
  VitalType t,
  double v,
  DateTime at, {
  String astronaut = 'a1',
  String device = 'dev1',
  ObservationSource source = ObservationSource.demo,
  DateTime? received,
}) =>
    Observation(
      astronautId: astronaut,
      deviceId: device,
      type: t,
      value: v,
      unit: t.unit,
      measuredAt: at,
      receivedAt: received ?? at,
      source: source,
    );
