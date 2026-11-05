import unittest
from datetime import datetime, timezone

from app.config import ConfigError, Settings, load_settings
from app.errors import GatewayError
from app.gateway import Gateway
from app.upstream import UpstreamHttpError, UpstreamTimeout, UpstreamUnavailable
from tests.helpers import forecast_request, make_settings, risk_request

NOW = datetime(2026, 10, 19, 12, 30, 0, tzinfo=timezone.utc)


def clock():
    return NOW


class FakeUpstream:
    """Scripted upstream: returns `response` or raises `error`."""

    def __init__(self, response=None, error=None):
        self.response = response
        self.error = error
        self.calls = []

    def post_json(self, url, payload):
        self.calls.append((url, payload))
        if self.error:
            raise self.error
        return self.response


def proxy_settings(**kw):
    return make_settings(
        mode="proxy",
        upstream_forecast_url="https://lstm.example/predict",
        upstream_risk_url="https://xgb.example/classify",
        **kw,
    )


def good_forecast(**overrides):
    body = {
        "astronaut_id": "demo-astronaut-01",
        "model_name": "LSTM",
        "model_version": "1.2.3",
        "status": "ok",
        "prediction_horizon_seconds": 300,
        "step_seconds": 60,
        "predictions": [
            {"timestamp": f"2026-10-19T12:{12 + i}:00Z", "heart_rate_bpm": 85 + i} for i in range(5)
        ],
        "generated_at": "2026-10-19T12:11:01Z",
    }
    body.update(overrides)
    return body


def good_risk(**overrides):
    body = {
        "astronaut_id": "demo-astronaut-01",
        "model_name": "XGBoost",
        "model_version": "9.9",
        "status": "ok",
        "risk_class": "normal",
        "risk_score": 7.5,
        "generated_at": "2026-10-19T12:11:02Z",
    }
    body.update(overrides)
    return body


class MockModeTest(unittest.TestCase):
    def setUp(self):
        self.gw = Gateway(make_settings(), clock=clock)

    def test_forecast_is_labelled_mock_and_repeats_last_values(self):
        res = self.gw.forecast(forecast_request())
        self.assertEqual(res.status, "mock")
        self.assertIn("MOCK", res.model_name)
        self.assertEqual(len(res.predictions), 5)  # 300s horizon / 60s step
        self.assertTrue(all(p.heart_rate_bpm == 80.0 for p in res.predictions))
        self.assertEqual(res.generated_at, NOW)

    def test_forecast_timestamps_follow_last_measurement(self):
        req = forecast_request()
        res = self.gw.forecast(req)
        self.assertGreater(res.predictions[0].timestamp, req.measurements[-1].timestamp)

    def test_risk_is_a_labelled_fixture_without_probabilities(self):
        res = self.gw.risk_assessment(risk_request())
        self.assertEqual(res.status, "mock")
        self.assertEqual(res.risk_class, "normal")
        self.assertIsNone(res.class_probabilities)

    def test_mock_risk_class_is_configurable(self):
        gw = Gateway(make_settings(mock_risk_class="critical"), clock=clock)
        res = gw.risk_assessment(risk_request())
        self.assertEqual(res.risk_class, "critical")
        self.assertEqual(res.warnings[0].severity, "critical")

    def test_invalid_forecast_request_is_rejected(self):
        with self.assertRaises(GatewayError) as ctx:
            self.gw.forecast(forecast_request(window_size=30))
        self.assertEqual(ctx.exception.status_code, 422)

    def test_history_is_recorded_per_astronaut_newest_first(self):
        self.gw.risk_assessment(risk_request())
        self.gw.risk_assessment(risk_request())
        self.gw.risk_assessment(risk_request(astronaut_id="other-01"))
        hist = self.gw.prediction_history("demo-astronaut-01", limit=10)
        self.assertEqual(len(hist.items), 2)
        self.assertEqual(self.gw.prediction_history("nobody", 10).items, [])

    def test_history_limit_is_applied(self):
        for _ in range(5):
            self.gw.risk_assessment(risk_request())
        self.assertEqual(len(self.gw.prediction_history("demo-astronaut-01", 3).items), 3)

    def test_model_status_in_mock_mode(self):
        status = self.gw.model_status()
        self.assertEqual(status.mode, "mock")
        self.assertEqual(status.forecast_model.status, "mock")
        self.assertEqual(status.supported_horizons_seconds, [300, 600, 1800])


