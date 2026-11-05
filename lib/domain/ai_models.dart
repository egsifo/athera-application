import 'models.dart';

/// Contract models for the external AI service. They mirror
/// backend/app/schemas.py. Parsing is strict about required fields and never
/// invents values: absent optional data stays null.

enum AiErrorKind { unavailable, timeout, unauthorized, validation, badResponse, server, notConfigured }

class AiException implements Exception {
  AiException(this.kind, this.message, {this.statusCode, this.details = const []});
  final AiErrorKind kind;
  final String message;
  final int? statusCode;
  final List<String> details;

  /// Only transient failures are retried; 4xx and schema errors never are.
  bool get retryable =>
      kind == AiErrorKind.unavailable || kind == AiErrorKind.timeout || kind == AiErrorKind.server;

  String get headline => switch (kind) {
        AiErrorKind.unavailable => 'AI service unavailable',
        AiErrorKind.timeout => 'AI service timed out',
        AiErrorKind.unauthorized => 'AI service rejected the API key',
        AiErrorKind.validation => 'Request not sent',
        AiErrorKind.badResponse => 'AI service returned an invalid response',
        AiErrorKind.server => 'AI service error',
        AiErrorKind.notConfigured => 'AI service not configured',
      };

  @override
  String toString() => '$headline: $message';
}

enum RiskClass { normal, earlyWarning, critical, unknown }

extension RiskClassX on RiskClass {
  String get wire => switch (this) {
        RiskClass.normal => 'normal',
        RiskClass.earlyWarning => 'early_warning',
        RiskClass.critical => 'critical',
        RiskClass.unknown => 'unknown',
      };
  String get label => switch (this) {
        RiskClass.normal => 'Normal',
        RiskClass.earlyWarning => 'Early warning',
        RiskClass.critical => 'Critical',
        RiskClass.unknown => 'Unknown',
      };
  int get rank => switch (this) {
        RiskClass.critical => 3,
        RiskClass.earlyWarning => 2,
        RiskClass.normal => 1,
        RiskClass.unknown => 0,
      };
}

RiskClass? riskClassFromWire(String? s) {
  for (final c in RiskClass.values) {
    if (c.wire == s) return c;
  }
  return null;
}

enum ResultStatus { ok, mock, degraded }

// ---------------------------------------------------------------------------
// Tiny strict JSON helpers
// ---------------------------------------------------------------------------
final _tzSuffix = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');
final _idPattern = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

AiException _bad(String path, String why) =>
    AiException(AiErrorKind.badResponse, '$path: $why');

Map<String, dynamic> asObj(Object? v, String path) {
  if (v is Map) return Map<String, dynamic>.from(v);
  throw _bad(path, 'expected object');
}

String reqStr(Map<String, dynamic> m, String k, String path) {
  final v = m[k];
  if (v is String && v.isNotEmpty) return v;
  throw _bad('$path.$k', 'required string missing');
}

String? optStr(Map<String, dynamic> m, String k) {
  final v = m[k];
  return v is String ? v : null;
}

double? optNum(Map<String, dynamic> m, String k, String path) {
  final v = m[k];
  if (v == null) return null;
  if (v is num && v.isFinite) return v.toDouble();
  throw _bad('$path.$k', 'expected finite number or null');
}

int reqInt(Map<String, dynamic> m, String k, String path, {int min = 1}) {
  final v = m[k];
  if (v is num && v == v.roundToDouble() && v >= min) return v.toInt();
  throw _bad('$path.$k', 'required integer >= $min');
}

DateTime reqTime(Map<String, dynamic> m, String k, String path) {
  final v = m[k];
  if (v is String && _tzSuffix.hasMatch(v)) {
    final t = DateTime.tryParse(v);
    if (t != null) return t.toUtc();
  }
  throw _bad('$path.$k', 'required timezone-aware ISO-8601 timestamp');
}

DateTime? optTime(Map<String, dynamic> m, String k, String path) {
  if (m[k] == null) return null;
  return reqTime(m, k, path);
}

String iso(DateTime t) => t.toUtc().toIso8601String();

// ---------------------------------------------------------------------------
// Shared pieces
// ---------------------------------------------------------------------------
class MeasurementDto {
  const MeasurementDto(this.timestamp, this.values);
  final DateTime timestamp;
  final Map<VitalType, double?> values;

  Map<String, Object?> toJson() => {
        'timestamp': iso(timestamp),
        for (final e in values.entries)
          if (e.value != null) e.key.apiField: e.value,
      };

