"""
backtest.py - honest out-of-sample evaluation of an ATHERA model.

Replays the model over the held-out last 15% of a dataset (the same split the
training pipeline uses) and writes a compact JSON the mobile app bundles as an
asset. Every number is computed from real model output; nothing is typed in.
"""
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from athera_ai import STATUS_NAMES, build_features, prepare

STEP = 15


def build_backtest(csv_path, model_path, out_path, source_label, data_kind):
    assert data_kind in ("simulated", "real"), data_kind
    """Compute the report, write it to out_path, and return it as a dict."""
    out_path = Path(out_path)
    bundle = joblib.load(model_path)
    model, names, H = bundle["model"], bundle["feature_names"], bundle["horizon"]
    raw = pd.read_csv(csv_path)
    v = prepare(raw)
    f = build_features(v)
    now = f["now_status"]
    f["target"] = pd.concat([now.shift(-k) for k in range(1, H + 1)], axis=1).max(axis=1)
    ts = raw["Timestamp"]
    f = f.dropna()
    split = int(len(f) * 0.85)
    hold = f.iloc[split:]
    proba = model.predict_proba(hold[names])
    classes = list(model.classes_)
    pred = np.array([classes[k] for k in proba.argmax(1)])
    actual = hold["target"].astype(int).to_numpy()
    cur = hold["now_status"].astype(int).to_numpy()
    risk = np.round(np.minimum(100.0, proba[:, classes.index(1)] * 50 + proba[:, classes.index(2)] * 100), 1)

    def rate(num, den):
        return round(float(num) / float(den), 4) if den else None

    conf = [[int(((actual == a) & (pred == p)).sum()) for p in range(3)] for a in range(3)]
    per_class = {}
    for c, name in STATUS_NAMES.items():
        tp = conf[c][c]
        per_class[name] = {
            "support": int(sum(conf[c])),
            "recall": rate(tp, sum(conf[c])),
            "precision": rate(tp, sum(conf[r][c] for r in range(3))),
        }

    # Episodes: a new CRITICAL episode starts when the *current* status becomes 2
    # (after at least 4 non-critical readings). Lead time = how long before onset the
    # model first predicted EARLY_WARNING-or-worse / CRITICAL (looking back <= horizon).

    episodes = []
    idx = np.where(cur == 2)[0]
    last_end = -10
    for i in idx:
        if i - last_end > 4:
            lo = max(0, i - H)
            window = range(lo, i)
            first_any = next((j for j in window if pred[j] >= 1), None)
            first_crit = next((j for j in window if pred[j] == 2), None)
            episodes.append({
                "onset": str(ts.iloc[hold.index[i]]),
                "lead_any_min": None if first_any is None else int((i - first_any) * STEP),
                "lead_critical_min": None if first_crit is None else int((i - first_crit) * STEP),
            })
        last_end = i
    ep_n = len(episodes)
    ep_any = sum(e["lead_any_min"] is not None for e in episodes)
    ep_crit = sum(e["lead_critical_min"] is not None for e in episodes)
    leads = [e["lead_any_min"] for e in episodes if e["lead_any_min"] is not None]

    # Of all CRITICAL warnings the model raised, how many were followed by a real critical
    # state within the horizon (precision) - the false-alarm side of the story.
    crit_alarms = int((pred == 2).sum())
    crit_true = int(((pred == 2) & (actual == 2)).sum())

    rows = hold.index
    series = {
        "t": [str(ts.iloc[i]) for i in rows],
        "now": [int(x) for x in cur],
        "pred": [int(x) for x in pred],
        "actual": [int(x) for x in actual],
        "risk": [float(x) for x in risk],
        "hr": [round(float(v.Heart_Rate.iloc[i]), 1) for i in rows],
        "spo2": [round(float(v.SpO2.iloc[i]), 1) for i in rows],
        "temp": [round(float(v.Body_Temp.iloc[i]), 2) for i in rows],
        "sbp": [round(float(v.SBP.iloc[i]), 0) for i in rows],
    }
    baseline = float((cur == actual).mean())
    report = {
        "generated_from": source_label,
        "data_kind": data_kind,
        "horizon_minutes": H * STEP,
        "holdout_rows": int(len(hold)),
        "holdout_period": [series["t"][0], series["t"][-1]],
        "accuracy": round(float((pred == actual).mean()), 4),
        "baseline_accuracy": round(baseline, 4),
        "confusion": conf,
        "classes": [STATUS_NAMES[i] for i in range(3)],
        "per_class": per_class,
        "critical_episodes": {
            "count": ep_n,
            "warned_any": ep_any,
            "warned_critical": ep_crit,
            "median_lead_any_min": float(np.median(leads)) if leads else None,
            "critical_alarms": crit_alarms,
            "critical_alarms_confirmed": crit_true,
            "list": episodes,
        },
        "series": series,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, separators=(",", ":")))
    return report
