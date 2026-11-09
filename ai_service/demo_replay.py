"""
demo_replay.py  -  محاكي البث المباشر (Replay Engine)
بيقرا الـ CSV قراءة ورا قراءة كأن الرائد لابس البدلة، وبيطبع تنبيهات Athera.
تشغيل:  python demo_replay.py athera_synthetic_10col.csv 2800 3000
"""
import sys, pandas as pd
from athera_ai import AtheraAI, prepare, MIN_READINGS, label_risk

csv = sys.argv[1] if len(sys.argv) > 1 else "athera_synthetic_10col.csv"
start = int(sys.argv[2]) if len(sys.argv) > 2 else 0
end = int(sys.argv[3]) if len(sys.argv) > 3 else 300

ai = AtheraAI("athera_model.joblib")
raw = pd.read_csv(csv)
for t in range(max(start, MIN_READINGS), min(end, len(raw))):
    out = ai.predict(raw.iloc[:t])            # الـ AI مش بيشوف غير الماضي
    if out["predicted_status"] != "SAFE" or out["current_status"] != "SAFE":
        print(f"[{raw.Timestamp.iloc[t-1]}] now={out['current_status']:<13} "
              f"next{out['minutes_ahead']}min={out['predicted_status']:<13} risk={out['risk_score']:>5}%  {out['alert']}")
