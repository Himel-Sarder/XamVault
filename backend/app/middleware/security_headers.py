"""Response hardening headers.

The API serves JSON only, so the policy can be far stricter than a web app's: nothing is
allowed to load, nothing may frame it, and browsers must not sniff the content type.
"""

from __future__ import annotations

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

BASE_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}

# Swagger UI needs to load its own CSS/JS, so the docs routes get a relaxed policy
# instead of being broken by the API-wide one.
DOCS_PATHS = frozenset({"/docs", "/redoc", "/docs/oauth2-redirect", "/openapi.json"})


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, *, hsts: bool = False) -> None:
        super().__init__(app)
        self.hsts = hsts

    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        for header, value in BASE_HEADERS.items():
            if header == "Content-Security-Policy" and request.url.path in DOCS_PATHS:
                continue
            response.headers.setdefault(header, value)
        if self.hsts:
            response.headers.setdefault(
                "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
            )
        return response
