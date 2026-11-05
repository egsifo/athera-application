"""Gateway logic: validate, route to mock or upstream, validate the answer.

Rules this module enforces:
* A failed or invalid upstream answer becomes an error. It is never replaced
  by a fabricated "successful" result.
* Upstream answers must match the contract and must refer to the same
  astronaut / horizon that was requested.
"""
from __future__ import annotations

import logging
from collections import deque
from datetime import datetime, timezone
from typing import Callable

from pydantic import ValidationError

from . import mock_service
from .config import SERVICE_VERSION, Settings
from .errors import GatewayError
from .schemas import (
    ForecastRequest,
    ForecastResponse,
    ModelInfo,
    ModelStatus,
    PredictionHistory,
    RiskRequest,
    RiskResponse,
)
from .upstream import (
    Upstream,
    UpstreamHttpError,
    UpstreamTimeout,
    UpstreamUnavailable,
)
from .validation import validate_forecast_request

logger = logging.getLogger("athera.gateway")


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Gateway:
    def __init__(
        self,
        settings: Settings,
        upstream: Upstream | None = None,
        clock: Callable[[], datetime] = _utcnow,
    ) -> None:
        self._settings = settings
        self._upstream = upstream
        self._clock = clock
        self._history: deque[RiskResponse] = deque(maxlen=settings.history_max_items)
        if settings.mode == "proxy" and upstream is None:
            raise ValueError("proxy mode requires an upstream client")

    # ------------------------------------------------------------------ forecast
    def forecast(self, req: ForecastRequest) -> ForecastResponse:
        completeness = validate_forecast_request(req, self._settings)
        if self._settings.mode == "mock":
            return mock_service.mock_forecast(req, completeness, self._clock())

        payload = req.model_dump(mode="json")
        raw = self._call_upstream(self._settings.upstream_forecast_url, payload, "forecast")
        response = self._parse(ForecastResponse, raw, "forecast")
        if response.astronaut_id != req.astronaut_id:
            raise GatewayError(502, "upstream_mismatch", "Forecast was returned for a different astronaut")
        if response.prediction_horizon_seconds != req.prediction_horizon_seconds:
            raise GatewayError(502, "upstream_mismatch", "Forecast horizon differs from the request")
        return response

    # ------------------------------------------------------------ risk assessment
    def risk_assessment(self, req: RiskRequest) -> RiskResponse:
        if self._settings.mode == "mock":
            response = mock_service.mock_risk(req, self._settings, self._clock())
        else:
            payload = req.model_dump(mode="json")
            raw = self._call_upstream(self._settings.upstream_risk_url, payload, "risk")
            response = self._parse(RiskResponse, raw, "risk")
            if response.astronaut_id != req.astronaut_id:
                raise GatewayError(502, "upstream_mismatch", "Assessment was returned for a different astronaut")
        self._history.append(response)
        return response

    # -------------------------------------------------------------- status/history
    def model_status(self) -> ModelStatus:
        settings = self._settings
        if settings.mode == "mock":
            forecast_info = ModelInfo(name=mock_service.MOCK_FORECAST_NAME, version=mock_service.MOCK_VERSION, status="mock")
            risk_info = ModelInfo(name=mock_service.MOCK_RISK_NAME, version=mock_service.MOCK_VERSION, status="mock")
        else:
            # The gateway does not know upstream model versions until a call has
            # been made; report what it has actually seen, nothing invented.
            forecast_info = None
            risk_info = None
        return ModelStatus(
            service_version=SERVICE_VERSION,
            mode=settings.mode,  # type: ignore[arg-type]
            status="ok",
            checked_at=self._clock(),
            forecast_model=forecast_info,
            risk_model=risk_info,
            supported_horizons_seconds=list(settings.supported_horizons_seconds),
            min_window_size=settings.min_window_size,
            max_window_size=settings.max_window_size,
        )

    def prediction_history(self, astronaut_id: str, limit: int) -> PredictionHistory:
        limit = max(1, min(limit, 500))
        items = [r for r in self._history if r.astronaut_id == astronaut_id]
        items.sort(key=lambda r: r.generated_at, reverse=True)
        return PredictionHistory(astronaut_id=astronaut_id, items=items[:limit])

    # ------------------------------------------------------------------- helpers
    def _call_upstream(self, url: str | None, payload: dict, label: str) -> dict:
        assert self._upstream is not None and url is not None
        try:
            return self._upstream.post_json(url, payload)
        except UpstreamTimeout as exc:
            logger.warning("upstream %s timeout", label)
            raise GatewayError(504, "upstream_timeout", f"The {label} service timed out") from exc
        except UpstreamUnavailable as exc:
            logger.warning("upstream %s unreachable", label)
            raise GatewayError(503, "upstream_unavailable", f"The {label} service is unavailable") from exc
        except UpstreamHttpError as exc:
            logger.warning("upstream %s returned HTTP %s", label, exc.status_code)
            raise GatewayError(
                502, "upstream_error", f"The {label} service returned HTTP {exc.status_code}"
            ) from exc

    @staticmethod
    def _parse(model, raw: dict, label: str):
        try:
            return model.model_validate(raw)
        except ValidationError as exc:
            details = [f"{'.'.join(str(p) for p in e['loc'])}: {e['msg']}" for e in exc.errors()[:10]]
            logger.warning("upstream %s response failed schema validation", label)
            raise GatewayError(
                502,
                "upstream_schema_error",
                f"The {label} service returned a response that does not match the contract",
                details,
            ) from exc