  bool get hasAnyValue => values.values.any((v) => v != null);
}

class PredictedPoint {
  const PredictedPoint(this.timestamp, this.values);
  final DateTime timestamp;
  final Map<VitalType, double> values;

  factory PredictedPoint.parse(Object? raw, String path) {
    final m = asObj(raw, path);
    final vals = <VitalType, double>{};
    for (final t in VitalType.values) {
      final v = optNum(m, t.apiField, path);
      if (v != null) vals[t] = v;
    }
    return PredictedPoint(reqTime(m, 'timestamp', path), vals);
  }

  Map<String, Object?> toJson() => {
        'timestamp': iso(timestamp),
        for (final e in values.entries) e.key.apiField: e.value,
      };
}

class DataQualityReport {
  const DataQualityReport({this.inputCompleteness, this.notes = const []});
  final Map<String, double>? inputCompleteness;
  final List<String> notes;

  factory DataQualityReport.parse(Object? raw, String path) {
    final m = asObj(raw, path);
    Map<String, double>? comp;
    final c = m['input_completeness'];
    if (c is Map) {
      comp = {};
      c.forEach((k, v) {
        if (v is num && v >= 0 && v <= 1) comp![k.toString()] = v.toDouble();
      });
    }
    return DataQualityReport(
      inputCompleteness: comp,
      notes: ((m['notes'] as List?) ?? const []).whereType<String>().toList(),
    );
  }

  Map<String, Object?> toJson() => {'input_completeness': inputCompleteness, 'notes': notes};
}

// ---------------------------------------------------------------------------
// Forecast
// ---------------------------------------------------------------------------
class ForecastRequest {
  ForecastRequest({
    required this.astronautId,
    required this.windowSize,
    required this.samplingIntervalSeconds,
    required this.predictionHorizonSeconds,
    required this.measurements,
  });
  final String astronautId;
  final int windowSize;
  final int samplingIntervalSeconds;
  final int predictionHorizonSeconds;
  final List<MeasurementDto> measurements;

  /// Client-side validation. The service validates again; this just avoids
  /// sending requests that are guaranteed to be rejected.
  void validate() {
    final errs = <String>[];
    if (!_idPattern.hasMatch(astronautId)) errs.add('astronaut_id: invalid');
    if (windowSize < 2) errs.add('window_size must be >= 2');
    if (samplingIntervalSeconds < 1) errs.add('sampling_interval_seconds must be >= 1');
    if (predictionHorizonSeconds < samplingIntervalSeconds) {
      errs.add('prediction_horizon_seconds must be >= sampling interval');
    }
    if (measurements.length != windowSize) {
      errs.add('measurements has ${measurements.length} rows, window_size is $windowSize');
    }
    for (var i = 1; i < measurements.length; i++) {
      if (!measurements[i].timestamp.isAfter(measurements[i - 1].timestamp)) {
        errs.add('timestamps must be strictly increasing (row $i)');
        break;
      }
    }
    if (measurements.isNotEmpty && !measurements.any((m) => m.hasAnyValue)) {
      errs.add('no measured values in window');
    }
    for (final m in measurements) {
      for (final e in m.values.entries) {
        final v = e.value;
        if (v != null && (!v.isFinite || v < e.key.validMin || v > e.key.validMax)) {
          errs.add('${e.key.apiField} out of valid range at ${iso(m.timestamp)}');
          break;
        }
      }
      if (errs.length > 5) break;
    }
    if (errs.isNotEmpty) {
      throw AiException(AiErrorKind.validation, 'Forecast request is invalid', details: errs);
    }
  }

  Map<String, Object?> toJson() => {
        'astronaut_id': astronautId,
        'window_size': windowSize,
        'sampling_interval_seconds': samplingIntervalSeconds,
        'prediction_horizon_seconds': predictionHorizonSeconds,
        'measurements': measurements.map((m) => m.toJson()).toList(),
      };
}

class ForecastResult {
  ForecastResult({
    required this.astronautId,
    required this.modelName,
    required this.modelVersion,
    required this.status,
    required this.horizonSeconds,
    required this.stepSeconds,
    required this.predictions,
    required this.generatedAt,
    required this.receivedAt,
    this.dataQuality,
  });

  final String astronautId;
  final String modelName;
  final String modelVersion;
  final ResultStatus status;
  final int horizonSeconds;
  final int stepSeconds;
  final List<PredictedPoint> predictions;
  final DateTime generatedAt;

