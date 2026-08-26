"""FastAPI application factory and wiring."""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from app.core.config import settings
from app.core.exceptions import AppError, ValidationIssuesError
from app.core.rate_limit import limiter
from app.middleware import RequestContextMiddleware, SecurityHeadersMiddleware
from app.routers import api_router
from app.routers import health as health_router
from app.routers import media

logger = logging.getLogger("uniexam")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
    )
    # Raises if production is misconfigured (weak JWT secret, SQLite URL, no CORS list).
    settings.validate_for_runtime()
    logger.info("%s %s starting in %s mode", settings.PROJECT_NAME, settings.VERSION, settings.ENV)
    yield
    logger.info("%s shutting down", settings.PROJECT_NAME)


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.PROJECT_NAME,
        version=settings.VERSION,
        description="Secure university examination platform.",
        lifespan=lifespan,
        # Interactive docs are a development convenience, not a production endpoint.
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None if settings.is_production else "/redoc",
        openapi_url=None if settings.is_production else "/openapi.json",
    )

    # --- middleware (added last == outermost) ---
    app.state.limiter = limiter
    app.add_middleware(SlowAPIMiddleware)
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
            expose_headers=["X-Request-ID"],
        )
    app.add_middleware(SecurityHeadersMiddleware, hsts=settings.is_production)
    app.add_middleware(RequestContextMiddleware)

    # --- exception handlers ---
    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
        headers = (
            {"WWW-Authenticate": "Bearer"} if exc.status_code == 401 else None
        )
        content: dict[str, object] = {"detail": exc.message, "code": exc.code}
        if isinstance(exc, ValidationIssuesError):
            content["issues"] = exc.issues
        return JSONResponse(status_code=exc.status_code, content=content, headers=headers)

    @app.exception_handler(RateLimitExceeded)
    async def handle_rate_limit(request: Request, exc: RateLimitExceeded) -> JSONResponse:
        return JSONResponse(
            status_code=429,
            content={"detail": "Too many requests. Please slow down.", "code": "rate_limited"},
        )

    # --- uploaded files ---
    # Served from the database by app/routers/media.py, in every environment.
    #
    # This used to be a StaticFiles mount guarded by `if not settings.is_production`,
    # on the assumption that production would have object storage by now. It does not,
    # so the guard meant every question image returned 404 on the deployed app while
    # working perfectly in development -- the worst shape a bug can take. Dev and
    # production now take the same path.

    # --- routes ---
    app.include_router(health_router.router)
    app.include_router(media.router)
    app.include_router(api_router)

    @app.get("/", include_in_schema=False)
    def root() -> dict[str, str]:
        return {
            "name": settings.PROJECT_NAME,
            "version": settings.VERSION,
            "api": settings.API_V1_PREFIX,
        }

    return app


app = create_app()
