import '../wellness/check_in.dart';
import 'laila.dart';

/// Astro Mind simulation scenarios. Every value is SIMULATED (CheckIn.isDemo = true)
/// and generated deterministically, so they are repeatable and testable.
enum MindScenario { healthy, lonely, depressionLike, severeDistress, recovery }

extension MindScenarioX on MindScenario {
  String get label => switch (this) {
        MindScenario.healthy => 'Healthy and happy',
        MindScenario.lonely => 'Lonely astronaut',
        MindScenario.depressionLike => 'Depression-like symptoms',
        MindScenario.severeDistress => 'Severe psychological distress',
        MindScenario.recovery => 'Recovery and improvement',
      };

  String get note => switch (this) {
        MindScenario.depressionLike => 'A simulation of depression-like symptoms. It is NOT a clinical diagnosis.',
        MindScenario.severeDistress => 'Simulated distress. It triggers the urgent human-support protocol.',
        _ => 'Simulated self-reports. Not real astronaut data.',
      };

  LailaScenario get laila => switch (this) {
        MindScenario.healthy => LailaScenario.none,
        MindScenario.lonely => LailaScenario.lonely,
        MindScenario.depressionLike => LailaScenario.sadness,
        MindScenario.severeDistress => LailaScenario.sadness,
        MindScenario.recovery => LailaScenario.recovering,
      };
}

class MindScenarioSpec {
  const MindScenarioSpec(this.mood, this.stress, this.fatigue, this.sleep);

  /// (start, end) over the scenario.
  final (double, double) mood, stress, fatigue, sleep;
}

const kMindDays = 14;

const _specs = <MindScenario, MindScenarioSpec>{
  MindScenario.healthy: MindScenarioSpec((4.6, 4.4), (1.6, 1.8), (1.6, 1.8), (7.8, 7.6)),
  MindScenario.lonely: MindScenarioSpec((4.2, 2.2), (2.0, 3.4), (2.0, 3.2), (7.2, 5.8)),
  MindScenario.depressionLike: MindScenarioSpec((3.2, 1.2), (3.0, 4.2), (2.2, 4.8), (6.6, 4.4)),
  MindScenario.severeDistress: MindScenarioSpec((2.0, 1.0), (4.0, 5.0), (4.0, 5.0), (4.8, 3.0)),
  MindScenario.recovery: MindScenarioSpec((1.8, 4.4), (4.4, 1.8), (4.4, 1.8), (4.2, 7.4)),
};

/// Check-ins for days 0..[days]-1, oldest first, ending today at [today] (UTC midday).
List<CheckIn> buildMindScenario(MindScenario s, {required String astronautId, required DateTime today, int days = kMindDays}) {
  final spec = _specs[s]!;
  double at((double, double) r, int d) => r.$1 + (r.$2 - r.$1) * (d / (kMindDays - 1));
  return [
    for (var d = 0; d < days; d++)
      CheckIn(
        id: 'sim-${s.name}-$d',
        astronautId: astronautId,
        at: DateTime.utc(today.year, today.month, today.day, 12).subtract(Duration(days: kMindDays - 1 - d)),
        sleepHours: double.parse(at(spec.sleep, d).toStringAsFixed(1)),
        mood: at(spec.mood, d).round().clamp(1, 5),
        fatigue: at(spec.fatigue, d).round().clamp(1, 5),
        stress: at(spec.stress, d).round().clamp(1, 5),
        note: 'SIMULATION',
        isDemo: true,
      ),
  ];
}
