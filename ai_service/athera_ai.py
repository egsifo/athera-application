"""
athera_ai.py  -  عقل Athera
الملف ده فيه كل حاجة مشتركة بين التدريب والاستخدام:
1) تعريف حالة الخطر (label)
2) بناء الـ features (القراءات + الاتجاه)
3) كلاس AtheraAI اللي التطبيق بيستخدمه
مهم: التدريب والتنبؤ بيستخدموا نفس الدوال بالظبط، عشان مفيش أي اختلاف بينهم.
"""
import numpy as np
import pandas as pd
import joblib

VITALS = ["Heart_Rate", "SBP", "DBP", "SpO2", "Body_Temp",
          "HRV_Stress_Index", "Radiation_Level", "Sleep_Hours",
          "Physical_Activity_Load"]

LAGS = (1, 2, 4, 8, 12)      # بنقيس التغير من كام قراءة فاتت
ROLL = 12                    # متوسط وانحراف آخر 12 قراءة (3 ساعات)
MIN_READINGS = max(LAGS) + 1 # أقل عدد قراءات لازم التطبيق يبعتها = 13

STATUS_NAMES = {0: "SAFE", 1: "EARLY_WARNING", 2: "CRITICAL"}


def prepare(df):
    """يظبط شكل البيانات: يفصل الضغط 120/80 لرقمين، ويتأكد من الأعمدة."""
    df = df.copy()
    if "Blood_Pressure" in df.columns and "SBP" not in df.columns:
        bp = df["Blood_Pressure"].astype(str).str.split("/", expand=True).astype(float)
        df["SBP"], df["DBP"] = bp[0], bp[1]
    missing = [c for c in VITALS if c not in df.columns]
    if missing:
        raise ValueError(f"أعمدة ناقصة: {missing}")
    return df[VITALS].astype(float).reset_index(drop=True)


def label_risk(v):
    """قاعدة تعريف الخطر (حدود طبية تقريبية، غيّرها براحتك):
    2 = Critical ، 1 = Early Warning ، 0 = Safe"""
    crit = (v.Heart_Rate > 110) | (v.SpO2 < 94) | (v.Body_Temp > 38.0) | (v.SBP > 140)
    warn = ((v.Heart_Rate > 95) | (v.SpO2 < 95.5) | (v.Body_Temp > 37.6) |
            (v.SBP > 130) | (v.HRV_Stress_Index > 75) | (v.Sleep_Hours < 5))
    return pd.Series(np.where(crit, 2, np.where(warn, 1, 0)), index=v.index)


def build_features(v):
    """القراءات الحالية + التغير + المتوسط + الانحراف + الحالة الحالية."""
    f = v.copy()
    for c in VITALS:
        for l in LAGS:
            f[f"{c}_d{l}"] = v[c].diff(l)
        f[f"{c}_m{ROLL}"] = v[c].rolling(ROLL).mean()
        f[f"{c}_s{ROLL}"] = v[c].rolling(ROLL).std()
    f["now_status"] = label_risk(v)
    return f


class AtheraAI:
    def __init__(self, path="athera_model.joblib"):
        b = joblib.load(path)
        self.model = b["model"]
        self.feature_names = b["feature_names"]
        self.horizon = b["horizon"]
        self.minutes_ahead = b["horizon"] * 15

    def predict(self, history):
        """history = آخر 13 قراءة على الأقل (DataFrame أو list of dicts)،
        القراءة كل 15 دقيقة، الأقدم الأول والأحدث الأخير."""
        df = history if isinstance(history, pd.DataFrame) else pd.DataFrame(history)
        v = prepare(df)
        if len(v) < MIN_READINGS:
            raise ValueError(f"محتاج {MIN_READINGS} قراءة على الأقل، وصلني {len(v)}")
        v = v.tail(60)  # مش محتاجين أكتر من كده
        row = build_features(v).iloc[[-1]][self.feature_names]
        proba = self.model.predict_proba(row)[0]
        full = {int(c): float(p) for c, p in zip(self.model.classes_, proba)}
        p = [full.get(0, 0.0), full.get(1, 0.0), full.get(2, 0.0)]
        predicted = int(np.argmax(p))
        risk_score = round(min(100.0, p[1] * 50 + p[2] * 100), 1)
        last = v.iloc[-1]
        now = int(label_risk(v).iloc[-1])
        return {
            "current_status": STATUS_NAMES[now],
            "predicted_status": STATUS_NAMES[predicted],
            "minutes_ahead": self.minutes_ahead,
            "risk_score": risk_score,
            "probabilities": {"safe": round(p[0], 3),
                              "early_warning": round(p[1], 3),
                              "critical": round(p[2], 3)},
            "reasons": self._reasons(v),
            "alert": self._alert(predicted, now, risk_score),
        }

    def _reasons(self, v):
        """أسباب بسيطة يقدر يفهمها المستخدم: القراءات الخارجة عن الطبيعي + الاتجاهات الطالعة."""
        last, out = v.iloc[-1], []
        if last.Heart_Rate > 95:   out.append(f"Heart rate high ({last.Heart_Rate:.0f} bpm)")
        if last.SpO2 < 95.5:       out.append(f"SpO2 low ({last.SpO2:.1f}%)")
        if last.Body_Temp > 37.6:  out.append(f"Body temp high ({last.Body_Temp:.2f} C)")
        if last.SBP > 130:         out.append(f"Systolic BP high ({last.SBP:.0f})")
        if last.HRV_Stress_Index > 75: out.append("Stress index very high")
        if last.Sleep_Hours < 5:   out.append(f"Sleep low ({last.Sleep_Hours:.1f} h)")
        # اتجاهات: التغير في آخر ساعة (4 قراءات)
        d = v.iloc[-1] - v.iloc[-5]
        if d.Heart_Rate > 12:      out.append("Heart rate rising fast")
        if d.SpO2 < -1.0:          out.append("SpO2 dropping")
        if d.Body_Temp > 0.4:      out.append("Temperature rising")
        return out

    def _alert(self, predicted, now, score):
        if now == 2:
            return "CRITICAL NOW: send SOS and alert the crew."
        if predicted == 2:
            return f"Warning: high chance of critical state within {self.minutes_ahead} min. Reduce exertion and return to base."
        if predicted == 1:
            return f"Early warning: vitals are drifting (risk {score}%). Rest and recheck."
        if now == 1:
            return "Vitals are outside normal range but expected to recover. Keep monitoring."
        return "All vitals normal."
