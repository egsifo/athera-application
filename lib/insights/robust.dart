import 'dart:math' as math;

/// Small robust-statistics helpers (no external packages, fully testable).

double median(List<double> v) {
  if (v.isEmpty) throw ArgumentError('median of empty list');
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// Median absolute deviation scaled to match a standard deviation for normal data.
double madScale(List<double> v) {
  final m = median(v);
  return 1.4826 * median([for (final x in v) (x - m).abs()]);
}

/// Least-squares slope of y against x (units of y per unit of x). Null if x has no spread.
double? slope(List<double> x, List<double> y) {
  if (x.length != y.length || x.length < 2) return null;
  final mx = x.reduce((a, b) => a + b) / x.length;
  final my = y.reduce((a, b) => a + b) / y.length;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < x.length; i++) {
    sxx += (x[i] - mx) * (x[i] - mx);
    sxy += (x[i] - mx) * (y[i] - my);
  }
  return sxx == 0 ? null : sxy / sxx;
}

/// Pearson correlation, null when either side has no variance or n < 3.
double? pearson(List<double> a, List<double> b) {
  if (a.length != b.length || a.length < 3) return null;
  final ma = a.reduce((x, y) => x + y) / a.length;
  final mb = b.reduce((x, y) => x + y) / b.length;
  var sab = 0.0, saa = 0.0, sbb = 0.0;
  for (var i = 0; i < a.length; i++) {
    sab += (a[i] - ma) * (b[i] - mb);
    saa += (a[i] - ma) * (a[i] - ma);
    sbb += (b[i] - mb) * (b[i] - mb);
  }
  if (saa == 0 || sbb == 0) return null;
  return sab / math.sqrt(saa * sbb);
}
