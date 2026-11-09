"""
train.py  -  تدريب موديل Athera
تشغيل:  python train.py athera_synthetic_10col.csv
"""
import sys, json
import numpy as np, pandas as pd, joblib
from sklearn.ensemble import HistGradientBoostingClassifier   # أو XGBoost (شوف README)
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score
from sklearn.model_selection import TimeSeriesSplit
from athera_ai import prepare, label_risk, build_features

CSV = sys.argv[1] if len(sys.argv) > 1 else "athera_synthetic_10col.csv"
HORIZON = 8     # 8 قراءات × 15 دقيقة = ساعتين قدّام (غيّره لـ 4 = ساعة)


def new_model():
    return HistGradientBoostingClassifier(
        max_iter=150, learning_rate=0.05, max_depth=4, min_samples_leaf=40,
        l2_regularization=1.0, class_weight="balanced", random_state=0)

# ---- 1) قراءة الداتا وتجهيزها
raw = pd.read_csv(CSV)
v = prepare(raw)

# ---- 2) الـ features والهدف (أسوأ حالة في الـ HORIZON قراءة الجاية)
f = build_features(v)
now = f["now_status"]
future = pd.concat([now.shift(-k) for k in range(1, HORIZON + 1)], axis=1).max(axis=1)
f["target"] = future
f = f.dropna()
X, y = f.drop(columns="target"), f["target"].astype(int)
print("حجم الداتا:", len(X), "| توزيع الهدف:", y.value_counts().sort_index().to_dict())

# ---- 3) التقسيم بالزمن: أول 85% تدريب، آخر 15% اختبار (مش عشوائي)
i = int(len(X) * 0.85)
model = new_model().fit(X[:i], y[:i])
pred = model.predict(X[i:])
acc = accuracy_score(y[i:], pred)
base = accuracy_score(y[i:], X["now_status"][i:])   # "خمّن إن المستقبل زي دلوقتي"
print(f"\nالدقة على الاختبار: {acc*100:.1f}%   (خط الأساس 'المستقبل = الحاضر': {base*100:.1f}%)")
print(classification_report(y[i:], pred, target_names=["Safe", "Early", "Critical"], digits=3))
print("Confusion matrix (صفوف=الحقيقي، أعمدة=المتوقع):\n", confusion_matrix(y[i:], pred))

# ---- 4) تأكيد بـ Cross-Validation زمني (5 مرات)
scores = []
for tr, te in TimeSeriesSplit(n_splits=5).split(X):
    m = new_model().fit(X.iloc[tr], y.iloc[tr])
    scores.append(accuracy_score(y.iloc[te], m.predict(X.iloc[te])))
print("\nCross-validation accuracy:", [round(s, 3) for s in scores], "| المتوسط", round(float(np.mean(scores)), 3))

# ---- 5) حفظ الموديل (اللي اتدرّب على أول 85% بس، عشان أي اختبار على آخر 15% يفضل نضيف وصادق)
final = model
joblib.dump({"model": final, "feature_names": list(X.columns), "horizon": HORIZON}, "athera_model.joblib")
json.dump({"holdout_accuracy": round(acc, 4), "baseline_accuracy": round(base, 4),
           "cv_scores": [round(s, 4) for s in scores], "horizon_minutes": HORIZON * 15},
          open("metrics.json", "w"), indent=2)
print("\nتم الحفظ: athera_model.joblib + metrics.json")
