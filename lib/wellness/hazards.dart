import '../domain/models.dart';

/// One of the five spaceflight hazards mapped by NASA's Human Research Program.
class SpaceHazard {
  const SpaceHazard({
    required this.id,
    required this.name,
    required this.summary,
    required this.effects,
    required this.watch,
    required this.habit,
    required this.vitals,
  });
  final String id;
  final String name;
  final String summary;

  /// Health effects that are known or studied for this hazard.
  final List<String> effects;

  /// What ATHERA tracks for it.
  final List<String> watch;

  /// A practical daily habit that helps.
  final String habit;

  /// Vital signs most connected to this hazard (used to show live status).
  final List<VitalType> vitals;
}

const List<SpaceHazard> kHazards = [
  SpaceHazard(
    id: 'radiation',
    name: 'Space radiation',
    summary: 'Beyond Earth\'s protective magnetic field, crews are exposed to cosmic rays and solar particle events.',
    effects: [
      'Long-term cancer risk',
      'Effects on the brain and nervous system',
      'Possible damage to the heart and blood vessels',
    ],
    watch: ['Radiation level (from a dosimeter, when available)', 'Body temperature', 'Sleep and fatigue'],
    habit: 'Follow shelter instructions during solar events and log every dosimeter reading.',
    vitals: [VitalType.temperature],
  ),
  SpaceHazard(
    id: 'isolation',
    name: 'Isolation and confinement',
    summary: 'Small crews in a small space for months, far from family and friends.',
    effects: [
      'Low mood, stress and anxiety',
      'Disturbed sleep and fatigue',
      'Tension within the crew and slower thinking',
    ],
    watch: ['Daily mood, stress and fatigue check-in', 'Hours of sleep', 'Stress index from a wearable (HRV)'],
    habit: 'Do the daily check-in honestly, keep a sleep routine, and talk early.',
    vitals: [VitalType.heartRate],
  ),
  SpaceHazard(
    id: 'distance',
    name: 'Distance from Earth',
    summary: 'On the Moon help is days away, and on Mars a message needs up to 22 minutes each way.',
    effects: [
      'No quick evacuation or resupply',
      'Delayed advice from doctors on the ground',
      'Crews must assess and treat many problems themselves',
    ],
    watch: ['Self-assessment guidance', 'Delay-aware flight-surgeon brief', 'Works without a connection'],
    habit: 'Send a clear brief early, then act on your onboard procedures while you wait.',
    vitals: [],
  ),
  SpaceHazard(
    id: 'gravity',
    name: 'Altered gravity',
    summary: 'Weightlessness in flight, then partial gravity on arrival: about 38% of Earth\'s on Mars and 17% on the Moon.',
    effects: [
      'Bone and muscle loss',
      'Fluids shifting toward the head',
      'Weaker heart and blood vessels',
      'Balance problems and vision changes',
    ],
    watch: ['Blood pressure and heart rate', 'Exercise adherence', 'Orthostatic symptoms after standing'],
    habit: 'Never skip the exercise session: it is the main protection for bones and muscles.',
    vitals: [VitalType.systolic, VitalType.diastolic, VitalType.heartRate],
  ),
  SpaceHazard(
    id: 'closed',
    name: 'Hostile, closed environment',
    summary: 'The spacecraft air, water, noise, temperature and microbes are all managed by machines.',
    effects: [
      'Falling oxygen or rising carbon dioxide',
      'Infections and allergic reactions',
      'Noise, heat and lack of sleep',
    ],
    watch: ['Blood oxygen (SpO₂)', 'Respiratory rate', 'Body temperature'],
    habit: 'Report headaches, breathlessness or odd smells early: they can point to the air, not to you.',
    vitals: [VitalType.spo2, VitalType.respiratoryRate, VitalType.temperature],
  ),
];
