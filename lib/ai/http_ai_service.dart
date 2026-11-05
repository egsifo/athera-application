import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../domain/ai_models.dart';
import 'ai_service.dart';

/// REST client for the ATHERA AI gateway (see backend/ and AI_INTEGRATION.md).
///
/// * Requests are validated locally before they are sent.
/// * Responses are parsed strictly; a malformed response is an error, never
///   "repaired" or replaced with made-up values.
/// * Transient failures (network, timeout, 5xx) are retried with backoff;
///   4xx and schema errors are not.
class HttpAiService implements AiService {
  HttpAiService({
    required String baseUrl,
    required this.apiKey,
    http.Client? client,
    this.timeout = AppConfig.aiTimeout,
    this.retry = const RetryPolicy(),
  })  : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;

  /// Read lazily from secure storage on every request; never kept in a field.
  final Future<String?> Function() apiKey;
  final Duration timeout;
  final RetryPolicy retry;
  final http.Client _client;

  @override
  String get name => 'HTTP gateway ($baseUrl)';
  @override
  bool get isIllustrative => false;
  @override
  bool get supportsForecast => true;

  @override
  Future<ModelStatusInfo> getModelStatus() async =>
      ModelStatusInfo.parse(await send('GET', '/api/v1/model-status'));

  @override
  Future<ForecastResult> getForecast(ForecastRequest request) async {
    request.validate();
    return ForecastResult.parse(await send('POST', '/api/v1/forecast', body: request.toJson()));
  }

  @override
  Future<RiskResult> getRiskAssessment(RiskRequest request) async {
    request.validate();
    return RiskResult.parse(await send('POST', '/api/v1/risk-assessment', body: request.toJson()));
  }

  @override
  Future<List<RiskResult>> getPredictionHistory(String astronautId, {int limit = 50}) async {
    final json = asObj(
      await send('GET', '/api/v1/predictions', query: {'astronaut_id': astronautId, 'limit': '$limit'}),
      'history',
    );
    final items = json['items'];
    if (items is! List) throw AiException(AiErrorKind.badResponse, 'history.items: expected list');
    return items.map((e) => RiskResult.parse(e)).toList();
  }

  /// Shared transport (retry, timeout, error mapping). Subclasses reuse it.
  Future<Object?> send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
  }) async {
    if (baseUrl.isEmpty || !(baseUrl.startsWith('http://') || baseUrl.startsWith('https://'))) {
      throw AiException(AiErrorKind.notConfigured, 'AI base URL is empty or invalid');
    }
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final maxAttempts = retry.delays.length + 1;
    for (var attempt = 0;; attempt++) {
      try {
        return await _once(method, uri, body);
      } on AiException catch (e) {
        if (!e.retryable || attempt >= maxAttempts - 1) rethrow;
        await Future<void>.delayed(retry.delays[attempt]);
      }
    }
  }

  Future<Object?> _once(String method, Uri uri, Map<String, Object?>? body) async {
    final key = await apiKey();
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (key != null && key.isNotEmpty) 'X-API-Key': key,
    };
    final http.Response resp;
    try {
      final future = method == 'GET'
          ? _client.get(uri, headers: headers)
          : _client.post(uri, headers: headers, body: jsonEncode(body));
      resp = await future.timeout(timeout);
    } on TimeoutException {
      throw AiException(AiErrorKind.timeout, 'No answer within ${timeout.inSeconds}s');
    } on SocketException catch (e) {
      throw AiException(AiErrorKind.unavailable, 'Cannot reach ${uri.host}: ${e.message}');
    } on http.ClientException catch (e) {
      throw AiException(AiErrorKind.unavailable, 'Cannot reach ${uri.host}: ${e.message}');
    }

    final status = resp.statusCode;
    if (status >= 200 && status < 300) {
      try {
        return jsonDecode(utf8.decode(resp.bodyBytes));
      } on FormatException {
        throw AiException(AiErrorKind.badResponse, 'Response is not valid JSON', statusCode: status);
      }
    }
    final err = _errorBody(resp);
    if (status == 401 || status == 403) {
      throw AiException(AiErrorKind.unauthorized, err.$1, statusCode: status);
    }
    if (status == 400 || status == 422) {
      throw AiException(AiErrorKind.validation, err.$1, statusCode: status, details: err.$2);
    }
    if (status == 404) {
      throw AiException(AiErrorKind.notConfigured, 'Endpoint not found (${uri.path})', statusCode: status);
    }
    if (status == 502 || status == 503 || status == 504) {
      throw AiException(AiErrorKind.unavailable, err.$1, statusCode: status);
    }
    if (status >= 500) {
      throw AiException(AiErrorKind.server, err.$1, statusCode: status);
    }
    throw AiException(AiErrorKind.badResponse, 'Unexpected HTTP $status', statusCode: status);
  }

  (String, List<String>) _errorBody(http.Response r) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final e = (j as Map)['error'];
      if (e is Map) {
        return (
          (e['message'] as String?) ?? 'HTTP ${r.statusCode}',
          ((e['details'] as List?) ?? const []).map((x) => x.toString()).toList(),
        );
      }
      final d = j['detail'];
      if (d is String) return (d, const []);
      if (d is List && d.isNotEmpty) {
        final items = d.map((x) => x is Map ? '${(x['loc'] as List?)?.join('.') ?? ''}: ${x['msg']}' : x.toString()).toList();
        return ('Request rejected by the service', items.map((e) => e.toString()).toList());
      }
    } catch (_) {}
    return ('HTTP ${r.statusCode}', const []);
  }

  void close() => _client.close();
}
