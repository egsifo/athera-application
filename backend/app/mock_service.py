"""Mock endpoints for integration testing.

IMPORTANT: nothing in this module is a model. It exists so the mobile app and
the contract can be tested end to end before the real LSTM / XGBoost services
exist.

* Forecast: repeats the last observed value of each vital (a "persistence"
  placeholder). No learning, no inference.
* Risk: returns a fixed fixture chosen by ATHERA_MOCK_RISK_CLASS.

Every response carries ``status="mock"`` and a model name that says so, and the
mobile app shows a MOCK badge for such results.
"""
from __future__ import annotations

from datetime import datetime, timedelta

from .config import Settings
from .schemas import (
    DataQuality,
    ForecastRequest,
    ForecastResponse,
    ModelWarning,
    PredictedPoint,
    RiskRequest,
    RiskResponse,
)

MOCK_FORECAST_NAME = "MOCK-PERSISTENCE-PLACEHOLDER"
MOCK_RISK_NAME = "MOCK-FIXTURE"
MOCK_VERSION = "mock-0"

# Fixed fixture values, only used so the UI can be exercised.
_FIXTURE_SCORES = {"normal": 12.0, "early_warning": 48.0, "critical": 85.0, "unknown": None}


def _last_value(req: ForecastRequest, attr: str) -> float | None:
    for m in reversed(req.measurements):
        value = getattr(m, attr)
        if value is not None:
            return float(value)
    return None


def mock_forecast(
    req: ForecastRequest, completeness: dict[str, float], now: datetime
) -> ForecastResponse:
    step = req.sampling_interval_seconds
    steps = max(1, req.prediction_horizon_seconds // step)
    last_ts = req.measurements[-1].timestamp
    held = {
        "heart_rate_bpm": _last_value(req, "heart_rate_bpm"),
        "spo2_percent": _last_value(req, "spo2_percent"),
        "temperature_celsius": _last_value(req, "temperature_celsius"),
        "respiratory_rate_bpm": _last_value(req, "respiratory_rate_bpm"),
    }
    points = [
        PredictedPoint(timestamp=last_ts + timedelta(seconds=step * (i + 1)), **held)
        for i in range(steps)
    ]
    return ForecastResponse(
        astronaut_id=req.astronaut_id,
        model_name=MOCK_FORECAST_NAME,
        model_version=MOCK_VERSION,
        status="mock",
        prediction_horizon_seconds=req.prediction_horizon_seconds,
        step_seconds=step,
        predictions=points,
        generated_at=now,
        data_quality=DataQuality(
            input_completeness=completeness,
            notes=["Mock service: last observed values repeated. No model inference was performed."],
        ),
    )


def mock_risk(req: RiskRequest, settings: Settings, now: datetime) -> RiskResponse:
    risk_class = settings.mock_risk_class
    warnings: list[ModelWarning] = []
    if risk_class in ("early_warning", "critical"):
        warnings.append(
            ModelWarning(
                code="mock_fixture",
                message="Fixture warning from the mock service. No model inference was performed.",
                severity="critical" if risk_class == "critical" else "warning",
            )
        )
    return RiskResponse(
        astronaut_id=req.astronaut_id,
        model_name=MOCK_RISK_NAME,
        model_version=MOCK_VERSION,
        status="mock",
        risk_class=risk_class,  # type: ignore[arg-type]
        risk_score=_FIXTURE_SCORES[risk_class],
        class_probabilities=None,  # a mock must not invent probabilities
        generated_at=now,
        contributing_features=[],
        warnings=warnings,
        anomalies=[],
        data_quality=DataQuality(
            input_completeness=None,
            notes=["Mock service: fixed fixture response."],
        ),
    )
