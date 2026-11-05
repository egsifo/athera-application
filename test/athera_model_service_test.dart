import 'dart:convert';

import 'package:athera/ai/ai_service.dart';
import 'package:athera/ai/athera_model_service.dart';
import 'package:athera/domain/ai_models.dart';
import 'package:athera/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<ModelRow> _rows(int n, {String? drop}) {
  final t0 = DateTime.utc(2026, 11, 5, 0, 0);
  return [
    for (var i = 0; i < n; i++)
      ModelRow(t0.add(Duration(minutes: 15 * i)), {
        for (final k in kModelFields)
          if (k != drop) k: 70.0,
      }),
  ];
}

RiskRequest _req(List<ModelRow>? rows) => RiskRequest(
      astronautId: 'a1',
      assessedAt: DateTime.utc(2026, 11, 5, 4),
      current: MeasurementDto(DateTime.utc(2026, 11, 5, 4), {VitalType.heartRate: 70}),
      features: const {},
      modelHistory: rows,
      inputSimulated: true,
    );

const _okReply = {
  'current_status': 'SAFE',
  'predicted_status': 'EARLY_WARNING',
  'minutes_ahead': 120,
  'risk_score': 31.5,
  'probabilities': {'safe': 0.5, 'early_warning': 0.37, 'critical': 0.13},
  'reasons': ['Heart rate rising fast'],
  'alert': 'Early warning: vitals are drifting (risk 31.5%). Rest and recheck.',
};

AtheraModelService _svc(http.Client c) =>
    AtheraModelService(baseUrl: 'http://x:8000/', apiKey: () async => null, client: c, retry: RetryPolicy.none);

void main() {
  test('sends 13 readings with exactly the 9 model fields to /predict', () async {
    late http.Request seen;
    final svc = _svc(MockClient((r) async {
      seen = r;
      return http.Response(jsonEncode(_okReply), 200, headers: {'content-type': 'application/json'});
    }));
    final res = await svc.getRiskAssessment(_req(_rows(13)));
    expect(seen.url.path, '/predict');
    final body = jsonDecode(seen.body) as Map;
    final hist = body['history'] as List;
    expect(hist.length, 13);
    expect((hist.first as Map).keys.toSet(), kModelFields.toSet());
    expect(res.riskClass, RiskClass.earlyWarning);
    expect(res.currentClass, RiskClass.normal);
    expect(res.horizonMinutes, 120);
    expect(res.riskScore, 31.5);
    expect(res.inputSimulated, isTrue);
    expect(res.contributingFeatures.single.feature, 'Heart rate rising fast');
    expect(res.warnings.single.severity, 'warning');
    // Survives the local database round trip.
    final again = RiskResult.parse(jsonDecode(jsonEncode(res.toJson())));
    expect(again.horizonMinutes, 120);
    expect(again.inputSimulated, isTrue);
  });

  test('refuses to send fewer than 13 readings or a missing field', () async {
    var calls = 0;
    final svc = _svc(MockClient((r) async {
      calls++;
      return http.Response('{}', 200);
    }));
    await expectLater(svc.getRiskAssessment(_req(_rows(12))), throwsA(isA<AiException>()));
    await expectLater(svc.getRiskAssessment(_req(_rows(13, drop: 'SBP'))), throwsA(isA<AiException>()));
    await expectLater(svc.getRiskAssessment(_req(null)), throwsA(isA<AiException>()));
    expect(calls, 0);
  });

  test('model 400 detail is shown, 5xx is unavailable', () async {
    final bad = _svc(MockClient((r) async => http.Response(jsonEncode({'detail': 'need 13 readings'}), 400)));
    try {
      await bad.getRiskAssessment(_req(_rows(13)));
      fail('should throw');
    } on AiException catch (e) {
      expect(e.kind, AiErrorKind.validation);
      expect(e.message, 'need 13 readings');
    }
    final down = _svc(MockClient((r) async => http.Response('boom', 503)));
    await expectLater(
      down.getRiskAssessment(_req(_rows(13))),
      throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.unavailable)),
    );
  });

  test('malformed reply is an error, not repaired', () async {
    final svc = _svc(MockClient((r) async => http.Response(jsonEncode({'predicted_status': 'MAYBE'}), 200)));
    await expectLater(
      svc.getRiskAssessment(_req(_rows(13))),
      throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.badResponse)),
    );
  });

  test('status reads GET / and there is no forecast', () async {
    final svc = _svc(MockClient((r) async {
      expect(r.url.path, '/');
      return http.Response(jsonEncode({'status': 'ok', 'predicts_minutes_ahead': 120}), 200);
    }));
    final s = await svc.getModelStatus();
    expect(s.supportedHorizonsSeconds, [7200]);
    expect(svc.supportsForecast, isFalse);
  });
}
