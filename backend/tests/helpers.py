"""Shared builders for gateway tests."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.config import Settings
from app.schemas import ForecastRequest, RiskRequest

T0 = datetime(2026, 10, 19, 12, 0, 0, tzinfo=timezone.utc)


def make_settings(**overrides) -> Settings:
    base = dict(mode="mock", min_window_size=10)
    base.update(overrides)
    return Settings(**base)


def measurements(n: int = 12, interval: int = 60, hr: float | None = 80.0, spo2: float | None = 98.0):
    items = []
    for i in range(n):
        items.append(
            {
                "timestamp": (T0 + timedelta(seconds=i * interval)).isoformat().replace("+00:00", "Z"),
                "heart_rate_bpm": hr,
                "spo2_percent": spo2,
                "temperature_celsius": 36.8,
                "respiratory_rate_bpm": 16,
            }
        )
    return items


def forecast_payload(**overrides) -> dict:
    payload = {
        "astronaut_id": "demo-astronaut-01",
        "window_size": 12,
        "sampling_interval_seconds": 60,
        "prediction_horizon_seconds": 300,
        "measurements": measurements(12),
    }
    payload.update(overrides)
    return payload


def forecast_request(**overrides) -> ForecastRequest:
    return ForecastRequest.model_validate(forecast_payload(**overrides))


def risk_payload(**overrides) -> dict:
    payload = {
        "astronaut_id": "demo-astronaut-01",
        "assessed_at": "2026-10-19T12:12:00Z",
        "current": measurements(1)[0],
        "features": {"hr_mean_15m": 81.5, "spo2_min_15m": None},
    }
    payload.update(overrides)
    return payload


def risk_request(**overrides) -> RiskRequest:
    return RiskRequest.model_validate(risk_payload(**overrides))
