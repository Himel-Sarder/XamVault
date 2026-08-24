"""Rate limiting.

In-memory counters are correct for a single Render instance. When the backend scales to
more than one worker this needs a shared store (``storage_uri="redis://..."``), otherwise
each worker enforces its own quota.
"""

from __future__ import annotations

from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings

limiter = Limiter(
    key_func=get_remote_address,
    enabled=settings.RATE_LIMIT_ENABLED,
    default_limits=[settings.DEFAULT_RATE_LIMIT],
)
