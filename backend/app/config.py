"""Gateway configuration, read from environment variables.

Secrets (upstream API key, gateway API key) live only on the server and are
never sent to the mobile app.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

SERVICE_VERSION = "0.1.0"
VALID_MODES = ("mock", "proxy")
VALID_RISK_CLASSES = ("normal", "early_warning", "critical", "unknown")


class ConfigError(ValueError):
    """Raised at startup when the environment configuration is invalid."""


def _int_list(raw: str, name: str) -> tuple[int, ...]:
    try:
        values = tuple(int(part.strip()) for part in raw.split(",") if part.strip())
    except ValueError as exc:
        raise ConfigError(f"{name} must be a comma-separated list of integers") from exc
    if not values or any(v <= 0 for v in values):
        raise ConfigError(f"{name} must contain positive integers")
    return tuple(sorted(set(values)))


@dataclass(frozen=True)
class Settings:
    mode: str = "mock"
    gateway_api_key: str | None = None
    upstream_forecast_url: str | None = None
    upstream_risk_url: str | None = None
    upstream_api_key: str | None = field(default=None, repr=False)
    upstream_timeout_seconds: float = 10.0
    mock_risk_class: str = "normal"
    supported_horizons_seconds: tuple[int, ...] = (300, 600, 1800)
    min_window_size: int = 10
    max_window_size: int = 1440
    min_completeness: float = 0.5
    history_max_items: int = 500
    log_level: str = "INFO"

    def __post_init__(self) -> None:
        if self.mode not in VALID_MODES:
            raise ConfigError(f"ATHERA_GATEWAY_MODE must be one of {VALID_MODES}")
        if self.mock_risk_class not in VALID_RISK_CLASSES:
            raise ConfigError(f"ATHERA_MOCK_RISK_CLASS must be one of {VALID_RISK_CLASSES}")
        if self.mode == "proxy" and not (self.upstream_forecast_url and self.upstream_risk_url):
            raise ConfigError(
                "proxy mode requires ATHERA_UPSTREAM_FORECAST_URL and ATHERA_UPSTREAM_RISK_URL"
            )
        if not 0 < self.min_completeness <= 1:
            raise ConfigError("ATHERA_MIN_COMPLETENESS must be in (0, 1]")
        if self.min_window_size < 2 or self.max_window_size < self.min_window_size:
            raise ConfigError("window size limits are inconsistent")
        if self.upstream_timeout_seconds <= 0:
            raise ConfigError("ATHERA_UPSTREAM_TIMEOUT_SECONDS must be > 0")

    @property
    def model_status_label(self) -> str:
        return "mock" if self.mode == "mock" else "proxy"


def load_settings(env: dict[str, str] | None = None) -> Settings:
    """Build Settings from an environment mapping (defaults to os.environ)."""
    e = os.environ if env is None else env

    def get(name: str, default: str | None = None) -> str | None:
        value = e.get(name)
        if value is None or value.strip() == "":
            return default
        return value.strip()

    try:
        timeout = float(get("ATHERA_UPSTREAM_TIMEOUT_SECONDS", "10"))
        completeness = float(get("ATHERA_MIN_COMPLETENESS", "0.5"))
        min_window = int(get("ATHERA_MIN_WINDOW_SIZE", "10"))
        max_window = int(get("ATHERA_MAX_WINDOW_SIZE", "1440"))
        history_max = int(get("ATHERA_HISTORY_MAX_ITEMS", "500"))
    except ValueError as exc:
        raise ConfigError(f"numeric environment variable is not a number: {exc}") from exc

    return Settings(
        mode=(get("ATHERA_GATEWAY_MODE", "mock") or "mock").lower(),
        gateway_api_key=get("ATHERA_API_KEY"),
        upstream_forecast_url=get("ATHERA_UPSTREAM_FORECAST_URL"),
        upstream_risk_url=get("ATHERA_UPSTREAM_RISK_URL"),
        upstream_api_key=get("ATHERA_UPSTREAM_API_KEY"),
        upstream_timeout_seconds=timeout,
        mock_risk_class=(get("ATHERA_MOCK_RISK_CLASS", "normal") or "normal").lower(),
        supported_horizons_seconds=_int_list(
            get("ATHERA_SUPPORTED_HORIZONS", "300,600,1800") or "", "ATHERA_SUPPORTED_HORIZONS"
        ),
        min_window_size=min_window,
        max_window_size=max_window,
        min_completeness=completeness,
        history_max_items=history_max,
        log_level=(get("ATHERA_LOG_LEVEL", "INFO") or "INFO").upper(),
    )
