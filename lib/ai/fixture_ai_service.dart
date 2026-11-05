import '../domain/ai_models.dart';
import '../domain/models.dart';
import '../sensors/demo_generator.dart';
import 'ai_service.dart';

/// Offline stand-in used only in demo mode. IT IS NOT A MODEL.
///
/// * Forecast = last observed value held flat, plus a SCRIPTED drift for the
///   "developing warning" storyline so the chart has something to show.
/// * Risk = a fixed fixture chosen by the simulator's scenario.
/// Every result carries status = mock and a name saying so; the UI shows an
/// ILLUSTRATIVE badge and never presents these as medical predictions.
class FixtureAiService implements AiService {
  FixtureAiService(this.scenarioOf);

  final DemoScenario Function(String astronautId) scenarioOf;

  static const forecastName = 'DEMO-FIXTURE (flat hold, not a model)';
  static const riskName = 'DEMO-FIXTURE (scripted, not a model)';
  static const version = 'fixture-0';

  @override
  String get name => 'Built-in demo fixtures';
  @override
  bool get isIllustrative => true;
  @override
  bool get supportsForecast => true;

  @override
  Future<ModelStatusInfo> getModelStatus() async => ModelStatusInfo(
        serviceVersion: version,
        mode: 'mock',
        status: 'ok',
        checkedAt: DateTime.now().toUtc(),
        forecastModel: const ModelInfo(forecastName, version, 'mock'),
        riskModel: const ModelInfo(riskName, version, 'mock'),
        supportedHorizonsSeconds: const [300, 600, 1800],
        minWindowSize: 10,
        maxWindowSize: 1440,
      );

  @override
  Future<ForecastResult> getForecast(ForecastRequest request) async {
    request.validate();
    final now = DateTime.now().toUtc();
    final held = <VitalType, double>{};
    for (final t in VitalType.values.where((v) => v.isForecastable)) {
      for (final m in request.measurements.reversed) {
        final v = m.values[t];
        if (v != null) {
          held[t] = v;
          break;
        }
      }
    }
    final step = request.samplingIntervalSeconds;
    final steps = (request.predictionHorizonSeconds ~/ step).clamp(1, 2000);
    final developing = scenarioOf(request.astronautId) == DemoScenario.developingWarning;
    final last = request.measurements.last.timestamp;
    final points = <PredictedPoint>[];
    for (var i = 0; i < steps; i++) {
      final f = (i + 1) / steps;
      final vals = <VitalType, double>{};
      held.forEach((t, v) {
        var d = 0.0;
        if (developing) {
          d = switch (t) {
            VitalType.heartRate => 6 * f,
            VitalType.respiratoryRate => 2.5 * f,
            VitalType.spo2 => -1.0 * f,
            VitalType.temperature => 0.2 * f,
            _ => 0.0,
          };
        }
        vals[t] = double.parse((v + d).toStringAsFixed(2));
      });
      points.add(PredictedPoint(last.add(Duration(seconds: step * (i + 1))), vals));
    }
    return ForecastResult(
      astronautId: request.astronautId,
      modelName: forecastName,
      modelVersion: version,
      status: ResultStatus.mock,
      horizonSeconds: request.predictionHorizonSeconds,
      stepSeconds: step,
      predictions: points,
      generatedAt: now,
      receivedAt: now,
      dataQuality: const DataQualityReport(notes: ['Illustrative fixture: values are not model output.']),
    );
  }

  @override
  Future<RiskResult> getRiskAssessment(RiskRequest request) async {
    request.validate();
    final now = DateTime.now().toUtc();
    final sc = scenarioOf(request.astronautId);
    final (cls, score) = switch (sc) {
      DemoScenario.nominal => (RiskClass.normal, 12.0),
      DemoScenario.eva => (RiskClass.normal, 22.0),
      DemoScenario.developingWarning => (RiskClass.earlyWarning, 56.0),
      DemoScenario.sensorDropout => (RiskClass.unknown, null),
    };
    final dev = sc == DemoScenario.developingWarning;
    return RiskResult(
      astronautId: request.astronautId,
      modelName: riskName,
      modelVersion: version,
      status: ResultStatus.mock,
      riskClass: cls,
      riskScore: score,
      generatedAt: now,
      receivedAt: now,
      contributingFeatures: dev
          ? const [
              ContributingFeature(
                feature: 'respiratory_rate_bpm_delta_vs_baseline',
                direction: 'increase',
                description: 'Scripted example of a contributing feature.',
              ),
              ContributingFeature(
                feature: 'spo2_percent_slope_per_hour_15m',
                direction: 'decrease',
                description: 'Scripted example of a contributing feature.',
              ),
            ]
          : const [],
      warnings: [
        const ModelWarning(
          code: 'DEMO_FIXTURE',
          message: 'ILLUSTRATIVE fixture. This is not a model output and not a medical prediction.',
          severity: 'info',
        ),
        if (dev)
          const ModelWarning(
            code: 'DEMO_RESP_TREND',
            message: 'Scripted example: respiratory rate trending upward relative to baseline.',
            severity: 'warning',
          ),
        if (sc == DemoScenario.sensorDropout)
          const ModelWarning(
            code: 'DEMO_INSUFFICIENT_DATA',
            message: 'Scripted example: not enough recent data to classify.',
            severity: 'warning',
          ),
      ],
      anomalies: dev
          ? [
              AnomalyReport(
                metric: 'respiratory_rate_bpm',
                timestamp: now,
                description: 'Scripted example anomaly (illustrative only).',
              ),
            ]
          : const [],
    );
  }

  @override
  Future<List<RiskResult>> getPredictionHistory(String astronautId, {int limit = 50}) async => const [];
}
