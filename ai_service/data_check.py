"""
data_check.py - validate a training CSV before it is allowed to replace the model.

A bad file must fail loudly here, never silently produce a model. Returns
(errors, warnings); training refuses to run when there are errors.
"""
import numpy as np
import pandas as pd

from athera_ai import VITALS

STEP_MIN = 15
MIN_ROWS = 600  # ~6 days at 15 min; fewer than this cannot give a meaningful hold-out

# Physically implausible bounds (sensor faults / unit mix-ups), not clinical limits.
HARD_RANGES = {
    "Heart_Rate": (20, 250),
    "SBP": (50, 280),
    "DBP": (25, 180),
    "SpO2": (50, 100),
    "Body_Temp": (30, 44),
    "HRV_Stress_Index": (0, 1000),
    "Radiation_Level": (0, 100000),
    "Sleep_Hours": (0, 24),
    "Physical_Activity_Load": (0, 100),
}


def validate_dataset(raw: pd.DataFrame):
    errors, warnings = [], []
    cols = set(raw.columns)
    if "Timestamp" not in cols:
        errors.append("missing column 'Timestamp' (needed to check the 15-minute cadence and to report dates)")
    has_bp = "Blood_Pressure" in cols
    need = [c for c in VITALS if c not in ("SBP", "DBP")] + ([] if has_bp else ["SBP", "DBP"])
    missing = [c for c in need if c not in cols]
    if missing:
        errors.append(f"missing columns: {missing}")
    if errors:
        return errors, warnings

    if len(raw) < MIN_ROWS:
        errors.append(f"only {len(raw)} rows; need at least {MIN_ROWS} (about 6 days at 15 min)")

    ts = pd.to_datetime(raw["Timestamp"], errors="coerce")
    if ts.isna().any():
        errors.append(f"{int(ts.isna().sum())} Timestamp values could not be parsed")
    else:
        d = ts.diff().dropna()
        if (d <= pd.Timedelta(0)).any():
            errors.append("Timestamp must be strictly increasing (oldest first, no duplicates)")
        off = d[(d != pd.Timedelta(minutes=STEP_MIN)) & (d > pd.Timedelta(0))]
        if len(off):
            errors.append(
                f"{len(off)} gaps/irregular steps: every reading must be exactly {STEP_MIN} minutes after the previous one "
                f"(first problem at row {int(off.index[0])}, step {off.iloc[0]}). Resample or split the file."
            )

    try:
        if has_bp and "SBP" not in cols:
            bp = raw["Blood_Pressure"].astype(str).str.split("/", expand=True)
            if bp.shape[1] != 2:
                raise ValueError("Blood_Pressure must look like 120/80")
            frame = raw.assign(SBP=pd.to_numeric(bp[0], errors="coerce"), DBP=pd.to_numeric(bp[1], errors="coerce"))
        else:
            frame = raw
        vit = frame[VITALS].apply(pd.to_numeric, errors="coerce")
    except Exception as e:  # noqa: BLE001 - report any parse failure as a data error
        errors.append(f"could not read vital columns: {e}")
        return errors, warnings

    for c in VITALS:
        bad = int(vit[c].isna().sum())
        if bad:
            errors.append(f"{c}: {bad} missing or non-numeric values (fill or remove them first)")
            continue
        lo, hi = HARD_RANGES[c]
        out = int(((vit[c] < lo) | (vit[c] > hi)).sum())
        if out:
            errors.append(f"{c}: {out} values outside the physically plausible range {lo}..{hi} (unit mix-up or sensor fault?)")
        if vit[c].nunique() <= 1:
            warnings.append(f"{c} never changes; it carries no information")
    if not errors:
        if (vit["SBP"] <= vit["DBP"]).any():
            errors.append("SBP must be greater than DBP in every row")
        if "Risk_Status" in raw.columns and raw["Risk_Status"].nunique() <= 1:
            warnings.append("Risk_Status is constant; it is ignored, risk is derived from the rule thresholds in athera_ai.label_risk")
    return errors, warnings
