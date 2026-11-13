import 'robust.dart' as rb;

/// A personal baseline learned from an astronaut's own earlier observations.
class PersonalBaseline {
  const PersonalBaseline({required this.median, required this.scale, required this.n, required this.confidence});

  final double median;

  /// Robust spread (MAD-based), never below the indicator's floor.
  final double scale;
  final int n;

  /// 0..1. Grows with the number of observations; 0 means "do not use".
  final double confidence;

  /// Builds a baseline, or returns null when there is not enough data.
  /// [floor] stops a perfectly steady history from producing absurd z-scores.
  static PersonalBaseline? compute(List<double> values, {required int minObservations, required double floor, int fullConfidenceAt = 21}) {
    final v = [for (final x in values) if (x.isFinite) x];
    if (v.length < minObservations) return null;
    final s = rb.madScale(v);
    return PersonalBaseline(
      median: rb.median(v),
      scale: s < floor ? floor : s,
      n: v.length,
      confidence: (v.length / fullConfidenceAt).clamp(0.0, 1.0),
    );
  }

  /// Signed robust z-score of [x] against this baseline.
  double z(double x) => (x - median) / scale;
}
