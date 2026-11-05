import unittest

from pydantic import ValidationError

from app.schemas import ForecastRequest, ForecastResponse, RiskRequest, RiskResponse
from tests.helpers import forecast_payload, risk_payload


class ForecastRequestSchemaTest(unittest.TestCase):
    def test_valid_payload_parses(self):
        req = ForecastRequest.model_validate(forecast_payload())
        self.assertEqual(req.window_size, 12)
        self.assertEqual(len(req.measurements), 12)

    def test_unknown_field_is_rejected(self):
        with self.assertRaises(ValidationError):
            ForecastRequest.model_validate(forecast_payload(surprise=1))

    def test_naive_timestamp_is_rejected(self):
        payload = forecast_payload()
        payload["measurements"][0]["timestamp"] = "2026-10-19T12:00:00"
        with self.assertRaises(ValidationError):
            ForecastRequest.model_validate(payload)

    def test_implausible_value_is_rejected(self):
        payload = forecast_payload()
        payload["measurements"][3]["heart_rate_bpm"] = 900
        with self.assertRaises(ValidationError):
            ForecastRequest.model_validate(payload)

    def test_null_vitals_are_allowed(self):
        payload = forecast_payload()
        payload["measurements"][2]["spo2_percent"] = None
        ForecastRequest.model_validate(payload)

    def test_bad_astronaut_id_is_rejected(self):
        with self.assertRaises(ValidationError):
            ForecastRequest.model_validate(forecast_payload(astronaut_id="bad id!"))


def _forecast_response(**overrides):
    body = {
        "astronaut_id": "demo-astronaut-01",
        "model_name": "LSTM",
        "model_version": "v1",
        "status": "ok",
        "prediction_horizon_seconds": 120,
        "step_seconds": 60,
        "predictions": [
            {"timestamp": "2026-10-19T12:12:00Z", "heart_rate_bpm": 90},
            {"timestamp": "2026-10-19T12:13:00Z", "heart_rate_bpm": 91},
        ],
        "generated_at": "2026-10-19T12:11:01Z",
    }
    body.update(overrides)
    return body


class ForecastResponseSchemaTest(unittest.TestCase):
    def test_valid_response(self):
        ForecastResponse.model_validate(_forecast_response())

    def test_extra_fields_are_ignored(self):
        ForecastResponse.model_validate(_forecast_response(brand_new_field="ok"))

    def test_missing_required_field_fails(self):
        body = _forecast_response()
        del body["model_version"]
        with self.assertRaises(ValidationError):
            ForecastResponse.model_validate(body)

    def test_non_increasing_timestamps_fail(self):
        body = _forecast_response()
        body["predictions"][1]["timestamp"] = "2026-10-19T12:12:00Z"
        with self.assertRaises(ValidationError):
            ForecastResponse.model_validate(body)


def _risk_response(**overrides):
    body = {
        "astronaut_id": "demo-astronaut-01",
        "model_name": "XGBoost",
        "model_version": "v1",
        "status": "ok",
        "risk_class": "early_warning",
        "risk_score": None,
        "class_probabilities": None,
        "generated_at": "2026-10-19T12:00:02Z",
    }
    body.update(overrides)
    return body


class RiskSchemaTest(unittest.TestCase):
    def test_request_parses(self):
        req = RiskRequest.model_validate(risk_payload())
        self.assertIsNone(req.features["spo2_min_15m"])

    def test_null_score_and_probabilities_are_valid(self):
        res = RiskResponse.model_validate(_risk_response())
        self.assertIsNone(res.risk_score)
        self.assertIsNone(res.class_probabilities)

    def test_unknown_risk_class_fails(self):
        with self.assertRaises(ValidationError):
            RiskResponse.model_validate(_risk_response(risk_class="catastrophe"))

    def test_score_out_of_range_fails(self):
        with self.assertRaises(ValidationError):
            RiskResponse.model_validate(_risk_response(risk_score=140))

    def test_probabilities_must_sum_to_one(self):
        with self.assertRaises(ValidationError):
            RiskResponse.model_validate(
                _risk_response(class_probabilities={"normal": 0.2, "early_warning": 0.2})
            )

    def test_valid_probabilities_pass(self):
        res = RiskResponse.model_validate(
            _risk_response(class_probabilities={"normal": 0.6, "early_warning": 0.3, "critical": 0.1})
        )
        self.assertAlmostEqual(sum(res.class_probabilities.values()), 1.0)


if __name__ == "__main__":
    unittest.main()
