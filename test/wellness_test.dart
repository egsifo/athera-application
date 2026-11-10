import 'package:athera/domain/ai_models.dart';
import 'package:athera/domain/models.dart';
import 'package:athera/wellness/brief.dart';
import 'package:athera/wellness/check_in.dart';
import 'package:athera/wellness/guidance.dart';
import 'package:athera/wellness/mission_env.dart';
import 'package:athera/wellness/routine.dart';
import 'package:flutter_test/flutter_test.dart';

CheckIn ci({double sleep = 7, int mood = 3, int fatigue = 2, int stress = 2, double? glucose, DateTime? at}) => CheckIn(
      id: 'c',
      astronautId: 'a1',
      at: at ?? DateTime.utc(2030, 1, 1, 12),
      sleepHours: sleep,
      mood: mood,
      fatigue: fatigue,
      stress: stress,
      glucoseMgDl: glucose,
    );

void main() {
  group('CheckIn', () {
    test('validate accepts plausible values', () {
      expect(CheckIn.validate(sleepHours: 7, mood: 3, fatigue: 2, stress: 2), isNull);
      expect(CheckIn.validate(sleepHours: 7, mood: 3, fatigue: 2, stress: 2, glucoseMgDl: 95), isNull);
    });
    test('validate rejects out-of-range values', () {
      expect(CheckIn.validate(sleepHours: 25, mood: 3, fatigue: 2, stress: 2), isNotNull);
      expect(CheckIn.validate(sleepHours: double.nan, mood: 3, fatigue: 2, stress: 2), isNotNull);
      expect(CheckIn.validate(sleepHours: 7, mood: 0, fatigue: 2, stress: 2), isNotNull);
      expect(CheckIn.validate(sleepHours: 7, mood: 3, fatigue: 6, stress: 2), isNotNull);
      expect(CheckIn.validate(sleepHours: 7, mood: 3, fatigue: 2, stress: 2, glucoseMgDl: 5), isNotNull);
    });
    test('json round trip', () {
      final c = ci(glucose: 101, sleep: 6.5);
      final back = CheckIn.fromJson(c.toJson());
      expect(back.sleepHours, 6.5);
      expect(back.glucoseMgDl, 101);
      expect(back.at, c.at);
    });
  });

  group('MissionEnvironment', () {
    test('Mars is autonomous, station is not', () {
      expect(MissionEnvironment.marsSurface.autonomous, isTrue);
      expect(MissionEnvironment.iss.autonomous, isFalse);
    });
    test('reply window is two one-way trips', () {
      final t = DateTime.utc(2030, 1, 1);
      final (lo, hi) = MissionEnvironment.marsTransit.replyWindow(t);
      expect(lo, t.add(const Duration(minutes: 6)));
      expect(hi, t.add(const Duration(minutes: 44)));
    });
    test('fromName falls back to station', () {
      expect(missionEnvironmentFromName('nonsense'), MissionEnvironment.iss);
      expect(missionEnvironmentFromName('lunar'), MissionEnvironment.lunar);
    });
  });

  group('RoutineProgress', () {
    final now = DateTime(2030, 1, 10, 15);
    List<RoutineLogEntry> fullDay(DateTime d) => [
          for (final t in kRoutine)
            RoutineLogEntry(astronautId: 'a1', taskId: t.id, day: dayKey(d), doneAt: d),
        ];

    test('task state follows the clock', () {
      expect(RoutineProgress.stateOf(kRoutine.first, DateTime(2030, 1, 10, 7), {}), TaskState.upcoming);
      expect(RoutineProgress.stateOf(kRoutine.first, DateTime(2030, 1, 10, 9), {}), TaskState.due);
      expect(RoutineProgress.stateOf(kRoutine.first, DateTime(2030, 1, 10, 11), {}), TaskState.overdue);
      expect(RoutineProgress.stateOf(kRoutine.first, now, {kRoutine.first.id}), TaskState.done);
    });
    test('streak counts consecutive complete days', () {
      final log = [...fullDay(DateTime(2030, 1, 9)), ...fullDay(DateTime(2030, 1, 8)), ...fullDay(DateTime(2030, 1, 6))];
      expect(RoutineProgress.streak(log, now), 2); // today incomplete, yesterday and the day before complete
    });
    test('streak includes today when complete', () {
      final log = [...fullDay(DateTime(2030, 1, 10)), ...fullDay(DateTime(2030, 1, 9))];
      expect(RoutineProgress.streak(log, now), 2);
    });
    test('streak is zero without data', () {
      expect(RoutineProgress.streak(const [], now), 0);
    });
    test('adherence is a share of possible completions', () {
      final log = fullDay(DateTime(2030, 1, 10)); // 5 of 35 over 7 days
      expect(RoutineProgress.adherence(log, now), closeTo(5 / 35, 1e-9));
    });
    test('points only count known tasks', () {
      expect(RoutineProgress.pointsFor({'bp_hr', 'nope'}), 10);
      expect(RoutineProgress.pointsFor({for (final t in kRoutine) t.id}), RoutineProgress.totalPoints);
    });
  });

  group('GuidanceEngine', () {
    const engine = GuidanceEngine();

    test('no data -> all clear with a prompt to measure', () {
      final g = engine.evaluate(const GuidanceInput(latest: {}));
      expect(g.level, GuidanceLevel.allClear);
      expect(g.headline, 'Waiting for readings');
    });
    test('normal vitals -> all clear', () {
      final g = engine.evaluate(const GuidanceInput(latest: {VitalType.heartRate: 70, VitalType.spo2: 98}));
      expect(g.level, GuidanceLevel.allClear);
      expect(g.signals, isEmpty);
    });
    test('one vital outside the usual range -> tell crew', () {
      final g = engine.evaluate(const GuidanceInput(latest: {VitalType.heartRate: 125}));
      expect(g.level, GuidanceLevel.tellCrew);
    });
    test('two vitals outside -> contact ground', () {
      final g = engine.evaluate(const GuidanceInput(latest: {VitalType.heartRate: 125, VitalType.temperature: 38.2}));
      expect(g.level, GuidanceLevel.contactGround);
    });
    test('critical vital -> urgent, and says to verify first', () {
      final g = engine.evaluate(const GuidanceInput(latest: {VitalType.spo2: 85}));
      expect(g.level, GuidanceLevel.urgent);
      expect(g.actions.first.text, contains('measure again'));
    });
    test('AI predicting critical raises to contact ground and mentions simulation', () {
      final g = engine.evaluate(const GuidanceInput(
        latest: {VitalType.heartRate: 70},
        aiPredicted: RiskClass.critical,
        aiHorizonMinutes: 120,
        aiSimulatedInput: true,
      ));
      expect(g.level, GuidanceLevel.contactGround);
      expect(g.signals.join(' '), contains('within 2 h'));
      expect(g.signals.join(' '), contains('simulated'));
    });
    test('AI early warning is only self-care', () {
      final g = engine.evaluate(const GuidanceInput(latest: {VitalType.heartRate: 70}, aiPredicted: RiskClass.earlyWarning));
      expect(g.level, GuidanceLevel.selfCare);
    });
    test('short sleep and low mood -> self-care', () {
      final g = engine.evaluate(GuidanceInput(latest: const {VitalType.heartRate: 70}, checkIn: ci(sleep: 4, mood: 2)));
      expect(g.level, GuidanceLevel.selfCare);
      expect(g.signals.length, 2);
    });
    test('low glucose -> tell crew', () {
      final g = engine.evaluate(GuidanceInput(latest: const {VitalType.heartRate: 70}, checkIn: ci(glucose: 60)));
      expect(g.level, GuidanceLevel.tellCrew);
    });
    test('three low-mood check-ins in a row -> contact ground', () {
      final g = engine.evaluate(GuidanceInput(
        latest: const {VitalType.heartRate: 70},
        recentCheckIns: [ci(mood: 1), ci(mood: 2), ci(mood: 2)],
      ));
      expect(g.level, GuidanceLevel.contactGround);
    });
    test('stale sensors add a signal but never lower the level', () {
      final g = engine.evaluate(const GuidanceInput(latest: {VitalType.spo2: 85}, sensorsStale: true));
      expect(g.level, GuidanceLevel.urgent);
      expect(g.signals.join(' '), contains('quiet'));
    });
    test('far from Earth the guidance warns about delay', () {
      final g = engine.evaluate(const GuidanceInput(
        latest: {VitalType.heartRate: 125, VitalType.temperature: 38.2},
        environment: MissionEnvironment.marsSurface,
      ));
      expect(g.actions.map((a) => a.why).join(' '), contains('minutes'));
    });
    test('always ends with the disclaimer', () {
      final g = engine.evaluate(const GuidanceInput(latest: {VitalType.heartRate: 70}));
      expect(g.actions.last.text, contains('Decision support only'));
    });
  });

  group('FlightSurgeonBrief', () {
    const astro = Astronaut(id: 'a1', name: 'Test Person', callsign: 'TP', role: UserRole.astronaut, isDemo: true);
    final now = DateTime(2030, 1, 10, 15);
    final guidance = const GuidanceEngine().evaluate(const GuidanceInput(latest: {VitalType.heartRate: 125}));

    String build({bool simulated = true, CheckIn? checkIn, MissionEnvironment env = MissionEnvironment.iss}) =>
        FlightSurgeonBrief.build(
          astronaut: astro,
          now: now,
          environment: env,
          vitals: [VitalLine(VitalType.heartRate, 125, now, min: 60, max: 130)],
          guidance: guidance,
          simulated: simulated,
          checkIn: checkIn,
        );

    test('labels simulated data loudly', () {
      expect(build(), contains('SIMULATED DEMO DATA'));
      expect(build(simulated: false), isNot(contains('SIMULATED DEMO DATA')));
    });
    test('contains vitals, assessment and the not-a-diagnosis line', () {
      final t = build();
      expect(t, contains('Heart rate: 125'));
      expect(t, contains('Assessment: '));
      expect(t, contains('not a diagnosis'));
    });
    test('includes self-reported data when present', () {
      expect(build(checkIn: ci(sleep: 5.5, glucose: 90)), contains('Sleep 5.5 h'));
    });
    test('states reply window only when the delay is large', () {
      expect(build(env: MissionEnvironment.marsTransit), contains('Earliest possible reply'));
      expect(build(), isNot(contains('Earliest possible reply')));
    });
  });
}
