"""
build_real_data_assets.py - turn the team's real NASA data pack into small app assets.

    python tools/build_real_data_assets.py <NASA_Space_Health_FINAL dir> [out dir]

Inputs  (all real, nothing imputed or invented):
  data/radlab_iss_daily_summary.csv      ISS RadLab dose rates (uGy/h), daily
  osdr/OSD-569 CBC and osdr/OSD-575 CMP   Inspiration4 crew blood tests (n = 4)
Outputs: assets/data/iss_radiation.json, assets/data/i4_blood.json

Honesty rules baked in: absorbed dose (uGy) is never converted to dose equivalent
(mSv); days with partial instrument coverage are kept but flagged, never filled;
the reference ranges are the lab's own, copied from the source tables.
"""
import json
import re
import sys
from pathlib import Path

import pandas as pd

src = Path(sys.argv[1])
out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "assets" / "data"
out.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------- radiation
daily = pd.read_csv(src / "data" / "radlab_iss_daily_summary.csv")
INSTR = ["DosTel2", "DosTel1"]  # same module (Columbus), same detector family: comparable over 2019-2024
rad = {}
for ins in INSTR:
    d = daily[daily.instrument_id == ins].copy().sort_values("date_utc")
    full = float(d.n_samples.median())
    # Cadence changed over the years, so "complete" is judged against the same month's typical day.
    month_typ = d.groupby(d.date_utc.str[:7]).n_samples.transform("median")
    d["complete"] = d.n_samples >= 0.9 * month_typ
    rad[ins] = {
        "typical_samples_per_day": int(full),
        "days": [
            [r.date_utc, round(float(r.absorbed_dose_rate_mean_uGy_per_h), 3),
             round(float(r.absorbed_dose_rate_median_uGy_per_h), 3),
             round(float(r.absorbed_dose_rate_max_uGy_per_h), 3),
             int(r.n_samples), 1 if r.complete else 0]
            for r in d.itertuples()
        ],
    }
rad_json = {
    "title": "ISS radiation, RadLab dose-rate instruments",
    "source": "NASA RadLab / Open Science Data Repository, ISS radiation dose rates 2019-01-01 to 2024-11-04",
    "kind": "measured",
    "unit": "uGy/h (absorbed dose rate, NOT dose equivalent; no conversion to mSv is made)",
    "columns": ["date_utc", "mean_uGy_h", "median_uGy_h", "max_uGy_h", "n_samples", "complete_day"],
    "instruments": rad,
    "notes": [
        "Instrument dose rate inside the Columbus module. It is not an individual astronaut's dose.",
        "No data from 2023-07 to 2023-12 for most instruments. Gaps are shown as gaps, never interpolated.",
        "The daily mean is dominated by South Atlantic Anomaly passes; the median shows the quiet baseline.",
        "Days with fewer than 90% of that month's usual samples are flagged complete_day=0 and excluded from dose totals.",
    ],
}
(out / "iss_radiation.json").write_text(json.dumps(rad_json, separators=(",", ":")))

# ------------------------------------------------------------------- blood
TIMES = ["L-92", "L-44", "L-3", "R+1", "R+45", "R+82", "R+194"]
markers = []


def add(csv, panel):
    d = pd.read_csv(csv, encoding="utf-8-sig")
    d["crew"] = d["Sample Name"].str.extract(r"^(C\d+)")
    d["t"] = d["Sample Name"].str.extract(r"_(L-\d+|R\+\d+)")
    for col in [c for c in d.columns if re.search(r"_value(_|$)", c)]:
        base, _, unit = col.partition("_value")
        unit = unit.lstrip("_").replace("_per_", "/").replace("_", " ")
        lo = next((c for c in d.columns if c.startswith(base + "_range_min") or c.startswith(base + "_min")), None)
        hi = next((c for c in d.columns if c.startswith(base + "_range_max") or c.startswith(base + "_max")), None)
        series = {}
        for crew, g in d.groupby("crew"):
            series[crew] = {r.t: (None if pd.isna(getattr(r, "v")) else float(r.v)) for r in
                            g.assign(v=pd.to_numeric(g[col], errors="coerce")).itertuples()}
        rmin = pd.to_numeric(d[lo], errors="coerce").median() if lo else float("nan")
        rmax = pd.to_numeric(d[hi], errors="coerce").median() if hi else float("nan")
        markers.append({
            "id": base, "label": base.replace("_", " ").replace("egfr", "eGFR").replace("alt", "ALT")
                                    .replace("ast", "AST").replace("bun", "BUN").replace("mch", "MCH")
                                    .replace("mcv", "MCV").replace("mpv", "MPV").replace("rdw", "RDW").title(),
            "panel": panel, "unit": unit,
            "ref_min": None if pd.isna(rmin) else float(rmin), "ref_max": None if pd.isna(rmax) else float(rmax),
            "values": {c: [series[c].get(t) for t in TIMES] for c in sorted(series)},
        })


add(src / "osdr/OSD-569/LSDS-7_Complete_Blood_Count_CBC_TRANSFORMED.csv", "CBC (whole blood)")
add(src / "osdr/OSD-575/LSDS-8_Comprehensive_Metabolic_Panel_CMP_TRANSFORMED.csv", "CMP (serum)")
blood = {
    "title": "Inspiration4 crew blood tests",
    "source": "NASA OSDR OSD-569 (CBC) and OSD-575 (CMP), Inspiration4, four private astronauts, 3-day flight",
    "kind": "measured",
    "timepoints": TIMES,
    "timepoint_note": "L-n = n days before launch, R+n = n days after return",
    "markers": markers,
    "notes": [
        "Only four people. Differences are descriptive, not statistical evidence.",
        "Reference ranges are the lab's general-population ranges, not astronaut-specific limits.",
        "Crew IDs are the study's anonymous codes.",
    ],
}
(out / "i4_blood.json").write_text(json.dumps(blood, separators=(",", ":")))
print("markers", len(markers), "radiation days", {k: len(v["days"]) for k, v in rad.items()})
