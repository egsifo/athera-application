import '../domain/models.dart';

enum VStatus { none, ok, watch, critical }

/// Screening status of one reading against the app's configurable limits.
/// A "watch" or "critical" result is not a diagnosis.
VStatus vitalStatus(VitalType t, double? v) {
  if (v == null) return VStatus.none;
  if (v > t.critHigh || v < t.critLow) return VStatus.critical;
  if (v > t.alertHigh || v < t.alertLow) return VStatus.watch;
  return VStatus.ok;
}

VStatus worst(Iterable<VStatus> list) {
  var w = VStatus.none;
  for (final s in list) {
    if (s == VStatus.none) continue;
    if (w == VStatus.none || s.index > w.index) w = s;
  }
  return w;
}
