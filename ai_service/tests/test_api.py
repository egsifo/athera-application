import pytest

fastapi = pytest.importorskip("fastapi")
from fastapi.testclient import TestClient  # noqa: E402

import api  # noqa: E402

client = TestClient(api.app)


def r(**kw):
    d = dict(Heart_Rate=72, SBP=118, DBP=76, SpO2=97.4, Body_Temp=37.0, HRV_Stress_Index=40,
             Radiation_Level=22, Sleep_Hours=6.5, Physical_Activity_Load=1.5)
    d.update(kw)
    return d


def test_health_contract():
    j = client.get("/").json()
    assert j == {"status": "ok", "predicts_minutes_ahead": 120}


def test_predict_ok():
    res = client.post("/predict", json={"history": [r() for _ in range(13)]})
    assert res.status_code == 200
    assert res.json()["predicted_status"] in {"SAFE", "EARLY_WARNING", "CRITICAL"}


def test_predict_too_few():
    res = client.post("/predict", json={"history": [r() for _ in range(12)]})
    assert res.status_code == 400


def test_predict_missing_field_is_422():
    bad = r()
    del bad["SpO2"]
    assert client.post("/predict", json={"history": [bad] * 13}).status_code == 422


def test_predict_implausible_is_422():
    assert client.post("/predict", json={"history": [r(SpO2=970)] * 13}).status_code == 422


def test_sbp_must_exceed_dbp():
    assert client.post("/predict", json={"history": [r(SBP=70, DBP=90)] * 13}).status_code == 400


def test_model_info_reports_training_source():
    j = client.get("/model-info").json()
    assert j["predicts_minutes_ahead"] == 120
    assert "disclaimer" in j
