import 'dart:math';

import 'package:athera/mind/laila.dart';
import 'package:athera/mind/mind_scenarios.dart';
import 'package:athera/mind/wellbeing.dart';
import 'package:athera/wellness/check_in.dart';
import 'package:flutter_test/flutter_test.dart';

CheckIn ci(int daysAgo, {double sleep = 7, int mood = 4, int fatigue = 2, int stress = 2, bool demo = false}) => CheckIn(
    id: 'c$daysAgo', astronautId: 'a', at: DateTime.utc(2030, 1, 20).subtract(Duration(days: daysAgo)),
    sleepHours: sleep, mood: mood, fatigue: fatigue, stress: stress, isDemo: demo);

void main() {
  const e = WellbeingEngine();

  group('WellbeingEngine', () {
    test('no check-ins: says so, makes no score', () {
      final a = e.assess(const []);
      expect(a.hasData, isFalse);
      expect(a.score, isNull);
      expect(a.level, SupportLevel.stable);
    });
    test('a good week is stable with a high score', () {
      final a = e.assess([for (var i = 0; i < 7; i++) ci(i)]);
      expect(a.level, SupportLevel.stable);
      expect(a.score, greaterThan(65));
    });
    test('one bad day raises attention, not more', () {
      final a = e.assess([ci(0, mood: 2, sleep: 5), ...[for (var i = 1; i < 7; i++) ci(i)]]);
      expect(a.level, SupportLevel.attention);
      expect(a.reasons, isNotEmpty);
    });
    test('persistent low mood raises elevated concern', () {
      final a = e.assess([ci(0, mood: 2), ci(1, mood: 1), ci(2, mood: 2), ci(3), ci(4)]);
      expect(a.level, SupportLevel.elevated);
    });
    test('low mood + high stress + short sleep together is elevated', () {
      expect(e.assess([ci(0, mood: 2, stress: 5, sleep: 4)]).level, SupportLevel.elevated);
    });
    test('urgent only when support is requested', () {
      expect(e.assess([ci(0)], urgentRequest: true).level, SupportLevel.urgent);
      expect(e.assess([ci(0, mood: 1, stress: 5, sleep: 2, fatigue: 5)]).level, isNot(SupportLevel.urgent));
    });
    test('falling scores give a declining trend, rising give improving', () {
      final down = e.assess([for (var i = 0; i < 6; i++) ci(i, mood: 1 + i ~/ 2 + 1, sleep: 4 + i * 0.6, stress: 5 - i ~/ 2)]);
      // newest first with i growing means older is better here: scores fall toward today
      expect(down.trend, WellbeingTrend.declining);
      final up = e.assess([for (var i = 0; i < 6; i++) ci(i, mood: 5 - i ~/ 2, sleep: 8 - i * 0.6, stress: 1 + i ~/ 2)]);
      expect(up.trend, WellbeingTrend.improving);
    });
    test('fewer than 4 check-ins: trend is insufficient', () {
      expect(e.assess([ci(0), ci(1)]).trend, WellbeingTrend.insufficient);
    });
    test('demo data is labelled', () {
      expect(e.assess([ci(0, demo: true)]).simulated, isTrue);
      expect(e.assess([ci(0)]).simulated, isFalse);
    });
    test('alert history only lists days where support was suggested', () {
      final list = [ci(0, mood: 2), ci(1), ci(2), ci(3, mood: 1, sleep: 4)];
      final h = e.alertHistory(list);
      expect(h.length, 2);
      expect(h.every((x) => x.level != SupportLevel.stable), isTrue);
    });
    test('score series is oldest first', () {
      final s = e.scoreSeries([ci(0), ci(1), ci(2)]);
      expect(s.first.$1.isBefore(s.last.$1), isTrue);
    });
  });

  group('Laila', () {
    LailaEngine mk() => LailaEngine(random: Random(1));

    test('the documented demo message gets the documented reply', () {
      final r = mk().respond("I'm tired of being here. I miss Earth. I feel lonely, and nothing makes me happy anymore.");
      expect(r.text, startsWith("I'm sorry you're feeling this way. Being so far away from everything familiar"));
      expect(r.text, contains('what you\'ve been missing the most?'));
      expect(r.urgent, isFalse);
    });
    test('Arabic is detected and answered in Arabic', () {
      final r = mk().respond('أنا حزين ومش عايز أكلم حد');
      expect(r.lang, LailaLang.ar);
      expect(RegExp(r'[؀-ۿ]').hasMatch(r.text), isTrue);
      expect(r.intent, LailaIntent.sad);
    });
    test('crisis in English stops motivational replies and escalates to humans', () {
      final l = mk();
      final r = l.respond('I want to kill myself');
      expect(r.urgent, isTrue);
      expect(r.intent, LailaIntent.crisis);
      expect(r.text.toLowerCase(), contains('mission medical officer'));
      final next = l.respond('thanks, I feel better');
      expect(next.urgent, isTrue, reason: 'protocol stays active');
      expect(next.intent, LailaIntent.crisis);
    });
    test('crisis in Arabic is detected, including spelling variants', () {
      expect(mk().respond('عايز أموت').urgent, isTrue);
      expect(mk().respond('أنا مش عايزة أعيش').urgent, isTrue);
      expect(mk().respond('بفكر أؤذي نفسي').urgent, isTrue);
    });
    test('ordinary tiredness is not a crisis', () {
      expect(mk().respond("I'm exhausted after the EVA").urgent, isFalse);
      expect(mk().respond('I am dying to see my family').urgent, isFalse);
    });
    test('each topic maps to the right intent', () {
      expect(mk().detect("I can't sleep at all"), LailaIntent.sleep);
      expect(mk().detect('I feel so anxious before launch'), LailaIntent.stress);
      expect(mk().detect('I feel much better today'), LailaIntent.recovering);
      expect(mk().detect('please help me breathe'), LailaIntent.breathing);
      expect(mk().detect('hello'), LailaIntent.greeting);
    });
    test('scenario context steers a vague message', () {
      final l = mk()..scenario = LailaScenario.sleep;
      final r = l.respond('hello');
      expect(r.intent, LailaIntent.sleep);
      expect(r.text, startsWith('I know sleep has been a struggle'));
    });
    test('breathing is offered for stress and sleep', () {
      expect(mk().respond('I feel very stressed').offerBreathing, isTrue);
    });
    test('welcome messages exist in both languages', () {
      expect(LailaEngine.welcome(LailaLang.en), startsWith("Hi, astronaut! I'm Laila."));
      expect(LailaEngine.welcome(LailaLang.ar), isNotEmpty);
    });
    test('reset clears the crisis state', () {
      final l = mk()..respond('I want to die');
      expect(l.crisisActive, isTrue);
      l.reset();
      expect(l.crisisActive, isFalse);
    });
  });

  group('Mind scenarios', () {
    final today = DateTime.utc(2030, 3, 1);
    List<CheckIn> build(MindScenario s) => buildMindScenario(s, astronautId: 'a', today: today);

    test('all scenarios are labelled simulation and cover 14 days ending today', () {
      for (final s in MindScenario.values) {
        final l = build(s);
        expect(l.length, kMindDays);
        expect(l.every((c) => c.isDemo && c.note == 'SIMULATION'), isTrue);
        expect(l.last.at.day, today.day);
        expect(l.first.at.isBefore(l.last.at), isTrue);
      }
    });
    test('healthy stays stable; lonely, depression-like and severe get worse; recovery improves', () {
      WellbeingAssessment end(MindScenario s) => e.assess(build(s).reversed.toList());
      expect(end(MindScenario.healthy).level, SupportLevel.stable);
      expect(end(MindScenario.lonely).level, isNot(SupportLevel.stable));
      expect(end(MindScenario.depressionLike).level, SupportLevel.elevated);
      expect(end(MindScenario.severeDistress).level, SupportLevel.elevated);
      expect(end(MindScenario.recovery).level, SupportLevel.stable);
      expect(end(MindScenario.recovery).trend, WellbeingTrend.improving);
      expect(end(MindScenario.depressionLike).trend, WellbeingTrend.declining);
    });
    test('values stay in valid ranges', () {
      for (final s in MindScenario.values) {
        for (final c in build(s)) {
          expect(CheckIn.validate(sleepHours: c.sleepHours, mood: c.mood, fatigue: c.fatigue, stress: c.stress), isNull);
        }
      }
    });
    test('scenarios drive Laila context', () {
      expect(MindScenario.lonely.laila, LailaScenario.lonely);
      expect(MindScenario.recovery.laila, LailaScenario.recovering);
    });
  });
}
