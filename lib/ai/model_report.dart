import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Out-of-sample evaluation of the ATHERA risk model, computed by
/// `ai_service/make_backtest.py` from the model's real output on held-out
/// SIMULATED data. Nothing here is typed in by hand.
class ModelReport {
  ModelReport({
    required this.source,
    required this.dataKind,
    required this.horizonMinutes,
    required this.holdoutRows,
    required this.periodStart,
    required this.periodEnd,
    required this.accuracy,
    required this.baselineAccuracy,
    required this.classes,
    required this.confusion,
    required this.perClass,
    required this.episodeCount,
    required this.episodesWarned,
    required this.episodesWarnedCritical,
    required this.medianLeadMinutes,
    required this.criticalAlarms,
    required this.criticalAlarmsConfirmed,
    required this.episodes,
    required this.series,
  });

  final String source;

  /// "simulated" or "real": what the model was trained and tested on.
  final String dataKind;
  bool get isSimulated => dataKind != 'real';
  final int horizonMinutes;
  final int holdoutRows;
  final String periodStart, periodEnd;
  final double accuracy;
  final double baselineAccuracy;
  final List<String> classes;

  /// confusion[actual][predicted].
  final List<List<int>> confusion;
  final Map<String, ClassMetrics> perClass;
  final int episodeCount;
  final int episodesWarned;
  final int episodesWarnedCritical;
  final double? medianLeadMinutes;
  final int criticalAlarms;
  final int criticalAlarmsConfirmed;
  final List<Episode> episodes;
  final ReportSeries series;

  double get gainOverBaseline => accuracy - baselineAccuracy;

  double? get criticalPrecision => criticalAlarms == 0 ? null : criticalAlarmsConfirmed / criticalAlarms;

  /// Strict parse: any missing or malformed field is an error, never a default.
  factory ModelReport.parse(Object? raw) {
    final m = _obj(raw, 'report');
    final ce = _obj(m['critical_episodes'], 'critical_episodes');
    final conf = (m['confusion'] as List?)?.map((r) => (r as List).map((x) => (x as num).toInt()).toList()).toList();
    if (conf == null || conf.length != 3 || conf.any((r) => r.length != 3)) {
      throw const FormatException('confusion must be a 3x3 matrix');
    }
    final period = (m['holdout_period'] as List?)?.cast<String>();
    if (period == null || period.length != 2) throw const FormatException('holdout_period must have 2 items');
    final pc = _obj(m['per_class'], 'per_class');
    final series = ReportSeries.parse(m['series']);
    return ModelReport(
      source: _str(m, 'generated_from'),
      dataKind: _dataKind(m),
      horizonMinutes: _int(m, 'horizon_minutes'),
      holdoutRows: _int(m, 'holdout_rows'),
      periodStart: period[0],
      periodEnd: period[1],
      accuracy: _num(m, 'accuracy'),
      baselineAccuracy: _num(m, 'baseline_accuracy'),
      classes: (m['classes'] as List).cast<String>(),
      confusion: conf,
      perClass: {for (final e in pc.entries) e.key: ClassMetrics.parse(e.value)},
      episodeCount: _int(ce, 'count'),
      episodesWarned: _int(ce, 'warned_any'),
      episodesWarnedCritical: _int(ce, 'warned_critical'),
      medianLeadMinutes: (ce['median_lead_any_min'] as num?)?.toDouble(),
      criticalAlarms: _int(ce, 'critical_alarms'),
      criticalAlarmsConfirmed: _int(ce, 'critical_alarms_confirmed'),
      episodes: [for (final e in (ce['list'] as List)) Episode.parse(e)],
      series: series,
    );
  }

  static Future<ModelReport> load({String asset = 'assets/ai/backtest.json'}) async =>
      ModelReport.parse(jsonDecode(await rootBundle.loadString(asset)));
}

class ClassMetrics {
  const ClassMetrics({required this.support, this.recall, this.precision});
  final int support;
  final double? recall, precision;
  factory ClassMetrics.parse(Object? raw) {
    final m = _obj(raw, 'class metrics');
    return ClassMetrics(
      support: _int(m, 'support'),
      recall: (m['recall'] as num?)?.toDouble(),
      precision: (m['precision'] as num?)?.toDouble(),
    );
  }
}

class Episode {
  const Episode({required this.onset, this.leadAnyMin, this.leadCriticalMin});
  final String onset;

  /// Minutes before the critical state that the model first said "early warning or worse".
  final int? leadAnyMin;
  final int? leadCriticalMin;
  factory Episode.parse(Object? raw) {
    final m = _obj(raw, 'episode');
    return Episode(
      onset: _str(m, 'onset'),
      leadAnyMin: (m['lead_any_min'] as num?)?.toInt(),
      leadCriticalMin: (m['lead_critical_min'] as num?)?.toInt(),
    );
  }
}

/// Time series over the held-out period, one entry per 15 minutes.
class ReportSeries {
  ReportSeries({
    required this.t,
    required this.now,
    required this.pred,
    required this.actual,
    required this.risk,
    required this.hr,
    required this.spo2,
    required this.temp,
    required this.sbp,
  });
  final List<String> t;
  final List<int> now, pred, actual;
  final List<double> risk, hr, spo2, temp, sbp;

  int get length => t.length;

  factory ReportSeries.parse(Object? raw) {
    final m = _obj(raw, 'series');
    List<int> ints(String k) => (m[k] as List).map((x) => (x as num).toInt()).toList();
    List<double> dbls(String k) => (m[k] as List).map((x) => (x as num).toDouble()).toList();
    final s = ReportSeries(
      t: (m['t'] as List).cast<String>(),
      now: ints('now'),
      pred: ints('pred'),
      actual: ints('actual'),
      risk: dbls('risk'),
      hr: dbls('hr'),
      spo2: dbls('spo2'),
      temp: dbls('temp'),
      sbp: dbls('sbp'),
    );
    final n = s.t.length;
    if ([s.now, s.pred, s.actual, s.risk, s.hr, s.spo2, s.temp, s.sbp].any((l) => l.length != n)) {
      throw const FormatException('series arrays must have equal length');
    }
    return s;
  }

  /// Index of the reading at [onset] (matching timestamp), or -1.
  int indexOf(String onset) => t.indexOf(onset);
}

String _dataKind(Map<String, Object?> m) {
  final v = _str(m, 'data_kind');
  if (v == 'simulated' || v == 'real') return v;
  throw const FormatException('data_kind must be "simulated" or "real"');
}

Map<String, Object?> _obj(Object? v, String name) {
  if (v is Map) return v.cast<String, Object?>();
  throw FormatException('$name must be an object');
}

String _str(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is String) return v;
  throw FormatException('$k must be a string');
}

int _int(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is num) return v.toInt();
  throw FormatException('$k must be a number');
}

double _num(Map<String, Object?> m, String k) {
  final v = m[k];
  if (v is num) return v.toDouble();
  throw FormatException('$k must be a number');
}
