import '../domain/models.dart';

/// A body system shown on the interactive body map.
class BodySystem {
  const BodySystem({
    required this.id,
    required this.name,
    required this.does,
    required this.spaceEffect,
    required this.howToMeasure,
    required this.seeDoctorIf,
    required this.vitals,
    required this.hazards,
  });
  final String id;
  final String name;
  final String does;
  final String spaceEffect;
  final String howToMeasure;
  final String seeDoctorIf;
  final List<VitalType> vitals;

  /// Ids from [kHazards] that mostly affect this system.
  final List<String> hazards;
}

const List<BodySystem> kBodySystems = [
  BodySystem(
    id: 'mind',
    name: 'Brain and mind',
    does: 'Thinking, mood, sleep and the stress response.',
    spaceEffect:
        'Isolation, a confined space and disturbed day-night cycles can lower mood, shorten sleep and raise stress.',
    howToMeasure: 'Use the daily check-in: hours slept, mood, fatigue and stress. A wearable can add a stress index (HRV).',
    seeDoctorIf: 'Low mood for several days, very little sleep, or thoughts that worry you. Ask early.',
    vitals: [],
    hazards: ['isolation', 'radiation'],
  ),
  BodySystem(
    id: 'heart',
    name: 'Heart and blood vessels',
    does: 'Pumps blood to every organ. Heart rate and blood pressure show how hard it is working.',
    spaceEffect:
        'Without gravity the heart and vessels do less work and can weaken, and blood shifts toward the head. Standing up after return can cause dizziness.',
    howToMeasure:
        'Sit for 5 minutes, arm at heart level, cuff on bare skin, no talking. Measure at the same time each day.',
    seeDoctorIf: 'Chest pain, fainting, a racing or very slow pulse, or blood pressure that stays high or low.',
    vitals: [VitalType.heartRate, VitalType.systolic, VitalType.diastolic],
    hazards: ['gravity', 'radiation'],
  ),
  BodySystem(
    id: 'lungs',
    name: 'Lungs and breathing',
    does: 'Bring oxygen into the blood. Blood oxygen (SpO₂) and breathing rate show how well it works.',
    spaceEffect:
        'Cabin air quality, dust and carbon dioxide matter more in a sealed spacecraft. Low oxygen or high CO₂ can cause headache and tiredness.',
    howToMeasure: 'Warm hands, sensor snug on the fingertip, stay still for 30 seconds. Count breaths for a full minute.',
    seeDoctorIf: 'SpO₂ below 94%, breathlessness at rest, or a headache with a stuffy feeling that others share.',
    vitals: [VitalType.spo2, VitalType.respiratoryRate],
    hazards: ['closed'],
  ),
  BodySystem(
    id: 'body',
    name: 'Whole body and immunity',
    does: 'Body temperature reflects infection, heat stress and recovery.',
    spaceEffect: 'Spaceflight changes immune function, and a closed cabin spreads germs. Heat is harder to shed in a suit.',
    howToMeasure: 'Measure core or oral temperature before exercise and before a hot drink.',
    seeDoctorIf: 'Temperature above 37.8 °C, chills, or a fever that lasts more than a day.',
    vitals: [VitalType.temperature],
    hazards: ['radiation', 'closed'],
  ),
  BodySystem(
    id: 'muscle',
    name: 'Muscles and bones',
    does: 'Hold the body up and move it. Bones also store calcium.',
    spaceEffect:
        'Weightlessness removes the load that keeps bones and muscles strong, so they weaken without exercise.',
    howToMeasure: 'ATHERA tracks your exercise routine. Bone density and muscle tests are done by medical teams.',
    seeDoctorIf: 'New bone or joint pain, or a sudden drop in strength or balance.',
    vitals: [],
    hazards: ['gravity'],
  ),
];
