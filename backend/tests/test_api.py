"""HTTP-level tests. Require fastapi + httpx (see requirements-dev.txt)."""
import unittest

try:  # pragma: no cover - depends on the environment
    from fastapi.testclient import TestClient

    from app.main import create_app

    HAVE_FASTAPI = True
except Exception:  # noqa: BLE001
    HAVE_FASTAPI = False

from tests.helpers import forecast_payload, make_settings, risk_payload


@unittest.skipUnless(HAVE_FASTAPI, "fastapi/httpx not installed")
class ApiTest(unittest.TestCase):
    def client(self, **settings):
        return TestClient(create_app(make_settings(**settings)))

    def test_health(self):
        res = self.client().get("/health")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["mode"], "mock")

    def test_forecast_roundtrip(self):
        res = self.client().post("/api/v1/forecast", json=forecast_payload())
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertEqual(body["status"], "mock")
        self.assertEqual(len(body["predictions"]), 5)

    def test_schema_error_uses_error_envelope(self):
        res = self.client().post("/api/v1/forecast", json={"astronaut_id": "x"})
        self.assertEqual(res.status_code, 422)
        self.assertEqual(res.json()["error"]["code"], "validation_error")

    def test_semantic_error_uses_error_envelope(self):
        res = self.client().post("/api/v1/forecast", json=forecast_payload(window_size=30))
        self.assertEqual(res.status_code, 422)
        self.assertEqual(res.json()["error"]["code"], "invalid_forecast_request")

    def test_risk_then_history(self):
        c = self.client()
        self.assertEqual(c.post("/api/v1/risk-assessment", json=risk_payload()).status_code, 200)
        res = c.get("/api/v1/predictions", params={"astronaut_id": "demo-astronaut-01"})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(len(res.json()["items"]), 1)

    def test_api_key_is_enforced_when_configured(self):
        c = self.client(gateway_api_key="s3cret")
        self.assertEqual(c.get("/api/v1/model-status").status_code, 401)
        ok = c.get("/api/v1/model-status", headers={"X-API-Key": "s3cret"})
        self.assertEqual(ok.status_code, 200)
        self.assertEqual(c.get("/health").status_code, 200)  # health stays open

    def test_simulated_error_header_in_mock_mode(self):
        res = self.client().post(
            "/api/v1/forecast", json=forecast_payload(), headers={"X-Mock-Error": "503"}
        )
        self.assertEqual(res.status_code, 503)
        self.assertEqual(res.json()["error"]["code"], "mock_simulated_error")


if __name__ == "__main__":
    unittest.main()
