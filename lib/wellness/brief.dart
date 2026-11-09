import '../core/format.dart';
import '../domain/ai_models.dart';
import '../domain/models.dart';
import 'check_in.dart';
import 'guidance.dart';
import 'mission_env.dart';

class VitalLine {
  const VitalLine(this.type, this.latest, this.at, {this.min, this.max, this.mean});
  final VitalType type;
  final double latest;
  final DateTime at;

  /// Last 24 h summary (usable readings only).
  final double? min, max, mean;
}

/// Builds a concise plain-text health brief for the flight surgeon. Pure
/// function: it states facts and caveats and never adds a diagnosis.
class FlightSurgeonBrief {
  const FlightSurgeonBrief._();

  static String build({
    required Astronaut astronaut,
    required DateTime now,
    required MissionEnvironment environment,
    required List<VitalLine> vitals,
    required Guidance guidance,
    required bool simulated,
    CheckIn? checkIn,
    RiskResult? risk,
    List<String> openAlerts = const [],
    bool fahrenheit = false,
  }) {
    final b = StringBuffer();
    String temp(double c) => fahrenheit ? '${cToF(c).toStringAsFixed(1)} °F' : '${c.toStringAsFixed(1)} °C';
    String val(VitalType t, double v) => t == VitalType.temperature ? temp(v) : '${v.toStringAsFixed(t.decimals)} ${t.unit}';

    b.writeln('ATHERA HEALTH BRIEF');
    if (simulated) b.writeln('*** SIMULATED DEMO DATA. NOT A REAL PERSON. ***');
    b.writeln('Crew member: ${astronaut.name} (${astronaut.callsign})');
    b.writeln('Prepared: ${fmtDateTime(now)} local · ${environment.label}');
    b.writeln('Assessment: ${guidance.level.label}. ${guidance.headline}.');
    if (guidance.signals.isNotEmpty) {
      b.writeln();
      b.writeln('WHY');
      for (final s in guidance.signals) {
        b.writeln('- $s');
      }
    }

    b.writeln();
    b.writeln('LATEST MEASUREMENTS (last 24 h range)');
    if (vitals.isEmpty) {
      b.writeln('- No usable measurements.');
    }
    for (final v in vitals) {
      final range = v.min == null || v.max == null ? '' : ' · 24 h ${val(v.type, v.min!)} to ${val(v.type, v.max!)}';
      b.writeln('- ${v.type.label}: ${val(v.type, v.latest)} at ${fmtTime(v.at, seconds: false)}$range');
    }

    if (checkIn != null) {
      b.writeln();
      b.writeln('SELF-REPORTED (${fmtDateTime(checkIn.at)})');
      b.writeln('- Sleep ${checkIn.sleepHours.toStringAsFixed(1)} h · mood ${checkIn.mood}/5 · fatigue ${checkIn.fatigue}/5 · stress ${checkIn.stress}/5');
      if (checkIn.glucoseMgDl != null) b.writeln('- Blood glucose ${checkIn.glucoseMgDl!.toStringAsFixed(0)} mg/dL');
      if (checkIn.note.trim().isNotEmpty) b.writeln('- Note: ${checkIn.note.trim()}');
    }

    if (risk != null) {
      b.writeln();
      b.writeln('AI MODEL OUTPUT (a prediction, not a measurement)');
      b.writeln('- ${risk.modelName} ${risk.modelVersion}: predicted ${risk.riskClass.label}'
          '${risk.horizonMinutes != null ? ' within ${risk.horizonMinutes} min' : ''}'
          '${risk.currentClass != null ? ' · current ${risk.currentClass!.label}' : ''}');
      if (risk.riskScore != null) b.writeln('- Risk index ${risk.riskScore!.toStringAsFixed(0)}/100 (model-defined)');
      for (final f in risk.contributingFeatures.take(5)) {
        b.writeln('- Reason: ${f.feature}');
      }
      if (risk.inputSimulated) b.writeln('- Model input was simulated.');
    }

    if (openAlerts.isNotEmpty) {
      b.writeln();
      b.writeln('OPEN ALERTS');
      for (final a in openAlerts.take(6)) {
        b.writeln('- $a');
      }
    }

    final (lo, hi) = environment.replyWindow(now);
    b.writeln();
    b.writeln('COMMUNICATION');
    b.writeln('- One-way delay to Earth: ${environment.delayText}.');
    if (environment.autonomous) {
      b.writeln('- Earliest possible reply ${fmtTime(lo, seconds: false)}, up to ${fmtTime(hi, seconds: false)} (travel time only).');
    }
    b.writeln();
    b.writeln('Screening rules and a model produced this brief. It is not a diagnosis.');
    return b.toString();
  }
}
