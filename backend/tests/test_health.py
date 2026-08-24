from __future__ import annotations


def test_health_reports_ok_and_database(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["database"] == "ok"


def test_root_advertises_api_prefix(client, api):
    response = client.get("/")
    assert response.status_code == 200
    assert response.json()["api"] == api


def test_security_headers_are_present(client):
    response = client.get("/health")
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"
    assert response.headers["X-Request-ID"]


def test_a_mobile_only_production_config_starts():
    """Empty CORS_ORIGINS means no browser origin is allowed — the safe default.

    A native client sends no Origin header, so requiring a value here would block a
    legitimate mobile-only deployment for no security gain.
    """
    from app.core.config import Settings

    settings = Settings(
        ENV="production",
        DATABASE_URL="postgresql://u:p@db.example.com/uniexam",
        JWT_SECRET_KEY="a-long-enough-generated-production-secret-value",
        CORS_ORIGINS="",
    )
    settings.validate_for_runtime()  # must not raise


def test_production_still_refuses_a_weak_secret_or_sqlite():
    import pytest

    from app.core.config import Settings

    settings = Settings(
        ENV="production",
        DATABASE_URL="sqlite:///./local.db",
        JWT_SECRET_KEY="short",
        CORS_ORIGINS="https://example.edu",
    )
    with pytest.raises(RuntimeError) as failure:
        settings.validate_for_runtime()

    message = str(failure.value)
    assert "JWT_SECRET_KEY" in message
    assert "PostgreSQL" in message