  /// App clock when the response arrived (used for freshness).
  final DateTime receivedAt;
  final DataQualityReport? dataQuality;

  bool get isMock => status == ResultStatus.mock;

  factory ForecastResult.parse(Object? raw, {DateTime? now}) {
    const p = 'forecast';
    final m = asObj(raw, p);
    final status = _status(m, p);
    final horizon = reqInt(m, 'prediction_horizon_seconds', p);
    final step = reqInt(m, 'step_seconds', p);
    if (step > horizon) throw _bad(p, 'step_seconds exceeds prediction_horizon_seconds');
    final list = m['predictions'];
    if (list is! List || list.isEmpty) throw _bad('$p.predictions', 'non-empty list required');
    final preds = [for (var i = 0; i < list.length; i++) PredictedPoint.parse(list[i], '$p.predictions[$i]')];
    for (var i = 1; i < preds.length; i++) {
      if (!preds[i].timestamp.isAfter(preds[i - 1].timestamp)) {
        throw _bad('$p.predictions', 'timestamps must be strictly increasing');
      }
    }
    return ForecastResult(
      astronautId: reqStr(m, 'astronaut_id', p),
      modelName: reqStr(m, 'model_name', p),
      modelVersion: reqStr(m, 'model_version', p),
      status: status,
      horizonSeconds: horizon,
      stepSeconds: step,
      predictions: preds,
      generatedAt: reqTime(m, 'generated_at', p),
      receivedAt: now ?? DateTime.now().toUtc(),
      dataQuality: m['data_quality'] == null ? null : DataQualityReport.parse(m['data_quality'], '$p.data_quality'),
    );
  }

  Map<String, Object?> toJson() => {
        'astronaut_id': astronautId,
        'model_name': modelName,
        'model_version': modelVersion,
        'status': status.name,
        'prediction_horizon_seconds': horizonSeconds,
        'step_seconds': stepSeconds,
        'predictions': predictions.map((x) => x.toJson()).toList(),
        'generated_at': iso(generatedAt),
        if (dataQuality != null) 'data_quality': dataQuality!.toJson(),
      };
}

ResultStatus _status(Map<String, dynamic> m, String p) {
  final s = m['status'];
  for (final r in ResultStatus.values) {
    if (r.name == s) return r;
  }
  throw _bad('$p.status', 'must be ok | mock | degraded');
}

// ---------------------------------------------------------------------------
// Risk assessment
// ---------------------------------------------------------------------------
class ForecastSummaryDto {
  const ForecastSummaryDto({
    required this.modelName,
    required this.modelVersion,
    required this.stepSeconds,
    required this.predictions,
  });
  final String modelName;
  final String modelVersion;
  final int stepSeconds;
  final List<PredictedPoint> predictions;

  factory ForecastSummaryDto.fromResult(ForecastResult f) => ForecastSummaryDto(
        modelName: f.modelName,
        modelVersion: f.modelVersion,
        stepSeconds: f.stepSeconds,
        predictions: f.predictions,
      );

  Map<String, Object?> toJson() => {
        'model_name': modelName,
        'model_version': modelVersion,
        'step_seconds': stepSeconds,
        'predictions': predictions.map((p) => p.toJson()).toList(),
      };
}

/// One 15-minute reading in the exact column layout of the ATHERA model's
/// `/predict` endpoint (see AI_INTEGRATION.md). Only used by AtheraModelService.
class ModelRow {
  const ModelRow(this.timestamp, this.values);
  final DateTime timestamp;
  final Map<String, double> values;
}

class RiskRequest {
  RiskRequest({
    required this.astronautId,
    required this.assessedAt,
    required this.current,
    required this.features,
    this.forecast,
    this.modelHistory,
    this.inputSimulated = false,
  });
  final String astronautId;
  final DateTime assessedAt;
  final MeasurementDto current;
  final Map<String, double?> features;
  final ForecastSummaryDto? forecast;

  /// Rows for the single-call `/predict` model (oldest first). Null for gateways.
  final List<ModelRow>? modelHistory;

  /// True when the inputs were produced by the demo simulator.
  final bool inputSimulated;

  void validate() {
    final errs = <String>[];
    if (!_idPattern.hasMatch(astronautId)) errs.add('astronaut_id: invalid');
    if (!current.hasAnyValue) errs.add('current measurement has no values');
    if (features.length > 200) errs.add('features: at most 200 entries');
    for (final e in features.entries) {
      final v = e.value;
      if (v != null && !v.isFinite) errs.add('feature ${e.key} is not finite');
    }
    if (errs.isNotEmpty) {
      throw AiException(AiErrorKind.validation, 'Risk request is invalid', details: errs);
    }
  }

