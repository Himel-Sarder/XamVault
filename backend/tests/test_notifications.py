"""Phase 19 — in-app notifications (§61)."""

from __future__ import annotations

from datetime import timedelta

from app.models.enums import UserRole
from tests.conftest import mcq_payload


def _inbox(client, api, auth_headers, person, **params):
    return client.get(f"{api}/notifications", headers=auth_headers(person), params=params).json()


def test_publishing_an_exam_tells_the_enrolled_students(
    client, api, auth_headers, teacher, teacher_course, student, other_student,
    make_user, enroll, make_exam,
):
    enroll(teacher_course, student)
    enroll(teacher_course, other_student)
    outsider = make_user(UserRole.STUDENT, login_id="20269999")

    exam = make_exam(teacher, teacher_course, title="Mid Term Quiz")
    headers = auth_headers(teacher)
    client.post(f"{api}/exams/{exam.id}/questions", headers=headers, json=mcq_payload())
    assert client.post(f"{api}/exams/{exam.id}/publish", headers=headers).status_code == 200

    for person in (student, other_student):
        inbox = _inbox(client, api, auth_headers, person)
        assert inbox["total"] == 1
        item = inbox["items"][0]
        assert item["category"] == "exam_published"
        assert "Mid Term Quiz" in item["title"]
        assert item["payload"] == {"exam_id": exam.id}
        assert item["is_read"] is False

    # Somebody not enrolled in the course hears nothing.
    assert _inbox(client, api, auth_headers, outsider)["total"] == 0


def test_a_draft_exam_tells_nobody(
    client, api, auth_headers, teacher, teacher_course, student, enroll, make_exam
):
    enroll(teacher_course, student)
    make_exam(teacher, teacher_course)

    assert _inbox(client, api, auth_headers, student)["total"] == 0


def test_a_join_request_reaches_the_teacher(
    client, api, auth_headers, teacher, student, approved_exam
):
    """The approved_exam fixture seeds an approval directly, so ask fresh here."""
    inbox = _inbox(client, api, auth_headers, teacher)
    before = inbox["total"]

    other = client.post(
        f"{api}/exams/{approved_exam.id}/join-request", headers=auth_headers(student)
    )
    # Already approved, so a second request is refused and nothing new is announced.
    assert other.status_code == 409
    assert _inbox(client, api, auth_headers, teacher)["total"] == before


def test_asking_and_being_approved_notifies_both_sides(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam,
    enroll,
):
    enroll(teacher_course, student)
    exam = make_published_exam(teacher, teacher_course, title="Final Paper")

    request_id = client.post(
        f"{api}/exams/{exam.id}/join-request", headers=auth_headers(student)
    ).json()["id"]

    teacher_inbox = _inbox(client, api, auth_headers, teacher)
    assert teacher_inbox["items"][0]["category"] == "join_request_received"
    assert student.name in teacher_inbox["items"][0]["body"]

    client.post(f"{api}/join-requests/{request_id}/approve", headers=auth_headers(teacher))

    student_inbox = _inbox(client, api, auth_headers, student)
    assert student_inbox["items"][0]["category"] == "join_request_approved"
    assert "Final Paper" in student_inbox["items"][0]["body"]


def test_a_rejection_says_the_student_may_ask_again(
    client, api, auth_headers, teacher, student, teacher_course, make_published_exam, enroll
):
    enroll(teacher_course, student)
    exam = make_published_exam(teacher, teacher_course)
    request_id = client.post(
        f"{api}/exams/{exam.id}/join-request", headers=auth_headers(student)
    ).json()["id"]

    client.post(f"{api}/join-requests/{request_id}/reject", headers=auth_headers(teacher))

    latest = _inbox(client, api, auth_headers, student)["items"][0]
    assert latest["category"] == "join_request_rejected"
    assert "ask again" in latest["body"]


