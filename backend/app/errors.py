"""Gateway error type shared by validation, upstream calls and the HTTP layer."""
from __future__ import annotations


class GatewayError(Exception):
    """An error that maps directly onto an HTTP response.

    ``code`` is a stable machine-readable identifier the mobile app can switch
    on; ``message`` is for humans and logs.
    """

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        details: list[str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or []

    def to_dict(self) -> dict:
        return {"error": {"code": self.code, "message": self.message, "details": self.details}}
