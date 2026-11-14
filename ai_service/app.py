"""Vercel entrypoint. Vercel looks for app.py, index.py or server.py and an `app` variable."""
from api import app  # noqa: F401
