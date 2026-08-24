"""Answering during an attempt, and the timer that governs it."""

from __future__ import annotations

import pytest


@pytest.fixture
def attempt(client, api, auth_headers, student, approved_exam):
    headers = auth_headers(student)
    response = client.post(f"{api}/exams/{approved_exam.id}/start", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def _answer(client, api, headers, attempt_id, question_id, option_id):
    return client.post(
        f"{api}/attempts/{attempt_id}/answers",
        headers=headers,
        json={"exam_question_id": question_id, "selected_option_id": option_id},
    )


def test_saving_an_answer_records_it_and_resyncs_the_clock(
    client, api, auth_headers, student, attempt
):
    headers = auth_headers(student)
    question = attempt["questions"][0]

    response = _answer(
        client, api, headers, attempt["id"], question["exam_question_id"],
        question["options"][0]["id"],
    )
    assert response.status_code == 200
    body = response.json()
    assert body["selected_option_id"] == question["options"][0]["id"]
    assert body["answered_count"] == 1
    # Every save carries the authoritative remaining time back to the client.
    assert body["remaining_seconds"] > 0


def test_an_answer_can_be_changed_and_cleared(client, api, auth_headers, student, attempt):
    headers = auth_headers(student)
    question = attempt["questions"][0]
    first, second = question["options"][0]["id"], question["options"][1]["id"]

    _answer(client, api, headers, attempt["id"], question["exam_question_id"], first)
    changed = _answer(client, api, headers, attempt["id"], question["exam_question_id"], second)
    assert changed.json()["selected_option_id"] == second

    cleared = _answer(client, api, headers, attempt["id"], question["exam_question_id"], None)
    assert cleared.json()["selected_option_id"] is None
    assert cleared.json()["answered_count"] == 0


def test_an_option_from_another_question_is_rejected(
    client, api, auth_headers, student, attempt
):
    headers = auth_headers(student)
    question = attempt["questions"][0]
    response = _answer(
        client, api, headers, attempt["id"], question["exam_question_id"], 999_999
    )
    assert response.status_code == 400


def test_a_question_outside_this_attempt_is_rejected(
    client, api, auth_headers, student, attempt
):
    response = _answer(client, api, auth_headers(student), attempt["id"], 999_999, 1)
    assert response.status_code == 404


def test_answers_survive_a_restart(client, api, auth_headers, student, attempt):
    headers = auth_headers(student)
    question = attempt["questions"][0]
    chosen = question["options"][1]["id"]
    _answer(client, api, headers, attempt["id"], question["exam_question_id"], chosen)

    # Exactly what the app does after a crash: re-read the attempt (§60).
    restored = client.get(f"{api}/attempts/{attempt['id']}", headers=headers).json()
    assert restored["questions"][0]["selected_option_id"] == chosen
    assert restored["answered_count"] == 1
    assert restored["status"] == "active"


def test_another_student_cannot_read_or_answer_my_attempt(
    client, api, auth_headers, other_student, attempt
):
    headers = auth_headers(other_student)
    question = attempt["questions"][0]

    assert client.get(f"{api}/attempts/{attempt['id']}", headers=headers).status_code == 404
    assert _answer(
        client, api, headers, attempt["id"], question["exam_question_id"],
        question["options"][0]["id"],
    ).status_code == 404


def test_a_teacher_cannot_use_the_attempt_routes(client, api, auth_headers, teacher, attempt):
    assert client.get(f"{api}/attempts/{attempt['id']}", headers=auth_headers(teacher)).status_code == 403


def test_the_paper_never_carries_the_answer_key(client, api, auth_headers, student, attempt):
    response = client.get(f"{api}/attempts/{attempt['id']}", headers=auth_headers(student))
    assert "is_correct" not in response.text
    for question in response.json()["questions"]:
        for option in question["options"]:
            assert set(option) == {"id", "option_text", "option_image_url"}


def test_an_expired_attempt_is_auto_submitted_on_read(
    client, api, auth_headers, student, attempt, expire_attempt
):
    expire_attempt(attempt["id"])
    headers = auth_headers(student)

    body = client.get(f"{api}/attempts/{attempt['id']}", headers=headers).json()
    assert body["status"] == "auto_submitted"
    assert body["remaining_seconds"] == 0
    assert body["submitted_at"] is not None


def test_an_expired_attempt_accepts_no_more_answers(
    client, api, auth_headers, student, attempt, expire_attempt
):
    expire_attempt(attempt["id"])
    question = attempt["questions"][0]

    response = _answer(
        client, api, auth_headers(student), attempt["id"],
        question["exam_question_id"], question["options"][0]["id"],
    )
    assert response.status_code == 409
    assert response.json()["code"] == "attempt_closed"


def test_the_remaining_time_comes_from_the_server_not_the_client(
    client, api, auth_headers, student, attempt, expire_attempt
):
    # Whatever the device believes, the stored deadline decides.
    expire_attempt(attempt["id"], seconds_ago=1)
    body = client.get(f"{api}/attempts/{attempt['id']}", headers=auth_headers(student)).json()
    assert body["remaining_seconds"] == 0


def test_the_sweep_closes_attempts_nobody_came_back_to(
    client, api, auth_headers, student, attempt, expire_attempt, db
):
    """The backstop for a device that died mid-exam and never asked the server again."""
    from app.services.attempt_service import AttemptService

    expire_attempt(attempt["id"])

    closed = AttemptService(db).sweep_expired()
    assert closed == 1

    body = client.get(f"{api}/attempts/{attempt['id']}", headers=auth_headers(student)).json()
    assert body["status"] == "auto_submitted"

    # Running it again finds nothing left to do.
    assert AttemptService(db).sweep_expired() == 0
