"""FastAPI application: the ATHERA AI integration gateway.

Run (from the backend/ folder):
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

Interactive API docs are served at /docs once the server is running.
"""
from __future__ import annotations

import hmac
import logging

from fastapi import Depends, FastAPI, Header, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .config import SERVICE_VERSION, Settings, load_settings
from .errors import GatewayError
from .gateway import Gateway
from .schemas import (
    ErrorEnvelope,
    ForecastRequest,
    ForecastResponse,
    ModelStatus,
    PredictionHistory,
    RiskRequest,
    RiskResponse,
)
from .upstream import HttpUpstream, Upstream

_ERRORS = {
    401: {"model": ErrorEnvelope},
    422: {"model": ErrorEnvelope},
    502: {"model": ErrorEnvelope},
    503: {"model": ErrorEnvelope},
    504: {"model": ErrorEnvelope},
}


def create_app(settings: Settings | None = None, upstream: Upstream | None = None) -> FastAPI:
    settings = settings or load_settings()
    logging.basicConfig(
        level=getattr(logging, settings.log_level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    logger = logging.getLogger("athera.api")

    if settings.mode == "proxy" and upstream is None:
        upstream = HttpUpstream(settings.upstream_api_key, settings.upstream_timeout_seconds)
    gateway = Gateway(settings, upstream)

    app = FastAPI(
        title="ATHERA AI Integration Gateway",
        version=SERVICE_VERSION,
        description=(
            "Validated contract between the ATHERA mobile app and externally hosted "
            "forecast / risk models. In mock mode it returns clearly labelled fixtures; "
            "it never contains a model."
        ),
    )

    # ------------------------------------------------------------- dependencies
    def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
        expected = settings.gateway_api_key
        if expected is None:
            return
        supplied = (x_api_key or "").encode("utf-8")
        if not hmac.compare_digest(supplied, expected.encode("utf-8")):
            raise GatewayError(401, "unauthorized", "Missing or invalid API key")

    def simulate_error(x_mock_error: str | None = Header(default=None)) -> None:
        """Mock mode only: `X-Mock-Error: 503` makes the endpoint fail on purpose."""
        if settings.mode != "mock" or not x_mock_error:
            return
        try:
            status = int(x_mock_error)
        except ValueError:
            return
        if 400 <= status <= 599:
            raise GatewayError(status, "mock_simulated_error", f"Simulated HTTP {status} (mock mode)")

    # ----------------------------------------------------------------- handlers
    @app.exception_handler(GatewayError)
    async def _gateway_error(_: Request, exc: GatewayError) -> JSONResponse:
        return JSONResponse(status_code=exc.status_code, content=exc.to_dict())

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        details = [
            f"{'.'.join(str(part) for part in err['loc'])}: {err['msg']}" for err in exc.errors()[:20]
        ]
        body = GatewayError(422, "validation_error", "Request body failed schema validation", details)
        return JSONResponse(status_code=422, content=body.to_dict())

    # ------------------------------------------------------------------- routes
    @app.get("/health")
    def health() -> dict:
        return {"status": "ok", "service_version": SERVICE_VERSION, "mode": settings.mode}

    @app.get(
        "/api/v1/model-status",
        response_model=ModelStatus,
        responses=_ERRORS,
        dependencies=[Depends(require_api_key)],
    )
    def model_status() -> ModelStatus:
        return gateway.model_status()

    @app.post(
        "/api/v1/forecast",
        response_model=ForecastResponse,
        responses=_ERRORS,
        dependencies=[Depends(require_api_key), Depends(simulate_error)],
    )
    def forecast(body: ForecastRequest) -> ForecastResponse:
        logger.info("forecast astronaut=%s window=%s", body.astronaut_id, body.window_size)
        return gateway.forecast(body)

    @app.post(
        "/api/v1/risk-assessment",
        response_model=RiskResponse,
        responses=_ERRORS,
        dependencies=[Depends(require_api_key), Depends(simulate_error)],
    )
    def risk_assessment(body: RiskRequest) -> RiskResponse:
        logger.info("risk astronaut=%s", body.astronaut_id)
        return gateway.risk_assessment(body)

    @app.get(
        "/api/v1/predictions",
        response_model=PredictionHistory,
        responses=_ERRORS,
        dependencies=[Depends(require_api_key)],
    )
    def predictions(
        astronaut_id: str = Query(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_\-]+$"),
        limit: int = Query(default=50, ge=1, le=500),
    ) -> PredictionHistory:
        return gateway.prediction_history(astronaut_id, limit)

    return app


app = create_app()