  Map<String, Object?> toJson() => {
        'astronaut_id': astronautId,
        'assessed_at': iso(assessedAt),
        'current': current.toJson(),
        'features': features,
        if (forecast != null) 'forecast': forecast!.toJson(),
      };
}

class ContributingFeature {
  const ContributingFeature({required this.feature, this.direction, this.weight, this.description});
  final String feature;
  final String? direction;
  final double? weight;
  final String? description;
}

class ModelWarning {
  const ModelWarning({required this.code, required this.message, required this.severity});
  final String code;
  final String message;
  final String severity;
}

class AnomalyReport {
  const AnomalyReport({required this.metric, required this.description, this.timestamp, this.score});
  final String metric;
  final String description;
  final DateTime? timestamp;
  final double? score;
}

class RiskResult {
  RiskResult({
    required this.astronautId,
    required this.modelName,
    required this.modelVersion,
    required this.status,
    required this.riskClass,
    required this.generatedAt,
    required this.receivedAt,
    this.riskScore,
    this.classProbabilities,
    this.contributingFeatures = const [],
    this.warnings = const [],
    this.anomalies = const [],
    this.dataQuality,
    this.horizonMinutes,
    this.currentClass,
    this.inputSimulated = false,
  });

  final String astronautId;
  final String modelName;
  final String modelVersion;
  final ResultStatus status;
  final RiskClass riskClass;

  /// How far ahead [riskClass] is predicted (null = not stated by the model).
  final int? horizonMinutes;

  /// The model's own classification of the latest readings (rule-based "now").
  final RiskClass? currentClass;

  /// True when the model was fed simulated (demo) data.
  final bool inputSimulated;

  /// 0-100 index defined by the model owner. NOT a probability.
  final double? riskScore;

  /// Only if the model itself produced probabilities. Never derived by the app.
  final Map<RiskClass, double>? classProbabilities;
  final DateTime generatedAt;
  final DateTime receivedAt;
  final List<ContributingFeature> contributingFeatures;
  final List<ModelWarning> warnings;
  final List<AnomalyReport> anomalies;
  final DataQualityReport? dataQuality;

  bool get isMock => status == ResultStatus.mock;

  factory RiskResult.parse(Object? raw, {DateTime? now}) {
    const p = 'risk';
    final m = asObj(raw, p);
    final cls = riskClassFromWire(m['risk_class'] as String?);
    if (cls == null) throw _bad('$p.risk_class', 'must be normal | early_warning | critical | unknown');
    final score = optNum(m, 'risk_score', p);
    if (score != null && (score < 0 || score > 100)) throw _bad('$p.risk_score', 'must be within 0..100');

    Map<RiskClass, double>? probs;
    final rawProbs = m['class_probabilities'];
    if (rawProbs != null) {
      final pm = asObj(rawProbs, '$p.class_probabilities');
      probs = {};
      var sum = 0.0;
      pm.forEach((k, v) {
        final c = riskClassFromWire(k);
        if (c == null) throw _bad('$p.class_probabilities', 'unknown class "$k"');
        if (v is! num || v < 0 || v > 1) throw _bad('$p.class_probabilities.$k', 'must be within 0..1');
        probs![c] = v.toDouble();
        sum += v.toDouble();
      });
      if ((sum - 1.0).abs() > 0.01) throw _bad('$p.class_probabilities', 'must sum to 1');
    }

    final feats = <ContributingFeature>[];
    for (final e in (m['contributing_features'] as List? ?? const [])) {
      final f = asObj(e, '$p.contributing_features');
      feats.add(ContributingFeature(
        feature: reqStr(f, 'feature', '$p.contributing_features'),
        direction: optStr(f, 'direction'),
        weight: optNum(f, 'weight', '$p.contributing_features'),
        description: optStr(f, 'description'),
      ));
    }
    final warns = <ModelWarning>[];
    for (final e in (m['warnings'] as List? ?? const [])) {
      final w = asObj(e, '$p.warnings');
      warns.add(ModelWarning(
        code: reqStr(w, 'code', '$p.warnings'),
        message: reqStr(w, 'message', '$p.warnings'),
        severity: optStr(w, 'severity') ?? 'warning',
      ));
    }
    final anoms = <AnomalyReport>[];
    for (final e in (m['anomalies'] as List? ?? const [])) {
      final a = asObj(e, '$p.anomalies');
      anoms.add(AnomalyReport(
        metric: reqStr(a, 'metric', '$p.anomalies'),
        description: reqStr(a, 'description', '$p.anomalies'),
        timestamp: optTime(a, 'timestamp', '$p.anomalies'),
        score: optNum(a, 'score', '$p.anomalies'),
      ));
    }

    return RiskResult(
      astronautId: reqStr(m, 'astronaut_id', p),
      modelName: reqStr(m, 'model_name', p),
      modelVersion: reqStr(m, 'model_version', p),
      status: _status(m, p),
      riskClass: cls,
      riskScore: score,
      classProbabilities: probs,
      generatedAt: reqTime(m, 'generated_at', p),
      receivedAt: now ?? DateTime.now().toUtc(),
      contributingFeatures: feats,
      warnings: warns,
      anomalies: anoms,
      dataQuality: m['data_quality'] == null ? null : DataQualityReport.parse(m['data_quality'], '$p.data_quality'),
      horizonMinutes: m['horizon_minutes'] == null ? null : reqInt(m, 'horizon_minutes', p),
      currentClass: riskClassFromWire(optStr(m, 'current_class')),
      inputSimulated: m['input_simulated'] == true,
    );
  }