def test_bulk_approval_notifies_everyone_it_approved(
    client, api, auth_headers, teacher, teacher_course, make_user, enroll,
    make_published_exam,
):
    exam = make_published_exam(teacher, teacher_course)
    students = []
    for index in range(3):
        person = make_user(UserRole.STUDENT, login_id=f"2026300{index}")
        enroll(teacher_course, person)
        client.post(f"{api}/exams/{exam.id}/join-request", headers=auth_headers(person))
        students.append(person)

    client.post(
        f"{api}/exams/{exam.id}/join-requests/approve-all", headers=auth_headers(teacher)
    )

    for person in students:
        categories = [
            item["category"] for item in _inbox(client, api, auth_headers, person)["items"]
        ]
        assert "join_request_approved" in categories


def test_submitting_tells_the_teacher(client, api, auth_headers, teacher, student, approved_exam):
    headers = auth_headers(student)
    attempt = client.post(f"{api}/exams/{approved_exam.id}/start", headers=headers).json()
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)

    latest = _inbox(client, api, auth_headers, teacher)["items"][0]
    assert latest["category"] == "exam_submitted"
    assert student.name in latest["body"]
    assert "time ran out" not in latest["body"]


def test_an_auto_submission_says_the_time_ran_out(
    client, api, auth_headers, teacher, student, approved_exam, expire_attempt
):
    headers = auth_headers(student)
    attempt = client.post(f"{api}/exams/{approved_exam.id}/start", headers=headers).json()
    expire_attempt(attempt["id"])
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)

    latest = _inbox(client, api, auth_headers, teacher)["items"][0]
    assert latest["category"] == "exam_submitted"
    assert "time ran out" in latest["body"]


def test_releasing_results_tells_the_students(
    client, api, auth_headers, teacher, student, approved_exam
):
    headers = auth_headers(student)
    attempt = client.post(f"{api}/exams/{approved_exam.id}/start", headers=headers).json()
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)

    client.post(
        f"{api}/exams/{approved_exam.id}/results/publish", headers=auth_headers(teacher)
    )

    latest = _inbox(client, api, auth_headers, student)["items"][0]
    assert latest["category"] == "result_published"
    assert latest["payload"] == {"exam_id": approved_exam.id}


def test_releasing_twice_does_not_announce_twice(
    client, api, auth_headers, teacher, student, approved_exam
):
    headers = auth_headers(student)
    attempt = client.post(f"{api}/exams/{approved_exam.id}/start", headers=headers).json()
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)
    teacher_headers = auth_headers(teacher)

    client.post(f"{api}/exams/{approved_exam.id}/results/publish", headers=teacher_headers)
    second = client.post(
        f"{api}/exams/{approved_exam.id}/results/publish", headers=teacher_headers
    )
    assert second.status_code == 409

    released = [
        item for item in _inbox(client, api, auth_headers, student)["items"]
        if item["category"] == "result_published"
    ]
    assert len(released) == 1, "telling someone twice would be noise"


def test_my_inbox_is_mine_alone(
    client, api, auth_headers, teacher, student, other_student, teacher_course,
    make_published_exam, enroll,
):
    enroll(teacher_course, student)
    make_published_exam(teacher, teacher_course)
    client.post(
        f"{api}/exams/{make_published_exam(teacher, teacher_course).id}/join-request",
        headers=auth_headers(student),
    )

    # Scoped inside the query, so there is no id to ask for and no filter to forget.
    assert _inbox(client, api, auth_headers, other_student)["total"] == 0


def test_reading_one_notification(client, api, auth_headers, teacher, student, approved_exam):
    headers = auth_headers(student)
    attempt = client.post(f"{api}/exams/{approved_exam.id}/start", headers=headers).json()
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)
    client.post(
        f"{api}/exams/{approved_exam.id}/results/publish", headers=auth_headers(teacher)
    )

    unread = client.get(f"{api}/notifications/unread-count", headers=headers).json()
    assert unread["unread"] >= 1

    first = _inbox(client, api, auth_headers, student)["items"][0]
    response = client.post(f"{api}/notifications/{first['id']}/read", headers=headers)
    assert response.status_code == 200
    assert response.json()["is_read"] is True
    assert response.json()["read_at"] is not None

    after = client.get(f"{api}/notifications/unread-count", headers=headers).json()
    assert after["unread"] == unread["unread"] - 1


