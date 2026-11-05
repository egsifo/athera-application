import '../domain/ai_models.dart';
import 'ai_service.dart';
import 'http_ai_service.dart';

/// Column names (and order) the ATHERA model expects in every reading.
/// Must match `Reading` in the model's api.py and `VITALS` in athera_ai.py.
const kModelFields = <String>[
  'Heart_Rate',
  'SBP',
  'DBP',
  'SpO2',
  'Body_Temp',
  'HRV_Stress_Index',
  'Radiation_Level',
  'Sleep_Hours',
  'Physical_Activity_Load',
];

/// Readings the model needs, and how far apart they are.
const kModelMinReadings = 13;
const kModelIntervalSeconds = 900;

/// Client for the team's own model server (api.py):
///   GET  /         -> {"status":"ok","predicts_minutes_ahead":120}
///   POST /predict  -> {"history":[{9 fields}, ...]}  (13+ readings, 15 min apart)
///
/// This model classifies risk ahead of time. It does NOT forecast vital signs,
/// so [supportsForecast] is false and [getForecast] always fails: the app never
/// draws a made-up forecast curve.
class AtheraModelService extends HttpAiService {
  AtheraModelService({
    required super.baseUrl,
    required super.apiKey,
    super.client,
    super.timeout,
    super.retry,
  });

  @override
  String get name => 'ATHERA model ($baseUrl)';

  @override
  bool get supportsForecast => false;

  @override
  Future<ModelStatusInfo> getModelStatus() async {
    final m = asObj(await send('GET', '/'), 'status');
    final minutes = reqInt(m, 'predicts_minutes_ahead', 'status');
    final status = reqStr(m, 'status', 'status');
    return ModelStatusInfo(
      serviceVersion: 'not reported',
      mode: 'live model',
      status: status,
      checkedAt: DateTime.now().toUtc(),
      riskModel: ModelInfo('ATHERA risk model', 'not reported', status),
      supportedHorizonsSeconds: [minutes * 60],
      minWindowSize: kModelMinReadings,
    );
  }

  @override
  Future<ForecastResult> getForecast(ForecastRequest request) async => throw AiException(
        AiErrorKind.notConfigured,
        'This model predicts a risk class, not vital-sign values, so there is no forecast.',
      );

  @override
  Future<RiskResult> getRiskAssessment(RiskRequest request) async {
    final rows = request.modelHistory;
    if (rows == null) {
      throw AiException(AiErrorKind.validation, 'No model input was prepared (history missing).');
    }
    final problems = validateRows(rows);
    if (problems.isNotEmpty) {
      throw AiException(AiErrorKind.validation, 'Model input is incomplete', details: problems);
    }
    final body = {
      'history': [
        for (final r in rows) {for (final k in kModelFields) k: r.values[k]},
      ],
    };
    final json = await send('POST', '/predict', body: body);
    return parsePrediction(
      json,
      astronautId: request.astronautId,
      inputSimulated: request.inputSimulated,
    );
  }

  /// The model keeps its own history; the app stores results locally instead.
  @override
  Future<List<RiskResult>> getPredictionHistory(String astronautId, {int limit = 50}) async => const [];

  /// Checks done before sending, so a bad request never reaches the model.
  static List<String> validateRows(List<ModelRow> rows) {
    final errs = <String>[];
    if (rows.length < kModelMinReadings) {
      errs.add('need at least $kModelMinReadings readings, have ${rows.length}');
    }
    for (var i = 0; i < rows.length; i++) {
      for (final k in kModelFields) {
        final v = rows[i].values[k];
        if (v == null || !v.isFinite) {
          errs.add('reading ${i + 1}: $k missing');
          break;
        }
      }
      if (i > 0 && !rows[i].timestamp.isAfter(rows[i - 1].timestamp)) {
        errs.add('readings must be oldest first');
        break;
      }
      if (errs.length > 5) break;
    }
    return errs;
  }

  static RiskClass _cls(Object? v, String path) => switch (v) {
        'SAFE' => RiskClass.normal,
        'EARLY_WARNING' => RiskClass.earlyWarning,
        'CRITICAL' => RiskClass.critical,
        _ => throw AiException(AiErrorKind.badResponse, '$path: expected SAFE | EARLY_WARNING | CRITICAL, got "$v"'),
      };

  /// Maps the model's reply onto [RiskResult]. Strict: a reply that does not
  /// match the contract is an error, never repaired.
  static RiskResult parsePrediction(
    Object? raw, {
    required String astronautId,
    bool inputSimulated = false,
    DateTime? now,
  }) {
    const p = 'predict';
    final m = asObj(raw, p);
    final predicted = _cls(m['predicted_status'], '$p.predicted_status');
    final current = _cls(m['current_status'], '$p.current_status');
    final minutes = reqInt(m, 'minutes_ahead', p);
    final score = optNum(m, 'risk_score', p);
    if (score != null && (score < 0 || score > 100)) {
      throw AiException(AiErrorKind.badResponse, '$p.risk_score: must be within 0..100');
    }

    Map<RiskClass, double>? probs;
    final rp = m['probabilities'];
    if (rp != null) {
      final pm = asObj(rp, '$p.probabilities');
      final safe = optNum(pm, 'safe', '$p.probabilities');
      final early = optNum(pm, 'early_warning', '$p.probabilities');
      final crit = optNum(pm, 'critical', '$p.probabilities');
      if (safe == null || early == null || crit == null) {
        throw AiException(AiErrorKind.badResponse, '$p.probabilities: safe, early_warning and critical are required');
      }
      probs = {RiskClass.normal: safe, RiskClass.earlyWarning: early, RiskClass.critical: crit};
    }

    final reasons = (m['reasons'] as List?)?.whereType<String>() ?? const <String>[];
    final alert = m['alert'];
    final received = now ?? DateTime.now().toUtc();
    final warnings = <ModelWarning>[
      if (alert is String && alert.isNotEmpty)
        ModelWarning(
          code: 'model_alert',
          message: alert,
          severity: predicted == RiskClass.critical || current == RiskClass.critical
              ? 'critical'
              : (predicted == RiskClass.earlyWarning || current == RiskClass.earlyWarning ? 'warning' : 'info'),
        ),
    ];

    return RiskResult(
      astronautId: astronautId,
      modelName: 'ATHERA model',
      modelVersion: 'not reported',
      status: ResultStatus.ok,
      riskClass: predicted,
      riskScore: score,
      classProbabilities: probs,
      // The model does not send a timestamp: this is when the app received it.
      generatedAt: received,
      receivedAt: received,
      contributingFeatures: [for (final r in reasons) ContributingFeature(feature: r)],
      warnings: warnings,
      horizonMinutes: minutes,
      currentClass: current,
      inputSimulated: inputSimulated,
    );
  }
}
