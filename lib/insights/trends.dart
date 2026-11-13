import 'robust.dart';

enum TrendDirection { improving, stable, declining, insufficient }

class TrendResult {
  const TrendResult({required this.label, required this.direction, required this.slopePerDay, required this.n, required this.summary});
  final String label;
  final TrendDirection direction;
  final double? slopePerDay;
  final int n;
  final String summary;
}

/// One observation per time; oldest first.
class TrendPoint {
  const TrendPoint(this.at, this.value);
  final DateTime at;
  final double value;
}

class TrendEngine {
  const TrendEngine({this.minPoints = 4});
  final int minPoints;

  static const insufficientText = 'Insufficient historical data to establish a reliable trend.';

  /// [higherIsBetter] decides whether a rising slope counts as improving.
  /// [meaningfulPerDay] is the smallest change per day worth calling a trend.
  TrendResult analyse(String label, List<TrendPoint> pts, {required bool higherIsBetter, required double meaningfulPerDay, required String unit}) {
    final clean = [for (final p in pts) if (p.value.isFinite) p];
    if (clean.length < minPoints) {
      return TrendResult(label: label, direction: TrendDirection.insufficient, slopePerDay: null, n: clean.length, summary: insufficientText);
    }
    final t0 = clean.first.at;
    final x = [for (final p in clean) p.at.difference(t0).inMinutes / 1440.0];
    final s = slope(x, [for (final p in clean) p.value]);
    if (s == null) {
      return TrendResult(label: label, direction: TrendDirection.insufficient, slopePerDay: null, n: clean.length, summary: insufficientText);
    }
    final dir = s.abs() < meaningfulPerDay
        ? TrendDirection.stable
        : ((s > 0) == higherIsBetter ? TrendDirection.improving : TrendDirection.declining);
    final word = switch (dir) {
      TrendDirection.improving => 'improving',
      TrendDirection.declining => 'declining',
      _ => 'stable',
    };
    return TrendResult(
      label: label,
      direction: dir,
      slopePerDay: s,
      n: clean.length,
      summary: '$label is $word: ${s >= 0 ? '+' : ''}${s.toStringAsFixed(2)} $unit per day over ${clean.length} observations.',
    );
  }
}