  Map<String, Object?> toJson() => {
        'astronaut_id': astronautId,
        'model_name': modelName,
        'model_version': modelVersion,
        'status': status.name,
        if (horizonMinutes != null) 'horizon_minutes': horizonMinutes,
        if (currentClass != null) 'current_class': currentClass!.wire,
        if (inputSimulated) 'input_simulated': true,
        'risk_class': riskClass.wire,
        'risk_score': riskScore,
        'class_probabilities': classProbabilities?.map((k, v) => MapEntry(k.wire, v)),
        'generated_at': iso(generatedAt),
        'contributing_features': contributingFeatures
            .map((f) => {'feature': f.feature, 'direction': f.direction, 'weight': f.weight, 'description': f.description})
            .toList(),
        'warnings': warnings.map((w) => {'code': w.code, 'message': w.message, 'severity': w.severity}).toList(),
        'anomalies': anomalies
            .map((a) => {
                  'metric': a.metric,
                  'description': a.description,
                  'timestamp': a.timestamp == null ? null : iso(a.timestamp!),
                  'score': a.score,
                })
            .toList(),
        if (dataQuality != null) 'data_quality': dataQuality!.toJson(),
      };
}

// ---------------------------------------------------------------------------
// Model status
// ---------------------------------------------------------------------------
class ModelInfo {
  const ModelInfo(this.name, this.version, this.status);
  final String name;
  final String version;
  final String status;
}

class ModelStatusInfo {
  ModelStatusInfo({
    required this.serviceVersion,
    required this.mode,
    required this.status,
    required this.checkedAt,
    this.forecastModel,
    this.riskModel,
    this.supportedHorizonsSeconds = const [],
    this.minWindowSize,
    this.maxWindowSize,
  });
  final String serviceVersion;
  final String mode;
  final String status;
  final DateTime checkedAt;
  final ModelInfo? forecastModel;
  final ModelInfo? riskModel;
  final List<int> supportedHorizonsSeconds;
  final int? minWindowSize;
  final int? maxWindowSize;

  factory ModelStatusInfo.parse(Object? raw) {
    const p = 'model_status';
    final m = asObj(raw, p);
    ModelInfo? info(String k) {
      final v = m[k];
      if (v == null) return null;
      final o = asObj(v, '$p.$k');
      return ModelInfo(reqStr(o, 'name', '$p.$k'), reqStr(o, 'version', '$p.$k'), optStr(o, 'status') ?? 'unknown');
    }

    return ModelStatusInfo(
      serviceVersion: reqStr(m, 'service_version', p),
      mode: reqStr(m, 'mode', p),
      status: reqStr(m, 'status', p),
      checkedAt: reqTime(m, 'checked_at', p),
      forecastModel: info('forecast_model'),
      riskModel: info('risk_model'),
      supportedHorizonsSeconds:
          ((m['supported_horizons_seconds'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList(),
      minWindowSize: (m['min_window_size'] as num?)?.toInt(),
      maxWindowSize: (m['max_window_size'] as num?)?.toInt(),
    );
  }
}