class ProxyModeTest(unittest.TestCase):
    def test_forecast_is_forwarded_and_validated(self):
        up = FakeUpstream(good_forecast())
        gw = Gateway(proxy_settings(), upstream=up, clock=clock)
        res = gw.forecast(forecast_request())
        self.assertEqual(res.model_version, "1.2.3")
        self.assertEqual(up.calls[0][0], "https://lstm.example/predict")
        self.assertEqual(up.calls[0][1]["astronaut_id"], "demo-astronaut-01")

    def test_risk_is_forwarded_and_stored(self):
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(good_risk()), clock=clock)
        res = gw.risk_assessment(risk_request())
        self.assertEqual(res.risk_score, 7.5)
        self.assertEqual(len(gw.prediction_history("demo-astronaut-01", 10).items), 1)

    def _assert_error(self, gw, call, status, code):
        with self.assertRaises(GatewayError) as ctx:
            call(gw)
        self.assertEqual(ctx.exception.status_code, status)
        self.assertEqual(ctx.exception.code, code)

    def test_timeout_maps_to_504(self):
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(error=UpstreamTimeout("slow")), clock=clock)
        self._assert_error(gw, lambda g: g.forecast(forecast_request()), 504, "upstream_timeout")

    def test_unreachable_maps_to_503(self):
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(error=UpstreamUnavailable("down")), clock=clock)
        self._assert_error(gw, lambda g: g.risk_assessment(risk_request()), 503, "upstream_unavailable")

    def test_upstream_http_error_maps_to_502(self):
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(error=UpstreamHttpError(500)), clock=clock)
        self._assert_error(gw, lambda g: g.forecast(forecast_request()), 502, "upstream_error")

    def test_schema_violation_maps_to_502_and_is_not_papered_over(self):
        bad = good_forecast()
        del bad["model_version"]
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(bad), clock=clock)
        with self.assertRaises(GatewayError) as ctx:
            gw.forecast(forecast_request())
        self.assertEqual(ctx.exception.code, "upstream_schema_error")
        self.assertTrue(ctx.exception.details)

    def test_wrong_astronaut_in_answer_is_rejected(self):
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(good_forecast(astronaut_id="someone-else")), clock=clock)
        self._assert_error(gw, lambda g: g.forecast(forecast_request()), 502, "upstream_mismatch")

    def test_wrong_horizon_in_answer_is_rejected(self):
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(good_forecast(prediction_horizon_seconds=600)), clock=clock)
        self._assert_error(gw, lambda g: g.forecast(forecast_request()), 502, "upstream_mismatch")

    def test_failed_risk_call_is_not_stored_in_history(self):
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(error=UpstreamHttpError(500)), clock=clock)
        with self.assertRaises(GatewayError):
            gw.risk_assessment(risk_request())
        self.assertEqual(gw.prediction_history("demo-astronaut-01", 10).items, [])

    def test_invalid_request_never_reaches_upstream(self):
        up = FakeUpstream(good_forecast())
        gw = Gateway(proxy_settings(), upstream=up, clock=clock)
        with self.assertRaises(GatewayError):
            gw.forecast(forecast_request(window_size=30))
        self.assertEqual(up.calls, [])

    def test_proxy_mode_requires_upstream_client(self):
        with self.assertRaises(ValueError):
            Gateway(proxy_settings(), upstream=None)

    def test_proxy_model_status_does_not_invent_versions(self):
        gw = Gateway(proxy_settings(), upstream=FakeUpstream(good_forecast()), clock=clock)
        status = gw.model_status()
        self.assertEqual(status.mode, "proxy")
        self.assertIsNone(status.forecast_model)
        self.assertIsNone(status.risk_model)


class ConfigTest(unittest.TestCase):
    def test_defaults(self):
        s = load_settings({})
        self.assertEqual(s.mode, "mock")
        self.assertEqual(s.supported_horizons_seconds, (300, 600, 1800))

    def test_proxy_requires_urls(self):
        with self.assertRaises(ConfigError):
            load_settings({"ATHERA_GATEWAY_MODE": "proxy"})

    def test_invalid_mode(self):
        with self.assertRaises(ConfigError):
            load_settings({"ATHERA_GATEWAY_MODE": "yolo"})

    def test_invalid_horizons(self):
        with self.assertRaises(ConfigError):
            load_settings({"ATHERA_SUPPORTED_HORIZONS": "abc"})

    def test_secrets_are_not_in_repr(self):
        s = Settings(upstream_api_key="topsecret")
        self.assertNotIn("topsecret", repr(s))


if __name__ == "__main__":
    unittest.main()
