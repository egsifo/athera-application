import '../domain/ai_models.dart';

/// The only door through which the app talks to AI models. UI code never
/// calls HTTP or builds model payloads; it asks the controller, which asks
/// an [AiService]. Swap the implementation (fixture, HTTP gateway, direct
/// model host) without touching screens.
abstract class AiService {
  String get name;

  /// True for implementations that return scripted/illustrative results.
  bool get isIllustrative;

  /// False for models that classify risk only (no per-vital forecast). The
  /// controller then skips [getForecast] and the UI hides the forecast chart.
  bool get supportsForecast;

  Future<ModelStatusInfo> getModelStatus();
  Future<ForecastResult> getForecast(ForecastRequest request);
  Future<RiskResult> getRiskAssessment(RiskRequest request);
  Future<List<RiskResult>> getPredictionHistory(String astronautId, {int limit = 50});
}

/// Used when no AI source is configured (demo mode off, no gateway selected).
/// Every call fails explicitly instead of returning anything.
class UnconfiguredAiService implements AiService {
  @override
  String get name => 'Not configured';
  @override
  bool get isIllustrative => false;
  @override
  bool get supportsForecast => true;

  AiException get _err => AiException(
        AiErrorKind.notConfigured,
        'Choose "HTTP gateway" in Settings and enter your AI service URL.',
      );

  @override
  Future<ModelStatusInfo> getModelStatus() async => throw _err;
  @override
  Future<ForecastResult> getForecast(ForecastRequest request) async => throw _err;
  @override
  Future<RiskResult> getRiskAssessment(RiskRequest request) async => throw _err;
  @override
  Future<List<RiskResult>> getPredictionHistory(String astronautId, {int limit = 50}) async => throw _err;
}

class RetryPolicy {
  const RetryPolicy({this.delays = const [Duration(milliseconds: 400), Duration(milliseconds: 1200)]});

  /// Wait before retry n. Total attempts = delays.length + 1.
  final List<Duration> delays;
  static const none = RetryPolicy(delays: []);
}
