import unittest

from app.errors import GatewayError
from app.validation import validate_forecast_request
from tests.helpers import forecast_payload, forecast_request, make_settings, measurements


class SemanticValidationTest(unittest.TestCase):
    def setUp(self):
        self.settings = make_settings()

    def _problems(self, req) -> list[str]:
        with self.assertRaises(GatewayError) as ctx:
            validate_forecast_request(req, self.settings)
        self.assertEqual(ctx.exception.status_code, 422)
        return ctx.exception.details

    def test_valid_request_returns_completeness(self):
        completeness = validate_forecast_request(forecast_request(), self.settings)
        self.assertEqual(completeness["heart_rate_bpm"], 1.0)

    def test_window_size_must_match_sample_count(self):
        problems = self._problems(forecast_request(window_size=20))
        self.assertTrue(any("window_size is 20" in p for p in problems))

    def test_unsupported_horizon(self):
        problems = self._problems(forecast_request(prediction_horizon_seconds=777))
        self.assertTrue(any("prediction_horizon_seconds must be one of" in p for p in problems))

    def test_window_below_minimum(self):
        req = forecast_request(window_size=5, measurements=measurements(5))
        problems = self._problems(req)
        self.assertTrue(any("window_size must be between" in p for p in problems))

    def test_non_increasing_timestamps(self):
        payload = forecast_payload()
        payload["measurements"][4]["timestamp"] = payload["measurements"][3]["timestamp"]
        from app.schemas import ForecastRequest

        problems = self._problems(ForecastRequest.model_validate(payload))
        self.assertTrue(any("strictly increasing" in p for p in problems))

    def test_irregular_sampling_is_reported(self):
        payload = forecast_payload()
        payload["measurements"][6]["timestamp"] = "2026-10-19T12:06:30Z"  # +30s drift
        from app.schemas import ForecastRequest

        problems = self._problems(ForecastRequest.model_validate(payload))
        self.assertTrue(any("expected 60s" in p for p in problems))

    def test_insufficient_completeness(self):
        payload = forecast_payload()
        for m in payload["measurements"]:
            m["heart_rate_bpm"] = None
            m["spo2_percent"] = None
            m["temperature_celsius"] = None
            m["respiratory_rate_bpm"] = None
        from app.schemas import ForecastRequest

        problems = self._problems(ForecastRequest.model_validate(payload))
        self.assertTrue(any("no core vital" in p for p in problems))

    def test_one_missing_vital_is_acceptable(self):
        req = forecast_request(measurements=measurements(12, spo2=None))
        completeness = validate_forecast_request(req, self.settings)
        self.assertEqual(completeness["spo2_percent"], 0.0)

    def test_multiple_problems_are_all_reported(self):
        problems = self._problems(forecast_request(window_size=20, prediction_horizon_seconds=777))
        self.assertGreaterEqual(len(problems), 2)


if __name__ == "__main__":
    unittest.main()
