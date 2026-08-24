"""Phase 12 — the device's event trail (§39), and the limits on what it may claim."""

from __future__ import annotations

import pytest


@pytest.fixture
def attempt(client, api, auth_headers, student, approved_exam):
    response = client.post(
        f"{api}/exams/{approved_exam.id}/start", headers=auth_headers(student)
    )
    assert response.status_code == 200, response.text
    return response.json()


def _report(client, api, headers, attempt_id, *events):
    return client.post(
        f"{api}/attempts/{attempt_id}/security-events",
        headers=headers,
        json={"events": [
            {"event_type": event} if isinstance(event, str) else event for event in events
        ]},
    )


def test_a_device_can_report_what_it_saw(client, api, auth_headers, student, attempt):
    response = _report(
        client, api, auth_headers(student), attempt["id"], "APP_BACKGROUND", "APP_FOREGROUND"
    )

    assert response.status_code == 201
    body = response.json()
    assert [event["event_type"] for event in body] == ["APP_BACKGROUND", "APP_FOREGROUND"]
    assert all(event["attempt_id"] == attempt["id"] for event in body)


def test_the_server_decides_how_serious_an_event_is(
    client, api, auth_headers, student, attempt
):
    """A patched client must not be able to file its own screenshot as harmless."""
    response = _report(
        client,
        api,
        auth_headers(student),
        attempt["id"],
        {"event_type": "SCREENSHOT_ATTEMPT", "severity": "info"},
        {"event_type": "APP_FOREGROUND", "severity": "critical"},
    )

    assert response.status_code == 201
    by_type = {event["event_type"]: event["severity"] for event in response.json()}
    assert by_type["SCREENSHOT_ATTEMPT"] == "critical"
    assert by_type["APP_FOREGROUND"] == "info"


def test_the_server_records_when_not_the_device(client, api, auth_headers, student, attempt):
    from datetime import UTC, datetime

    before = datetime.now(UTC)
    response = _report(
        client,
        api,
        auth_headers(student),
        attempt["id"],
        {"event_type": "APP_BACKGROUND", "occurred_at": "1999-01-01T00:00:00Z"},
    )
    recorded = datetime.fromisoformat(response.json()[0]["occurred_at"])

    # A device claiming a timestamp is making a claim; the row keeps the server's clock.
    assert recorded >= before
    assert recorded.year >= 2026


def test_free_form_context_is_kept(client, api, auth_headers, student, attempt):
    response = _report(
        client,
        api,
        auth_headers(student),
        attempt["id"],
        {"event_type": "APP_BACKGROUND", "metadata": {"away_seconds": 12}},
    )
    assert response.json()[0]["metadata"] == {"away_seconds": 12}


def test_an_unknown_event_type_is_rejected(client, api, auth_headers, student, attempt):
    response = _report(client, api, auth_headers(student), attempt["id"], "CHEATED")
    assert response.status_code == 422


def test_an_empty_batch_is_rejected(client, api, auth_headers, student, attempt):
    response = client.post(
        f"{api}/attempts/{attempt['id']}/security-events",
        headers=auth_headers(student),
        json={"events": []},
    )
    assert response.status_code == 422


def test_events_never_end_the_attempt(client, api, auth_headers, student, attempt):
    """§38: the platform records, it does not accuse or terminate."""
    headers = auth_headers(student)
    for _ in range(5):
        _report(client, api, headers, attempt["id"], "SCREENSHOT_ATTEMPT", "APP_BACKGROUND")

    still_running = client.get(f"{api}/attempts/{attempt['id']}", headers=headers).json()
    assert still_running["status"] == "active"
    assert still_running["remaining_seconds"] > 0


def test_another_student_cannot_file_events_against_my_attempt(
    client, api, auth_headers, other_student, attempt
):
    response = _report(
        client, api, auth_headers(other_student), attempt["id"], "APP_BACKGROUND"
    )
    assert response.status_code == 404


def test_a_finished_attempt_accepts_no_more_events(
    client, api, auth_headers, student, attempt
):
    headers = auth_headers(student)
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)

    response = _report(client, api, headers, attempt["id"], "APP_BACKGROUND")
    assert response.status_code == 409
    assert response.json()["code"] == "attempt_closed"


def test_the_owning_teacher_sees_the_trail(
    client, api, auth_headers, teacher, student, attempt
):
    _report(
        client, api, auth_headers(student), attempt["id"],
        "APP_BACKGROUND", "APP_FOREGROUND", "SCREENSHOT_ATTEMPT",
    )

    report = client.get(
        f"{api}/attempts/{attempt['id']}/security-events", headers=auth_headers(teacher)
    )
    assert report.status_code == 200
    body = report.json()
    assert body["total_events"] == 3
    assert body["warnings"] == 1, "one backgrounding"
    assert body["critical"] == 1, "one screenshot"
    assert body["student_name"] == student.name


def test_another_teacher_cannot_read_the_trail(
    client, api, auth_headers, other_teacher, student, attempt
):
    _report(client, api, auth_headers(student), attempt["id"], "APP_BACKGROUND")
    response = client.get(
        f"{api}/attempts/{attempt['id']}/security-events", headers=auth_headers(other_teacher)
    )
    assert response.status_code == 404


def test_a_student_cannot_read_their_own_trail(client, api, auth_headers, student, attempt):
    _report(client, api, auth_headers(student), attempt["id"], "APP_BACKGROUND")
    response = client.get(
        f"{api}/attempts/{attempt['id']}/security-events", headers=auth_headers(student)
    )
    assert response.status_code == 403


def test_a_flood_of_events_is_capped(client, api, auth_headers, student, attempt):
    from app.services.security_service import MAX_EVENTS_PER_ATTEMPT

    headers = auth_headers(student)
    sent = 0
    while sent < MAX_EVENTS_PER_ATTEMPT:
        batch = ["APP_BACKGROUND"] * 50
        response = _report(client, api, headers, attempt["id"], *batch)
        if response.status_code != 201:
            break
        sent += len(response.json())

    overflow = _report(client, api, headers, attempt["id"], "APP_BACKGROUND")
    assert overflow.status_code == 409
    assert overflow.json()["code"] == "event_limit_reached"
