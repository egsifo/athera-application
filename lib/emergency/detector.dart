import 'knowledge_base.dart';

/// A possible emergency category. Always a possibility, never a diagnosis.
class Candidate {
  const Candidate(this.kind, this.reason, this.severity);
  final EmergencyKind kind;
  final String reason;

  /// 1 attention, 2 serious, 3 critical.
  final int severity;
}

class Detection {
  const Detection({required this.candidates, required this.uncertainty});
  final List<Candidate> candidates;

  /// Set when the data is not reliable enough to lean on. Shown next to the guide.
  final String? uncertainty;
  Candidate? get top => candidates.isEmpty ? null : candidates.first;
}

/// Maps measurements and reported symptoms to possible emergency categories.
/// It never names a diagnosis, and a heart-rate reading alone is only ever
/// "abnormal reading", never a confirmed arrhythmia.
Detection detectEmergency({
  double? hr,
  double? spo2,
  double? rr,
  double? temp,
  double? activity,
  double? doseRate,
  double quietDoseRate = 6,
  bool dataReliable = true,
  Set<EmergencyKind> reported = const {},
  bool unresponsive = false,
}) {
  final c = <Candidate>[];
  if (unresponsive || (activity != null && activity < 0.05 && hr != null && (hr < 55 || hr > 130))) {
    c.add(const Candidate(EmergencyKind.syncope, 'No movement with an abnormal heart rate. Suspected loss of consciousness, not confirmed.', 3));
  } else if (reported.contains(EmergencyKind.syncope)) {
    c.add(const Candidate(EmergencyKind.syncope, 'Dizziness or faintness reported.', 2));
  }
  if (spo2 != null && spo2 < 94) {
    final sev = spo2 < 85 ? 3 : (spo2 < 90 ? 2 : 1);
    c.add(Candidate(EmergencyKind.hypoxia, 'SpO₂ ${spo2.toStringAsFixed(1)}%. The cause is not known from SpO₂ alone.', sev));
  }
  if (rr != null && (rr > 25 || rr < 10) || reported.contains(EmergencyKind.respiratory)) {
    c.add(Candidate(EmergencyKind.respiratory, rr == null ? 'Breathing trouble reported.' : 'Breathing rate ${rr.round()}/min is outside the usual range.', rr != null && rr > 30 ? 3 : 2));
  }
  if (reported.contains(EmergencyKind.chestPain)) {
    c.add(const Candidate(EmergencyKind.chestPain, 'Chest pain or pressure reported.', 3));
  }
  if (hr != null && (hr > 120 || hr < 50)) {
    c.add(Candidate(EmergencyKind.arrhythmia, 'Heart-rate reading ${hr.round()} bpm is abnormal. This is a reading, not a confirmed arrhythmia.', 2));
  }
  if (reported.contains(EmergencyKind.stroke)) {
    c.add(const Candidate(EmergencyKind.stroke, 'Stroke warning signs reported.', 3));
  }
  if (reported.contains(EmergencyKind.allergy)) {
    c.add(const Candidate(EmergencyKind.allergy, 'Allergic symptoms reported.', 3));
  }
  if (temp != null && temp > 38.5) {
    c.add(Candidate(EmergencyKind.heat, 'Temperature ${temp.toStringAsFixed(1)} °C.', reported.contains(EmergencyKind.heat) ? 3 : 2));
  }
  if (doseRate != null && doseRate > 50 * quietDoseRate) {
    c.add(Candidate(EmergencyKind.radiation, 'Dose rate ${doseRate.toStringAsFixed(0)} µGy/h, far above the quiet level.', 3));
  }
  if (reported.contains(EmergencyKind.psychological)) {
    c.add(const Candidate(EmergencyKind.psychological, 'Severe distress reported.', 3));
  }
  if (reported.contains(EmergencyKind.dehydration)) {
    c.add(const Candidate(EmergencyKind.dehydration, 'Dehydration symptoms reported.', 1));
  }
  c.sort((a, b) => b.severity.compareTo(a.severity));
  return Detection(
    candidates: c,
    uncertainty: dataReliable ? null : 'Sensor data may be unreliable. Check the sensor fit and do not delay action if the person looks unwell.',
  );
}
