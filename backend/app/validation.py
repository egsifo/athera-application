"""Semantic validation that goes beyond per-field schema checks.

Pydantic validates each field; this module validates the *relationships*
between fields (window length, regular sampling grid, completeness, horizon).
"""
from __future__ import annotations

from .config import Settings
from .errors import GatewayError
from .schemas import ForecastRequest

CORE_VITALS = (
    "heart_rate_bpm",
    "spo2_percent",
    "temperature_celsius",
    "respiratory_rate_bpm",
)


def input_completeness(req: ForecastRequest) -> dict[str, float]:
    """Fraction of grid slots that carry a value, per core vital."""
    total = len(req.measurements)
    result: dict[str, float] = {}
    for name in CORE_VITALS:
        present = sum(1 for m in req.measurements if getattr(m, name) is not None)
        result[name] = round(present / total, 4) if total else 0.0
    return result


def validate_forecast_request(req: ForecastRequest, settings: Settings) -> dict[str, float]:
    """Validate relationships inside a forecast request.

    Returns the per-vital completeness map on success. Raises GatewayError(422)
    listing *all* problems found, so the client can fix them in one pass.
    """
    problems: list[str] = []
    n = len(req.measurements)

    if n != req.window_size:
        problems.append(f"window_size is {req.window_size} but {n} measurements were sent")
    if not settings.min_window_size <= req.window_size <= settings.max_window_size:
        problems.append(
            f"window_size must be between {settings.min_window_size} and "
            f"{settings.max_window_size}"
        )
    if req.prediction_horizon_seconds not in settings.supported_horizons_seconds:
        problems.append(
            "prediction_horizon_seconds must be one of "
            f"{list(settings.supported_horizons_seconds)}"
        )
    if req.prediction_horizon_seconds < req.sampling_interval_seconds:
        problems.append("prediction_horizon_seconds must be >= sampling_interval_seconds")

    stamps = [m.timestamp for m in req.measurements]
    if any(b <= a for a, b in zip(stamps, stamps[1:])):
        problems.append("measurement timestamps must be strictly increasing")
    else:
        tolerance = max(1.0, 0.1 * req.sampling_interval_seconds)
        for index, (a, b) in enumerate(zip(stamps, stamps[1:])):
            gap = (b - a).total_seconds()
            if abs(gap - req.sampling_interval_seconds) > tolerance:
                problems.append(
                    f"gap before measurement {index + 1} is {gap:.0f}s, expected "
                    f"{req.sampling_interval_seconds}s (+/- {tolerance:.0f}s)"
                )
                break  # one example is enough

    completeness = input_completeness(req)
    if not any(v >= settings.min_completeness for v in completeness.values()):
        problems.append(
            "no core vital has at least "
            f"{int(settings.min_completeness * 100)}% of the window populated"
        )

    if problems:
        raise GatewayError(422, "invalid_forecast_request", "Forecast request failed validation", problems)
    return completeness