def test_reading_an_already_read_notification_is_harmless(
    client, api, auth_headers, teacher, teacher_course, student, enroll, make_exam
):
    enroll(teacher_course, student)
    exam = make_exam(teacher, teacher_course)
    client.post(f"{api}/exams/{exam.id}/questions", headers=auth_headers(teacher), json=mcq_payload())
    client.post(f"{api}/exams/{exam.id}/publish", headers=auth_headers(teacher))

    headers = auth_headers(student)
    first = _inbox(client, api, auth_headers, student)["items"][0]
    first_read = client.post(f"{api}/notifications/{first['id']}/read", headers=headers).json()
    again = client.post(f"{api}/notifications/{first['id']}/read", headers=headers).json()

    assert again["is_read"] is True
    assert again["read_at"] == first_read["read_at"], "the original moment is kept"


def test_marking_everything_read(
    client, api, auth_headers, teacher, teacher_course, student, enroll, make_exam
):
    enroll(teacher_course, student)
    for title in ("First", "Second", "Third"):
        exam = make_exam(teacher, teacher_course, title=title)
        client.post(
            f"{api}/exams/{exam.id}/questions", headers=auth_headers(teacher), json=mcq_payload()
        )
        client.post(f"{api}/exams/{exam.id}/publish", headers=auth_headers(teacher))

    headers = auth_headers(student)
    assert client.get(f"{api}/notifications/unread-count", headers=headers).json()["unread"] == 3

    response = client.post(f"{api}/notifications/read-all", headers=headers)
    assert response.json() == {"updated": 3}
    assert client.get(f"{api}/notifications/unread-count", headers=headers).json()["unread"] == 0

    # Nothing left to do, so a second sweep updates nothing.
    assert client.post(f"{api}/notifications/read-all", headers=headers).json() == {"updated": 0}


def test_the_unread_filter(
    client, api, auth_headers, teacher, teacher_course, student, enroll, make_exam
):
    enroll(teacher_course, student)
    for title in ("First", "Second"):
        exam = make_exam(teacher, teacher_course, title=title)
        client.post(
            f"{api}/exams/{exam.id}/questions", headers=auth_headers(teacher), json=mcq_payload()
        )
        client.post(f"{api}/exams/{exam.id}/publish", headers=auth_headers(teacher))

    headers = auth_headers(student)
    items = _inbox(client, api, auth_headers, student)["items"]
    client.post(f"{api}/notifications/{items[0]['id']}/read", headers=headers)

    assert _inbox(client, api, auth_headers, student)["total"] == 2
    assert _inbox(client, api, auth_headers, student, unread_only=True)["total"] == 1


def test_someone_elses_notification_cannot_be_read(
    client, api, auth_headers, teacher, teacher_course, student, other_student, enroll, make_exam
):
    enroll(teacher_course, student)
    exam = make_exam(teacher, teacher_course)
    client.post(f"{api}/exams/{exam.id}/questions", headers=auth_headers(teacher), json=mcq_payload())
    client.post(f"{api}/exams/{exam.id}/publish", headers=auth_headers(teacher))

    theirs = _inbox(client, api, auth_headers, student)["items"][0]
    response = client.post(
        f"{api}/notifications/{theirs['id']}/read", headers=auth_headers(other_student)
    )
    assert response.status_code == 404


def test_notifications_need_authentication(client, api):
    assert client.get(f"{api}/notifications").status_code == 401
    assert client.get(f"{api}/notifications/unread-count").status_code == 401
    assert client.post(f"{api}/notifications/read-all").status_code == 401


def test_the_newest_notification_comes_first(
    client, api, auth_headers, teacher, teacher_course, student, enroll, make_exam
):
    enroll(teacher_course, student)
    for title in ("Oldest", "Newest"):
        exam = make_exam(teacher, teacher_course, title=title)
        client.post(
            f"{api}/exams/{exam.id}/questions", headers=auth_headers(teacher), json=mcq_payload()
        )
        client.post(f"{api}/exams/{exam.id}/publish", headers=auth_headers(teacher))

    titles = [item["title"] for item in _inbox(client, api, auth_headers, student)["items"]]
    assert "Newest" in titles[0]
