import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Real NASA data bundled with the app (see tools/build_real_data_assets.py).
/// Parsing is strict: a malformed file is an error, never silently repaired.

Never _bad(String m) => throw FormatException(m);

Map<String, Object?> _obj(Object? v, String p) => v is Map<String, Object?> ? v : _bad('$p: expected object');
List<Object?> _list(Object? v, String p) => v is List<Object?> ? v : _bad('$p: expected list');
String _s(Object? v, String p) => v is String ? v : _bad('$p: expected string');
double _d(Object? v, String p) => v is num && v.isFinite ? v.toDouble() : _bad('$p: expected number');
double? _dn(Object? v, String p) => v == null ? null : _d(v, p);

class RadDay {
  const RadDay(this.date, this.mean, this.median, this.max, this.samples, this.complete);
  final DateTime date;

  /// Absorbed dose rate in uGy/h.
  final double mean, median, max;
  final int samples;

  /// Enough samples that the day's average is representative.
  final bool complete;

  /// Absorbed dose for the day in uGy (mean rate x 24 h). Only meaningful when [complete].
  double get doseUGy => mean * 24;
}

class IssRadiation {
  IssRadiation({required this.title, required this.source, required this.unit, required this.notes, required this.instruments});

  final String title, source, unit;
  final List<String> notes;
  final Map<String, List<RadDay>> instruments;

  factory IssRadiation.parse(Object? raw) {
    final m = _obj(raw, 'radiation');
    if (_s(m['kind'], 'kind') != 'measured') _bad('kind must be "measured"');
    final ins = _obj(m['instruments'], 'instruments');
    if (ins.isEmpty) _bad('instruments: empty');
    final out = <String, List<RadDay>>{};
    ins.forEach((name, v) {
      final days = _list(_obj(v, name)['days'], '$name.days');
      DateTime? prev;
      out[name] = [
        for (var i = 0; i < days.length; i++)
          () {
            final r = _list(days[i], '$name.days[$i]');
            if (r.length != 6) _bad('$name.days[$i]: expected 6 columns');
            final t = DateTime.tryParse(_s(r[0], 'date'));
            if (t == null) _bad('$name.days[$i]: bad date');
            if (prev != null && !t.isAfter(prev!)) _bad('$name.days[$i]: dates must increase');
            prev = t;
            final mean = _d(r[1], 'mean'), median = _d(r[2], 'median'), max = _d(r[3], 'max');
            if (mean < 0 || median < 0 || max < mean) _bad('$name.days[$i]: impossible dose values');
            return RadDay(t, mean, median, max, _d(r[4], 'n').toInt(), _d(r[5], 'complete') == 1);
          }(),
      ];
    });
    return IssRadiation(
      title: _s(m['title'], 'title'),
      source: _s(m['source'], 'source'),
      unit: _s(m['unit'], 'unit'),
      notes: [for (final n in _list(m['notes'], 'notes')) _s(n, 'note')],
      instruments: out,
    );
  }

  static Future<IssRadiation> load() async =>
      IssRadiation.parse(jsonDecode(await rootBundle.loadString('assets/data/iss_radiation.json')));
}

/// Summary statistics computed from the real days, never typed in.
class RadStats {
  RadStats(List<RadDay> days) {
    final complete = days.where((d) => d.complete).toList();
    completeDays = complete.length;
    totalDays = days.length;
    if (complete.isEmpty) return;
    meanDailyDoseUGy = complete.map((d) => d.doseUGy).reduce((a, b) => a + b) / complete.length;
    totalMeasuredDoseUGy = complete.map((d) => d.doseUGy).reduce((a, b) => a + b);
    final sorted = complete.map((d) => d.median).toList()..sort();
    quietMedianRate = sorted[sorted.length ~/ 2];
    peakDay = complete.reduce((a, b) => a.mean >= b.mean ? a : b);
    peakInstant = days.reduce((a, b) => a.max >= b.max ? a : b);
  }
  int completeDays = 0, totalDays = 0;
  double? meanDailyDoseUGy, totalMeasuredDoseUGy, quietMedianRate;
  RadDay? peakDay, peakInstant;

  /// Gaps longer than [minDays] between consecutive measured days.
  static List<(DateTime, DateTime)> gaps(List<RadDay> days, {int minDays = 7}) {
    final g = <(DateTime, DateTime)>[];
    for (var i = 1; i < days.length; i++) {
      if (days[i].date.difference(days[i - 1].date).inDays > minDays) g.add((days[i - 1].date, days[i].date));
    }
    return g;
  }
}

class BloodMarker {
  BloodMarker({
    required this.id,
    required this.label,
    required this.panel,
    required this.unit,
    required this.refMin,
    required this.refMax,
    required this.values,
  });
  final String id, label, panel, unit;
  final double? refMin, refMax;

  /// crew id -> value per timepoint (null = not measured).
  final Map<String, List<double?>> values;

  bool outOfRange(double v) => (refMin != null && v < refMin!) || (refMax != null && v > refMax!);

  int get outOfRangeCount => values.values.expand((l) => l).whereType<double>().where(outOfRange).length;

  /// Mean across crew of (R+1 - L-3) / L-3, in percent. Null when not computable.
  double? changeAtLandingPct(List<String> timepoints) {
    final a = timepoints.indexOf('L-3'), b = timepoints.indexOf('R+1');
    if (a < 0 || b < 0) return null;
    final ch = <double>[];
    for (final v in values.values) {
      final x = v[a], y = v[b];
      if (x != null && y != null && x != 0) ch.add((y - x) / x * 100);
    }
    return ch.isEmpty ? null : ch.reduce((p, q) => p + q) / ch.length;
  }
}

class BloodPanel {
  BloodPanel({required this.title, required this.source, required this.timepoints, required this.timepointNote, required this.markers, required this.notes});
  final String title, source, timepointNote;
  final List<String> timepoints, notes;
  final List<BloodMarker> markers;

  factory BloodPanel.parse(Object? raw) {
    final m = _obj(raw, 'blood');
    if (_s(m['kind'], 'kind') != 'measured') _bad('kind must be "measured"');
    final tps = [for (final t in _list(m['timepoints'], 'timepoints')) _s(t, 'timepoint')];
    if (tps.isEmpty) _bad('timepoints: empty');
    final markers = <BloodMarker>[];
    for (final raw in _list(m['markers'], 'markers')) {
      final o = _obj(raw, 'marker');
      final vals = _obj(o['values'], 'values');
      markers.add(BloodMarker(
        id: _s(o['id'], 'id'),
        label: _s(o['label'], 'label'),
        panel: _s(o['panel'], 'panel'),
        unit: _s(o['unit'], 'unit'),
        refMin: _dn(o['ref_min'], 'ref_min'),
        refMax: _dn(o['ref_max'], 'ref_max'),
        values: vals.map((k, v) {
          final l = _list(v, k);
          if (l.length != tps.length) _bad('${o['id']}.$k: expected ${tps.length} values');
          return MapEntry(k, [for (final x in l) _dn(x, '${o['id']}.$k')]);
        }),
      ));
    }
    if (markers.isEmpty) _bad('markers: empty');
    return BloodPanel(
      title: _s(m['title'], 'title'),
      source: _s(m['source'], 'source'),
      timepoints: tps,
      timepointNote: _s(m['timepoint_note'], 'timepoint_note'),
      markers: markers,
      notes: [for (final n in _list(m['notes'], 'notes')) _s(n, 'note')],
    );
  }

  static Future<BloodPanel> load() async =>
      BloodPanel.parse(jsonDecode(await rootBundle.loadString('assets/data/i4_blood.json')));
}
