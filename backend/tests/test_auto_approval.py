"""Admitting anyone enrolled, instead of one request at a time.

Manual approval stays the default. A teacher deciding who is in the room is the safer
position, so turning that off has to be a deliberate act rather than something a
migration or a default does on their behalf.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest


@pytest.fixture
def open_exam(client, api, auth_headers, teacher, teacher_course, student, enroll, make_exam):
    """A published exam, open now, on a course the student is enrolled in."""
    enroll(teacher_course, student)
    exam = make_exam(
        teacher, teacher_course, start_at=datetime.now(UTC) - timedelta(minutes=1)
    )
    headers = auth_headers(teacher)
    client.post(
        f"{api}/exams/{exam.id}/questions",
        headers=headers,
        json={"type": "SHORT_ANSWER", "question_text": "Explain.", "marks": 5},
    )
    assert client.post(f"{api}/exams/{exam.id}/publish", headers=headers).status_code == 200
    return exam


def _set_auto_approve(client, api, auth_headers, teacher, exam, value):
    return client.put(
        f"{api}/exams/{exam.id}/settings",
        headers=auth_headers(teacher),
        json={"auto_approve_join": value},
    )


def test_manual_approval_is_the_default(client, api, auth_headers, teacher, student, open_exam):
    """Nothing changes for an exam whose teacher never touched the setting."""
    response = client.post(f"{api}/exams/{open_exam.id}/start", headers=auth_headers(student))

    assert response.status_code == 403
    assert response.json()["code"] == "not_approved"


def test_with_auto_approval_an_enrolled_student_just_starts(
    client, api, auth_headers, teacher, student, open_exam
):
    assert _set_auto_approve(client, api, auth_headers, teacher, open_exam, True).status_code == 200

    response = client.post(f"{api}/exams/{open_exam.id}/start", headers=auth_headers(student))

    assert response.status_code == 200, response.text


def test_enrolment_is_still_required(
    client, api, auth_headers, teacher, other_student, open_exam
):
    """Auto-approval removes the second gate, not the first.

    An exam nobody has to be approved for is still an exam only its own course can sit.
    """
    _set_auto_approve(client, api, auth_headers, teacher, open_exam, True)

    response = client.post(
        f"{api}/exams/{open_exam.id}/start", headers=auth_headers(other_student)
    )

    assert response.status_code == 404, "a stranger learns nothing about the exam"


def test_a_rejected_student_stays_rejected(
    client, api, auth_headers, teacher, student, open_exam, make_join_request
):
    """Opening the doors is not a licence to readmit somebody turned away by hand."""
    make_join_request(open_exam, student, status="rejected")
    _set_auto_approve(client, api, auth_headers, teacher, open_exam, True)

    response = client.post(f"{api}/exams/{open_exam.id}/start", headers=auth_headers(student))

    assert response.status_code == 403
    assert response.json()["code"] == "not_approved"


def test_the_student_is_not_offered_a_request_they_do_not_need(
    client, api, auth_headers, teacher, student, open_exam
):
    _set_auto_approve(client, api, auth_headers, teacher, open_exam, True)

    view = client.get(f"{api}/exams/{open_exam.id}", headers=auth_headers(student)).json()

    assert view["admits_anyone_enrolled"] is True
    assert view["can_request_join"] is False


def test_a_manual_exam_still_offers_the_request(
    client, api, auth_headers, teacher, student, open_exam
):
    view = client.get(f"{api}/exams/{open_exam.id}", headers=auth_headers(student)).json()

    assert view["admits_anyone_enrolled"] is False
    assert view["can_request_join"] is True


def test_turning_it_back_off_restores_the_gate(
    client, api, auth_headers, teacher, student, open_exam
):
    _set_auto_approve(client, api, auth_headers, teacher, open_exam, True)
    _set_auto_approve(client, api, auth_headers, teacher, open_exam, False)

    response = client.post(f"{api}/exams/{open_exam.id}/start", headers=auth_headers(student))

    assert response.status_code == 403


def test_only_the_exam_owner_may_change_it(
    client, api, auth_headers, other_teacher, open_exam
):
    response = client.put(
        f"{api}/exams/{open_exam.id}/settings",
        headers=auth_headers(other_teacher),
        json={"auto_approve_join": True},
    )
    assert response.status_code == 404


def test_the_paper_itself_stays_frozen_after_publish(
    client, api, auth_headers, teacher, open_exam
):
    """Admission is changeable; shuffling is not.

    Two students must not sit measurably different exams because a setting moved
    between their sittings.
    """
    response = client.put(
        f"{api}/exams/{open_exam.id}/settings",
        headers=auth_headers(teacher),
        json={"shuffle_questions": True},
    )

    assert response.status_code == 409
    assert response.json()["code"] == "exam_not_editable"


def test_admission_alongside_a_frozen_field_is_refused_whole(
    client, api, auth_headers, teacher, open_exam
):
    """No half-applied writes: if one field is refused, none of them land."""
    response = client.put(
        f"{api}/exams/{open_exam.id}/settings",
        headers=auth_headers(teacher),
        json={"auto_approve_join": True, "shuffle_questions": True},
    )
    assert response.status_code == 409

    view = client.get(f"{api}/exams/{open_exam.id}", headers=auth_headers(teacher)).json()
    assert view["settings"]["auto_approve_join"] is False
