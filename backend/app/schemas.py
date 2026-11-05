"""Request / response contracts for the ATHERA AI integration gateway.

These schemas are the single source of truth for the mobile app, the gateway
and the external model services. They describe the *shape* of data only; they
are not evidence that any model has been trained or validated.

Conventions
-----------
* Every timestamp is timezone-aware ISO-8601 (UTC recommended, "Z" suffix).
* Requests use ``extra="forbid"`` so typos fail loudly.
* Responses use ``extra="ignore"`` so a model service can add fields without
  breaking older clients; required fields are still enforced.
* ``None`` means "not measured / not provided". It is never replaced by a
  default number.
"""
from __future__ import annotations

from typing import Annotated, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

RiskClass = Literal["normal", "early_warning", "critical", "unknown"]
ResultStatus = Literal["ok", "mock", "degraded"]
Severity = Literal["info", "warning", "critical"]

AstronautId = Annotated[str, Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9_\-]+$")]
Probability = Annotated[float, Field(ge=0.0, le=1.0)]


class _Request(BaseModel):
    model_config = ConfigDict(extra="forbid")


class _Response(BaseModel):
    model_config = ConfigDict(extra="ignore")


# --------------------------------------------------------------------------
# Shared building blocks
# --------------------------------------------------------------------------
class Measurement(_Request):
    """One time-slot of measured values. Any vital may be null (not measured)."""

    timestamp: AwareDatetime
    heart_rate_bpm: float | None = Field(default=None, ge=20, le=250)
    spo2_percent: float | None = Field(default=None, ge=50, le=100)
    temperature_celsius: float | None = Field(default=None, ge=30, le=45)
    respiratory_rate_bpm: float | None = Field(default=None, ge=4, le=60)
    systolic_mmhg: float | None = Field(default=None, ge=50, le=260)
    diastolic_mmhg: float | None = Field(default=None, ge=20, le=160)


class PredictedPoint(_Response):
    """One forecast time-slot. A model may forecast only a subset of vitals."""

    timestamp: AwareDatetime
    heart_rate_bpm: float | None = None
    spo2_percent: float | None = None
    temperature_celsius: float | None = None
    respiratory_rate_bpm: float | None = None


class DataQuality(_Response):
    """Optional data-quality report returned by a model service."""

    input_completeness: dict[str, Probability] | None = None
    notes: list[str] = Field(default_factory=list)


# --------------------------------------------------------------------------
# Forecast
# --------------------------------------------------------------------------
class ForecastRequest(_Request):
    astronaut_id: AstronautId
    window_size: int = Field(ge=2, le=100_000)
    sampling_interval_seconds: int = Field(ge=1, le=3600)
    prediction_horizon_seconds: int = Field(ge=1, le=86_400)
    measurements: list[Measurement] = Field(min_length=1, max_length=100_000)


class ForecastResponse(_Response):
    astronaut_id: AstronautId
    model_name: str = Field(min_length=1)
    model_version: str = Field(min_length=1)
    status: ResultStatus
    prediction_horizon_seconds: int = Field(ge=1)
    step_seconds: int = Field(ge=1)
    predictions: list[PredictedPoint] = Field(min_length=1)
    generated_at: AwareDatetime
    data_quality: DataQuality | None = None

    @model_validator(mode="after")
    def _check_predictions(self) -> "ForecastResponse":
        if self.step_seconds > self.prediction_horizon_seconds:
            raise ValueError("step_seconds must not exceed prediction_horizon_seconds")
        stamps = [p.timestamp for p in self.predictions]
        if any(b <= a for a, b in zip(stamps, stamps[1:])):
            raise ValueError("prediction timestamps must be strictly increasing")
        return self


# --------------------------------------------------------------------------
# Risk assessment
# --------------------------------------------------------------------------
class ForecastSummary(_Request):
    """Forecast outputs forwarded into the risk-assessment request."""

    model_name: str = Field(min_length=1)
    model_version: str = Field(min_length=1)
    step_seconds: int = Field(ge=1)
    predictions: list[PredictedPoint] = Field(min_length=1)

    # PredictedPoint tolerates extras on parse, but requests stay strict about
    # the envelope. Points themselves are produced by the app from a validated
    # forecast response.


class RiskRequest(_Request):
    astronaut_id: AstronautId
    assessed_at: AwareDatetime
    current: Measurement
    # Free-form engineered features (name -> value). The final feature set is
    # defined by the XGBoost model owner; see AI_INTEGRATION.md.
    features: dict[str, float | None] = Field(default_factory=dict, max_length=200)
    forecast: ForecastSummary | None = None


class ContributingFeature(_Response):
    feature: str = Field(min_length=1)
    direction: Literal["increase", "decrease"] | None = None
    # Meaning of ``weight`` is defined by the model owner (e.g. SHAP value).
    weight: float | None = None
    description: str | None = None


class ModelWarning(_Response):
    code: str = Field(min_length=1)
    message: str = Field(min_length=1)
    severity: Severity = "warning"


class Anomaly(_Response):
    metric: str = Field(min_length=1)
    timestamp: AwareDatetime | None = None
    description: str = Field(min_length=1)
    score: float | None = None


class RiskResponse(_Response):
    astronaut_id: AstronautId
    model_name: str = Field(min_length=1)
    model_version: str = Field(min_length=1)
    status: ResultStatus
    risk_class: RiskClass
    # Index on a 0-100 scale defined by the model owner. NOT a probability.
    risk_score: float | None = Field(default=None, ge=0, le=100)
    # Only present if the model produces probabilities. Never derived from
    # risk_score by the gateway or the app.
    class_probabilities: dict[RiskClass, Probability] | None = None
    generated_at: AwareDatetime
    contributing_features: list[ContributingFeature] = Field(default_factory=list)
    warnings: list[ModelWarning] = Field(default_factory=list)
    anomalies: list[Anomaly] = Field(default_factory=list)
    data_quality: DataQuality | None = None

    @model_validator(mode="after")
    def _check_probabilities(self) -> "RiskResponse":
        if self.class_probabilities is not None:
            total = sum(self.class_probabilities.values())
            if abs(total - 1.0) > 0.01:
                raise ValueError("class_probabilities must sum to 1 (+/- 0.01)")
        return self


# --------------------------------------------------------------------------
# Model status and history
# --------------------------------------------------------------------------
class ModelInfo(_Response):
    name: str
    version: str
    status: Literal["ok", "mock", "unavailable"]


class ModelStatus(_Response):
    service_version: str
    mode: Literal["mock", "proxy"]
    status: Literal["ok", "degraded", "down"]
    checked_at: AwareDatetime
    forecast_model: ModelInfo | None = None
    risk_model: ModelInfo | None = None
    supported_horizons_seconds: list[int] = Field(default_factory=list)
    min_window_size: int | None = None
    max_window_size: int | None = None


class PredictionHistory(_Response):
    astronaut_id: AstronautId
    items: list[RiskResponse]


class ErrorBody(BaseModel):
    code: str
    message: str
    details: list[str] = Field(default_factory=list)


class ErrorEnvelope(BaseModel):
    error: ErrorBody
