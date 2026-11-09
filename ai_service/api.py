"""
api.py - ATHERA model server.

    uvicorn api:app --host 0.0.0.0 --port 8000        then open http://127.0.0.1:8000/docs

The app POSTs the last 13+ readings (15 min apart, oldest first) to /predict.
Contract (unchanged): GET / and POST /predict. Added: GET /model-info.
"""
import json
import math
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, field_validator

from athera_ai import AtheraAI, MIN_READINGS
from data_check import HARD_RANGES

HERE = Path(__file__).parent
app = FastAPI(title="ATHERA AI", version="1.1.0")
ai = AtheraAI(str(HERE / "athera_model.joblib"))


def _r(name):
    lo, hi = HARD_RANGES[name]
    return Field(ge=lo, le=hi, description=f"physically plausible range {lo}..{hi}")


class Reading(BaseModel):
    Heart_Rate: float = _r("Heart_Rate")
    SBP: float = _r("SBP")
    DBP: float = _r("DBP")
    SpO2: float = _r("SpO2")
    Body_Temp: float = _r("Body_Temp")
    HRV_Stress_Index: float = _r("HRV_Stress_Index")
    Radiation_Level: float = _r("Radiation_Level")
    Sleep_Hours: float = _r("Sleep_Hours")
    Physical_Activity_Load: float = _r("Physical_Activity_Load")

    @field_validator("*")
    @classmethod
    def _finite(cls, v):
        if not math.isfinite(v):
            raise ValueError("must be a finite number")
        return v


class Request(BaseModel):
    history: list[Reading]  # oldest first, newest last


@app.post("/predict")
def predict(req: Request):
    if len(req.history) < MIN_READINGS:
        raise HTTPException(status_code=400, detail=f"need at least {MIN_READINGS} readings, got {len(req.history)}")
    if any(r.SBP <= r.DBP for r in req.history):
        raise HTTPException(status_code=400, detail="SBP must be greater than DBP in every reading")
    try:
        return ai.predict([r.model_dump() for r in req.history])
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@app.get("/")
def health():
    return {"status": "ok", "predicts_minutes_ahead": ai.minutes_ahead}


@app.get("/model-info")
def model_info():
    """What this model was trained on and how it scored. Read from metrics.json, never hard-coded."""
    p = HERE / "metrics.json"
    metrics = json.loads(p.read_text()) if p.exists() else {}
    return {
        "predicts_minutes_ahead": ai.minutes_ahead,
        "min_readings": MIN_READINGS,
        "reading_interval_minutes": 15,
        "n_features": len(ai.feature_names),
        "metrics": metrics,
        "disclaimer": "Decision support only. Not a medical device. Check metrics.trained_on / data_kind for what the model has seen.",
    }
