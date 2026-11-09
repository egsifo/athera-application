import '../domain/ai_models.dart';
import '../domain/models.dart';
import 'check_in.dart';
import 'mission_env.dart';

/// How far up the chain of help the situation points. This is decision
/// support from simple screening rules. It is not a diagnosis.
enum GuidanceLevel { allClear, selfCare, tellCrew, contactGround, urgent }

extension GuidanceLevelX on GuidanceLevel {
  String get label => switch (this) {
        GuidanceLevel.allClear => 'All clear',
        GuidanceLevel.selfCare => 'Self-care',
        GuidanceLevel.tellCrew => 'Tell the crew medical officer',
        GuidanceLevel.contactGround => 'Contact the flight surgeon',
        GuidanceLevel.urgent => 'Verify now, then act',
      };

  int get rank => index;
}

class GuidanceAction {
  const GuidanceAction(this.text, this.why);
  final String text;
  final String why;
}

class Guidance {
  const Guidance({
    required this.level,
    required this.headline,
    required this.actions,
    required this.signals,
  });
  final GuidanceLevel level;
  final String headline;
  final List<GuidanceAction> actions;

  /// The facts that triggered this guidance, in plain words.
  final List<String> signals;
}

class GuidanceInput {
  const GuidanceInput({
    required this.latest,
    this.aiPredicted,
    this.aiNow,
    this.aiHorizonMinutes,
    this.aiSimulatedInput = false,
    this.aiScore,
    this.checkIn,
    this.recentCheckIns = const [],
    this.environment = MissionEnvironment.iss,
    this.sensorsStale = false,
  });

  /// Latest usable reading per vital (missing = no data).
  final Map<VitalType, double> latest;
  final RiskClass? aiPredicted;
  final RiskClass? aiNow;
  final int? aiHorizonMinutes;
  final bool aiSimulatedInput;
  final double? aiScore;

  /// Today's check-in, if done.
  final CheckIn? checkIn;

  /// Newest first.
  final List<CheckIn> recentCheckIns;
  final MissionEnvironment environment;
  final bool sensorsStale;
}

class GuidanceEngine {
  const GuidanceEngine();

  static const _disclaimer = 'Decision support only. Follow your mission medical procedures.';

