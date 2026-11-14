import '../insights/robust.dart';
import '../wellness/check_in.dart';

/// Four support levels. These describe how much human attention is suggested.
/// They are NOT diagnoses and are never derived from a single score alone.
enum SupportLevel { stable, attention, elevated, urgent }

enum WellbeingTrend { improving, stable, declining, insufficient }

class WellbeingIndicator {
  const WellbeingIndicator(this.name, this.score, this.note);
  final String name;

  /// 0..100, higher is better.
  final int score;
  final String note;
}

class WellbeingAssessment {
  const WellbeingAssessment({
    required this.hasData,
    required this.score,
    required this.level,
    required this.trend,
    required this.indicators,
    required this.reasons,
    required this.action,
    required this.basedOn,
    required this.simulated,
  });

  final bool hasData;

  /// 0..100 summary of recent self-reports (higher is better). Null with no check-ins.
  final int? score;
  final SupportLevel level;
  final WellbeingTrend trend;
  final List<WellbeingIndicator> indicators;

  /// The facts that set the level, in plain words.
  final List<String> reasons;
  final String action;
  final int basedOn;
  final bool simulated;

  String get levelLabel => switch (level) {
        SupportLevel.stable => 'Stable',
        SupportLevel.attention => 'Attention needed',
        SupportLevel.elevated => 'Elevated concern',
        SupportLevel.urgent => 'Urgent human support',
      };
}

class WellbeingAlert {
  const WellbeingAlert({required this.at, required this.level, required this.title, required this.reasons, required this.action, required this.indicators});
  final DateTime at;
  final SupportLevel level;
  final String title, action;
  final List<String> reasons, indicators;
}

class WellbeingEngine {
  const WellbeingEngine();

  static int _sleepScore(double h) => (((h - 3) / 4.5).clamp(0.0, 1.0) * 100).round();
  static int _high(int v) => ((v - 1) / 4 * 100).round(); // 1..5 higher better
  static int _low(int v) => ((5 - v) / 4 * 100).round(); // 1..5 lower better

