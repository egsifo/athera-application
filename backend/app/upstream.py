"""Client for the real model services (proxy mode).

The gateway forwards validated requests to the services you host (for example
a TensorFlow/Keras LSTM service and an XGBoost service). The upstream API key
is attached here, on the server, so it never reaches the mobile app.
"""
from __future__ import annotations

import logging
from typing import Any, Protocol

logger = logging.getLogger("athera.upstream")


class UpstreamUnavailable(Exception):
    """The model service could not be reached."""


class UpstreamTimeout(Exception):
    """The model service did not answer in time."""


class UpstreamHttpError(Exception):
    """The model service answered with a non-2xx status."""

    def __init__(self, status_code: int, body_preview: str = "") -> None:
        super().__init__(f"upstream returned HTTP {status_code}")
        self.status_code = status_code
        self.body_preview = body_preview


class Upstream(Protocol):
    def post_json(self, url: str, payload: dict[str, Any]) -> dict[str, Any]: ...


class HttpUpstream:
    """httpx-based upstream client. httpx is imported lazily."""

    def __init__(self, api_key: str | None, timeout_seconds: float) -> None:
        self._api_key = api_key
        self._timeout = timeout_seconds

    def post_json(self, url: str, payload: dict[str, Any]) -> dict[str, Any]:
        import httpx  # lazy: only needed in proxy mode

        headers = {"Content-Type": "application/json"}
        if self._api_key:
            headers["Authorization"] = f"Bearer {self._api_key}"
        try:
            response = httpx.post(url, json=payload, headers=headers, timeout=self._timeout)
        except httpx.TimeoutException as exc:
            raise UpstreamTimeout(str(exc)) from exc
        except httpx.HTTPError as exc:
            raise UpstreamUnavailable(str(exc)) from exc

        if response.status_code >= 400:
            # Keep only a short preview and never log request payloads.
            raise UpstreamHttpError(response.status_code, response.text[:200])
        try:
            data = response.json()
        except ValueError as exc:
            raise UpstreamHttpError(502, "response was not valid JSON") from exc
        if not isinstance(data, dict):
            raise UpstreamHttpError(502, "response JSON was not an object")
        return data
