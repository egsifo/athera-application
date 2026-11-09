"""
make_backtest.py - regenerate the app's bundled model report card.

    python make_backtest.py [out.json]     # default: ../assets/ai/backtest.json

For a new dataset use retrain.py, which trains and then calls the same code.
"""
import json
import sys
from pathlib import Path

from backtest import build_backtest

HERE = Path(__file__).parent
out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parent / "assets" / "ai" / "backtest.json"
r = build_backtest(
    HERE / "athera_synthetic_10col.csv",
    HERE / "athera_model.joblib",
    out,
    "athera_synthetic_10col.csv (SIMULATED data, not NASA data)",
    "simulated",
)
print(f"wrote {out} ({out.stat().st_size / 1024:.0f} KB)")
print("accuracy", r["accuracy"], "baseline", r["baseline_accuracy"])
print("episodes", {k: v for k, v in r["critical_episodes"].items() if k != "list"})
