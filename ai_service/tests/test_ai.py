import json
from pathlib import Path

import pandas as pd
import pytest

from athera_ai import MIN_READINGS, VITALS, AtheraAI, label_risk
from data_check import validate_dataset

HERE = Path(__file__).resolve().parent.parent
CSV = HERE / "athera_synthetic_10col.csv"


def reading(**kw):
    r = dict(Heart_Rate=72, SBP=118, DBP=76, SpO2=97.4, Body_Temp=37.0, HRV_Stress_Index=40,
             Radiation_Level=22, Sleep_Hours=6.5, Physical_Activity_Load=1.5)
    r.update(kw)
    return r


@pytest.fixture(scope="module")
def ai():
    return AtheraAI(str(HERE / "athera_model.joblib"))


def test_calm_history_is_safe(ai):
    out = ai.predict([reading() for _ in range(MIN_READINGS)])
    assert out["current_status"] == "SAFE"
    assert out["minutes_ahead"] == 120
    assert 0 <= out["risk_score"] <= 100
    assert abs(sum(out["probabilities"].values()) - 1) < 0.01


def test_contract_keys(ai):
    out = ai.predict([reading() for _ in range(MIN_READINGS)])
    assert set(out) == {"current_status", "predicted_status", "minutes_ahead", "risk_score",
                        "probabilities", "reasons", "alert"}


def test_current_critical_is_reported(ai):
    hist = [reading() for _ in range(MIN_READINGS - 1)] + [reading(Heart_Rate=130, SpO2=92)]
    out = ai.predict(hist)
    assert out["current_status"] == "CRITICAL"
    assert out["alert"].startswith("CRITICAL NOW")


def test_too_few_readings_rejected(ai):
    with pytest.raises(ValueError):
        ai.predict([reading() for _ in range(MIN_READINGS - 1)])


def test_label_rule_thresholds():
    v = pd.DataFrame([reading(), reading(Heart_Rate=100), reading(Heart_Rate=115)])
    assert list(label_risk(v)) == [0, 1, 2]


def test_metrics_file_matches_model():
    m = json.loads((HERE / "metrics.json").read_text())
    assert m["horizon_minutes"] == 120
    assert m["holdout_accuracy"] > m["baseline_accuracy"]


def test_shipped_dataset_is_valid():
    errors, _ = validate_dataset(pd.read_csv(CSV))
    assert errors == []


def _good(n=700):
    ts = pd.date_range("2030-01-01", periods=n, freq="15min")
    df = pd.DataFrame({"Timestamp": ts.astype(str)})
    for k, v in reading().items():
        df[k] = v + (pd.Series(range(n)) % 7) * 0.1
    return df


def test_validator_accepts_clean_data():
    assert validate_dataset(_good())[0] == []


def test_validator_rejects_missing_column():
    errs, _ = validate_dataset(_good().drop(columns=["SpO2"]))
    assert any("SpO2" in e for e in errs)


def test_validator_rejects_gap():
    df = _good().drop(index=[100, 101]).reset_index(drop=True)
    errs, _ = validate_dataset(df)
    assert any("15 minutes" in e for e in errs)


def test_validator_rejects_implausible_values_and_nan():
    df = _good()
    df.loc[5, "SpO2"] = 970  # unit mix-up
    df.loc[6, "Heart_Rate"] = float("nan")
    errs, _ = validate_dataset(df)
    assert any("SpO2" in e for e in errs) and any("Heart_Rate" in e for e in errs)


def test_validator_rejects_too_short():
    errs, _ = validate_dataset(_good(100))
    assert any("rows" in e for e in errs)


def test_retrain_refuses_bad_data(tmp_path):
    import retrain
    bad = _good().drop(columns=["SpO2"])
    p = tmp_path / "bad.csv"
    bad.to_csv(p, index=False)
    code = retrain.run(str(p), "real", tmp_path / "out", tmp_path / "bt.json")
    assert code == 2
    assert not (tmp_path / "out" / "athera_model.joblib").exists()


def test_retrain_roundtrip_on_shipped_data(tmp_path):
    import retrain
    code = retrain.run(str(CSV), "simulated", tmp_path / "out", tmp_path / "bt.json")
    assert code == 0
    report = json.loads((tmp_path / "bt.json").read_text())
    assert report["data_kind"] == "simulated"
    assert len(report["confusion"]) == 3
    m = json.loads((tmp_path / "out" / "metrics.json").read_text())
    assert m["data_kind"] == "simulated" and m["rows"] == 8640
    # The new model must load and predict.
    out = AtheraAI(str(tmp_path / "out" / "athera_model.joblib")).predict([reading() for _ in range(MIN_READINGS)])
    assert out["minutes_ahead"] == 120
