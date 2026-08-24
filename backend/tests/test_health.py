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
