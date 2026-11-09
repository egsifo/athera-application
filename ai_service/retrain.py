"""
retrain.py - swap the training data, rebuild everything.

    python retrain.py --data my_data.csv --data-kind real
    python retrain.py --data my_data.csv --data-kind simulated --out-dir build/

Steps: validate the CSV (data_check.py) -> temporal split (first 85% train, last
15% test) -> train -> time-series cross-validation -> save model + metrics.json
-> write the app's report card (backtest.json). Nothing is written when
validation fails. --data-kind is required so the app never calls simulated data
real (or the other way round).
"""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
import sklearn
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import TimeSeriesSplit

from athera_ai import build_features, prepare
from backtest import build_backtest
from data_check import validate_dataset

HERE = Path(__file__).parent
HORIZON = 8  # readings ahead (8 x 15 min = 120 min)


def new_model():
    return HistGradientBoostingClassifier(
        max_iter=150, learning_rate=0.05, max_depth=4, min_samples_leaf=40,
        l2_regularization=1.0, class_weight="balanced", random_state=0)


def make_xy(raw, horizon=HORIZON):
    v = prepare(raw)
    f = build_features(v)
    now = f["now_status"]
    f["target"] = pd.concat([now.shift(-k) for k in range(1, horizon + 1)], axis=1).max(axis=1)
    f = f.dropna()
    return f.drop(columns="target"), f["target"].astype(int)


def run(data, data_kind, out_dir, backtest_out, horizon=HORIZON, label=None):
    raw = pd.read_csv(data)
    errors, warnings = validate_dataset(raw)
    for w in warnings:
        print("warning:", w)
    if errors:
        print("DATA REJECTED, nothing was written:")
        for e in errors:
            print(" -", e)
        return 2

    X, y = make_xy(raw, horizon)
    split = int(len(X) * 0.85)
    model = new_model().fit(X[:split], y[:split])
    pred = model.predict(X[split:])
    acc = accuracy_score(y[split:], pred)
    base = accuracy_score(y[split:], X["now_status"][split:])
    print(f"hold-out accuracy {acc * 100:.1f}% (baseline 'future = now' {base * 100:.1f}%)")

    cv = []
    for tr, te in TimeSeriesSplit(n_splits=5).split(X):
        m = new_model().fit(X.iloc[tr], y.iloc[tr])
        cv.append(round(float(accuracy_score(y.iloc[te], m.predict(X.iloc[te]))), 4))
    print("cross-validation:", cv)

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    model_path = out_dir / "athera_model.joblib"
    # The saved model is the one trained on the first 85% only, so the report card
    # (computed on the last 15%) stays an honest out-of-sample test.
    joblib.dump({"model": model, "feature_names": list(X.columns), "horizon": horizon}, model_path)
    label = label or f"{Path(data).name} ({'REAL data supplied by the team' if data_kind == 'real' else 'SIMULATED data'})"
    metrics = {
        "holdout_accuracy": round(float(acc), 4),
        "baseline_accuracy": round(float(base), 4),
        "cv_scores": cv,
        "horizon_minutes": horizon * 15,
        "trained_on": label,
        "data_kind": data_kind,
        "rows": int(len(raw)),
        "trained_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sklearn_version": sklearn.__version__,
    }
    (out_dir / "metrics.json").write_text(json.dumps(metrics, indent=2))
    report = build_backtest(data, model_path, backtest_out, label, data_kind)
    print("report card written:", backtest_out)
    n = report["critical_episodes"]["count"]
    if n < 20:
        print(f"note: only {n} critical episodes in the hold-out; recall is statistically weak.")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", required=True, help="CSV with the 9 vitals + Timestamp, one row per 15 minutes")
    ap.add_argument("--data-kind", required=True, choices=["simulated", "real"])
    ap.add_argument("--out-dir", default=str(HERE), help="where athera_model.joblib and metrics.json go")
    ap.add_argument("--report-out", default=str(HERE.parent / "assets" / "ai" / "backtest.json"))
    ap.add_argument("--horizon", type=int, default=HORIZON, help="readings ahead to predict (default 8 = 120 min)")
    ap.add_argument("--label", default=None, help="text shown in the app for where the data came from")
    a = ap.parse_args(argv)
    return run(a.data, a.data_kind, a.out_dir, a.report_out, a.horizon, a.label)


if __name__ == "__main__":
    sys.exit(main())