  Guidance evaluate(GuidanceInput i) {
    final signals = <String>[];
    final actions = <GuidanceAction>[];
    var level = GuidanceLevel.allClear;

    void raise(GuidanceLevel l) {
      if (l.rank > level.rank) level = l;
    }

    // ---- 1. vital readings against the app's screening limits -------------
    var outOfRange = 0;
    var critical = 0;
    for (final e in i.latest.entries) {
      final t = e.key;
      final v = e.value;
      final d = t.decimals;
      String fmt() => '${v.toStringAsFixed(d)} ${t.unit}';
      if (v > t.critHigh || v < t.critLow) {
        critical++;
        outOfRange++;
        signals.add('${t.label} ${fmt()} is far outside the safe range');
      } else if (v > t.alertHigh || v < t.alertLow) {
        outOfRange++;
        signals.add('${t.label} ${fmt()} is outside the usual range');
      }
    }
    if (critical > 0) {
      raise(GuidanceLevel.urgent);
      actions.add(const GuidanceAction(
        'Check that the sensor fits well, then measure again right now.',
        'A single bad reading is often a loose sensor. A repeated one is real.',
      ));
      actions.add(const GuidanceAction(
        'If it repeats, or you feel unwell, tell your crew immediately and use SOS.',
        'Critical values need people nearby to help, not just a note in an app.',
      ));
    } else if (outOfRange >= 2) {
      raise(GuidanceLevel.contactGround);
    } else if (outOfRange == 1) {
      raise(GuidanceLevel.tellCrew);
    }
    if (outOfRange > 0 && critical == 0) {
      actions.add(const GuidanceAction(
        'Stop strenuous work, sit down and rest for 10 to 15 minutes, then measure again.',
        'Exertion, heat and stress can push readings out of range for a short time.',
      ));
    }

    // ---- 2. what the AI model expects --------------------------------------
    final h = i.aiHorizonMinutes;
    final horizon = h == null ? 'soon' : (h >= 60 && h % 60 == 0 ? 'within ${h ~/ 60} h' : 'within $h min');
    final sim = i.aiSimulatedInput ? ' (model fed simulated demo data)' : '';
    if (i.aiPredicted == RiskClass.critical) {
      raise(GuidanceLevel.contactGround);
      signals.add('The AI model expects a critical state $horizon$sim');
      actions.add(const GuidanceAction(
        'Reduce exertion now and move to a safe place. Plan to return to base or the habitat.',
        'The model sees vitals drifting toward the critical limits.',
      ));
    } else if (i.aiPredicted == RiskClass.earlyWarning) {
      raise(GuidanceLevel.selfCare);
      signals.add('The AI model sees vitals drifting $horizon$sim');
      actions.add(const GuidanceAction(
        'Rest, drink water, and measure again in 15 minutes.',
        'An early, small correction is easier than a late one.',
      ));
    }
    if (i.aiNow == RiskClass.critical && critical == 0) {
      raise(GuidanceLevel.contactGround);
      signals.add('The AI model rates the current readings as critical');
    }

    // ---- 3. self-reported wellbeing -------------------------------------------
    final c = i.checkIn;
    if (c != null) {
      if (c.sleepHours < 5) {
        raise(GuidanceLevel.selfCare);
        signals.add('Only ${c.sleepHours.toStringAsFixed(1)} h of sleep');
        actions.add(const GuidanceAction(
          'Plan recovery sleep, and avoid high-risk tasks such as EVA while sleep-deprived.',
          'Short sleep slows reactions and raises stress, and it is a known spaceflight risk.',
        ));
      }
      if (c.mood <= 2 || c.stress >= 4) {
        raise(GuidanceLevel.selfCare);
        signals.add(c.mood <= 2 ? 'Low mood reported' : 'High stress reported');
        actions.add(const GuidanceAction(
          'Talk to a crewmate, or request a private call with behavioral health support.',
          'Isolation and confinement affect mood and stress, and talking early helps.',
        ));
      }
      final g = c.glucoseMgDl;
      if (g != null && g < 70) {
        raise(GuidanceLevel.tellCrew);
        signals.add('Blood glucose ${g.toStringAsFixed(0)} mg/dL is low');
        actions.add(const GuidanceAction(
          'Take fast-acting carbohydrate as your mission medical procedures describe, then recheck in 15 minutes.',
          'Low blood sugar can cause confusion and weakness quickly.',
        ));
      } else if (g != null && g > 180) {
        raise(GuidanceLevel.tellCrew);
        signals.add('Blood glucose ${g.toStringAsFixed(0)} mg/dL is high');
        actions.add(const GuidanceAction(
          'Tell the crew medical officer and note recent meals and exercise.',
          'Context helps the medical team interpret one high value.',
        ));
      }
    }
    final lowMoodRun = i.recentCheckIns.length >= 3 && i.recentCheckIns.take(3).every((x) => x.mood <= 2);
    if (lowMoodRun) {
      raise(GuidanceLevel.contactGround);
      signals.add('Low mood on 3 check-ins in a row');
      actions.add(const GuidanceAction(
        'Contact the flight surgeon or behavioral health team about how you have been feeling.',
        'A pattern over several days matters more than one bad day.',
      ));
    }

    if (i.sensorsStale) {
      signals.add('Sensors have gone quiet, so this guidance may be out of date');
      actions.add(const GuidanceAction(
        'Check that the wearable is on, charged and connected.',
        'Without data the app cannot watch your vitals.',
      ));
    }

    // ---- 4. escalation and distance --------------------------------------------
    if (level.rank >= GuidanceLevel.tellCrew.rank) {
      actions.add(GuidanceAction(
        level.rank >= GuidanceLevel.contactGround.rank
            ? 'Prepare a flight-surgeon brief. The app can build it for you.'
            : 'Let the crew medical officer know how you feel.',
        i.environment.autonomous
            ? 'Ground replies take minutes. ${i.environment.autonomyNote}'
            : 'Early contact gives the doctors more time.',
      ));
    }

    final String headline;
    if (level == GuidanceLevel.allClear) {
      if (i.latest.isEmpty) {
        headline = 'Waiting for readings';
        actions.add(const GuidanceAction(
          'Take your routine measurements so ATHERA can assess your health.',
          'There is nothing to judge until data arrives.',
        ));
      } else {
        headline = 'Everything looks in range';
        actions.add(const GuidanceAction(
          'Keep up your routine: exercise, sleep, hydration and your daily check-in.',
          'Steady habits are the best protection on a long mission.',
        ));
      }
    } else {
      headline = switch (level) {
        GuidanceLevel.selfCare => 'Take it easy and recheck',
        GuidanceLevel.tellCrew => 'Tell someone how you feel',
        GuidanceLevel.contactGround => 'Involve the flight surgeon',
        GuidanceLevel.urgent => 'Verify the reading now',
        GuidanceLevel.allClear => '',
      };
    }
    actions.add(const GuidanceAction(_disclaimer, 'ATHERA is a research prototype and not a medical device.'));
    return Guidance(level: level, headline: headline, actions: actions, signals: signals);
  }
}