  /// [checkIns] newest first. [urgentRequest] is set when the person (or Laila's safety protocol) asks for human support.
  WellbeingAssessment assess(List<CheckIn> checkIns, {bool urgentRequest = false}) {
    if (checkIns.isEmpty) {
      return WellbeingAssessment(
        hasData: false,
        score: null,
        level: urgentRequest ? SupportLevel.urgent : SupportLevel.stable,
        trend: WellbeingTrend.insufficient,
        indicators: const [],
        reasons: urgentRequest ? const ['Human support was requested'] : const ['No check-ins yet'],
        action: urgentRequest ? _urgentAction : 'Do your first daily check-in so ATHERA can follow how you are doing.',
        basedOn: 0,
        simulated: false,
      );
    }
    final recent = checkIns.take(3).toList();
    final n = recent.length;
    double avg(double Function(CheckIn) f) => recent.map(f).reduce((a, b) => a + b) / n;
    final mood = avg((c) => c.mood.toDouble()), stress = avg((c) => c.stress.toDouble());
    final fatigue = avg((c) => c.fatigue.toDouble()), sleep = avg((c) => c.sleepHours);

    final ind = [
      WellbeingIndicator('Mood', _high(mood.round()), _moodWord(mood)),
      WellbeingIndicator('Stress', _low(stress.round()), _lvlWord(stress)),
      WellbeingIndicator('Fatigue', _low(fatigue.round()), _lvlWord(fatigue)),
      WellbeingIndicator('Sleep', _sleepScore(sleep), '${sleep.toStringAsFixed(1)} h'),
    ];
    final score = (0.30 * _high(mood.round()) + 0.25 * _low(stress.round()) + 0.20 * _low(fatigue.round()) + 0.25 * _sleepScore(sleep)).round();

    final newest = checkIns.first;
    final reasons = <String>[];
    var level = SupportLevel.stable;
    void raise(SupportLevel l, String why) {
      if (l.index > level.index) level = l;
      reasons.add(why);
    }

    if (newest.mood <= 2) raise(SupportLevel.attention, 'Mood reported low today');
    if (newest.stress >= 4) raise(SupportLevel.attention, 'Stress reported high today');
    if (newest.sleepHours < 5.5) raise(SupportLevel.attention, 'Slept only ${newest.sleepHours.toStringAsFixed(1)} h');
    if (newest.fatigue >= 4) raise(SupportLevel.attention, 'Fatigue reported high today');
    if (score < 55 && level == SupportLevel.stable) raise(SupportLevel.attention, 'Overall self-report is below your comfortable range');

    // Persistence matters more than a single bad day.
    var lowRun = 0;
    for (final c in checkIns) {
      if (c.mood <= 2) {
        lowRun++;
      } else {
        break;
      }
    }
    if (lowRun >= 3) raise(SupportLevel.elevated, 'Low mood in $lowRun check-ins in a row');
    if (newest.mood <= 2 && newest.stress >= 4 && newest.sleepHours < 5) {
      raise(SupportLevel.elevated, 'Low mood, high stress and short sleep together');
    }
    if (urgentRequest) raise(SupportLevel.urgent, 'Human support was requested');

    // Trend across up to 7 check-ins, needing at least 4.
    var trend = WellbeingTrend.insufficient;
    final hist = checkIns.take(7).toList().reversed.toList();
    if (hist.length >= 4) {
      final t0 = hist.first.at;
      final xs = [for (final c in hist) c.at.difference(t0).inMinutes / 1440.0];
      final ys = [for (final c in hist) _scoreOf(c).toDouble()];
      final s = slope(xs, ys);
      if (s != null) trend = s >= 3 ? WellbeingTrend.improving : (s <= -3 ? WellbeingTrend.declining : WellbeingTrend.stable);
    }
    if (trend == WellbeingTrend.declining && level == SupportLevel.stable) raise(SupportLevel.attention, 'Well-being score has been falling');

    return WellbeingAssessment(
      hasData: true,
      score: score,
      level: level,
      trend: trend,
      indicators: ind,
      reasons: reasons,
      action: switch (level) {
        SupportLevel.stable => 'Keep your routine: sleep, exercise, contact with family and crew.',
        SupportLevel.attention => 'Take a short break, talk to Laila or a crewmate, and protect your sleep tonight.',
        SupportLevel.elevated => 'Talk to a crewmate and arrange a conversation with the flight surgeon or psychological support.',
        SupportLevel.urgent => _urgentAction,
      },
      basedOn: n,
      simulated: recent.any((c) => c.isDemo),
    );
  }

  static const _urgentAction = 'Contact the mission medical officer or mission control now. Do not stay alone with this.';

  static int _scoreOf(CheckIn c) =>
      (0.30 * _high(c.mood) + 0.25 * _low(c.stress) + 0.20 * _low(c.fatigue) + 0.25 * _sleepScore(c.sleepHours)).round();

  static String _moodWord(double v) => v < 1.5 ? 'Very low' : v < 2.5 ? 'Low' : v < 3.5 ? 'Okay' : v < 4.5 ? 'Good' : 'Very good';
  static String _lvlWord(double v) => v < 1.5 ? 'Very low' : v < 2.5 ? 'Low' : v < 3.5 ? 'Moderate' : v < 4.5 ? 'High' : 'Very high';

  /// One alert per check-in day on which support was suggested, derived only from stored check-ins.
  List<WellbeingAlert> alertHistory(List<CheckIn> checkIns) {
    final out = <WellbeingAlert>[];
    for (var i = 0; i < checkIns.length; i++) {
      final a = assess(checkIns.sublist(i));
      if (a.level == SupportLevel.stable) continue;
      out.add(WellbeingAlert(
        at: checkIns[i].at,
        level: a.level,
        title: a.levelLabel,
        reasons: a.reasons,
        action: a.action,
        indicators: [for (final x in a.indicators.where((x) => x.score < 50)) x.name],
      ));
    }
    return out;
  }

  /// Series of daily scores, oldest first, for charts.
  List<(DateTime, int)> scoreSeries(List<CheckIn> checkIns) =>
      [for (final c in checkIns.reversed) (c.at, _scoreOf(c))];
}
