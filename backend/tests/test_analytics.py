"""Phase 17 — exam and question analytics (§45, §46)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.models.enums import UserRole
from app.models.exam import Exam, ExamQuestion
from tests.conftest import mcq_payload, short_answer_payload


@pytest.fixture
def cohort(client, api, auth_headers, teacher, teacher_course, make_user, enroll,
           make_join_request, db):
    """A published exam of two MCQs and one short answer, sat by three students with
    deliberately different outcomes."""
    headers = auth_headers(teacher)
    exam_id = client.post(
        f"{api}/exams",
        headers=headers,
        json={
            "course_id": teacher_course.id,
            "title": "Analytics Paper",
            "start_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
            "duration_minutes": 60,
        },
    ).json()["id"]

    for payload in (
        mcq_payload(text="Q1", marks=10),
        mcq_payload(text="Q2", marks=10),
        short_answer_payload(text="Q3 explain", marks=10),
    ):
        client.post(f"{api}/exams/{exam_id}/questions", headers=headers, json=payload)
    client.post(f"{api}/exams/{exam_id}/publish", headers=headers)

    exam = db.get(Exam, exam_id)
    exam.start_at = datetime.now(UTC) - timedelta(minutes=1)
    exam.expires_at = datetime.now(UTC) + timedelta(minutes=59)
    db.commit()

    links = db.execute(
        select(ExamQuestion).where(ExamQuestion.exam_id == exam_id)
        .order_by(ExamQuestion.display_order)
    ).scalars().all()

    def option(link, correct):
        return next(
            o["id"] for o in link.question_snapshot["options"] if o["is_correct"] is correct
        )

    # Student A: both MCQs right. B: first right, second wrong. C: skips everything.
    plans = [
        ("2026A", [(links[0], True), (links[1], True)], "A full answer."),
        ("2026B", [(links[0], True), (links[1], False)], "A partial answer."),
        ("2026C", [], None),
    ]
    for login, choices, text in plans:
        person = make_user(UserRole.STUDENT, login_id=login)
        enroll(teacher_course, person)
        make_join_request(exam, person, status="approved")
        student_headers = auth_headers(person)
        attempt = client.post(f"{api}/exams/{exam_id}/start", headers=student_headers).json()
        for link, correct in choices:
            client.post(
                f"{api}/attempts/{attempt['id']}/answers",
                headers=student_headers,
                json={"exam_question_id": link.id, "selected_option_id": option(link, correct)},
            )
        if text:
            client.post(
                f"{api}/attempts/{attempt['id']}/answers",
                headers=student_headers,
                json={"exam_question_id": links[2].id, "answer_text": text},
            )
        client.post(f"{api}/attempts/{attempt['id']}/submit", headers=student_headers)

    return {"exam_id": exam_id, "links": links}


def test_the_cohort_is_counted(client, api, auth_headers, teacher, cohort):
    body = client.get(
        f"{api}/exams/{cohort['exam_id']}/analytics", headers=auth_headers(teacher)
    ).json()

    assert body["cohort"]["approved"] == 3
    assert body["cohort"]["submitted"] == 3
    assert body["cohort"]["in_progress"] == 0
    assert body["cohort"]["absent"] == 0


def test_scores_reflect_the_automatic_marks_so_far(
    client, api, auth_headers, teacher, cohort
):
    body = client.get(
        f"{api}/exams/{cohort['exam_id']}/analytics", headers=auth_headers(teacher)
    ).json()

    # Out of 30: A scored 20, B scored 10, C scored 0 — the short answer is unmarked.
    assert body["total_marks"] == 30
    assert body["scores"]["highest"] == pytest.approx(66.7, abs=0.1)
    assert body["scores"]["lowest"] == 0.0
    assert body["scores"]["median"] == pytest.approx(33.3, abs=0.1)


def test_the_pass_threshold_is_supplied_not_assumed(
    client, api, auth_headers, teacher, cohort
):
    """The platform does not know a university's pass mark, so it is a parameter."""
    headers = auth_headers(teacher)
    url = f"{api}/exams/{cohort['exam_id']}/analytics"

    lenient = client.get(url, headers=headers, params={"pass_percentage": 30}).json()
    assert lenient["pass_percentage"] == 30.0
    assert lenient["passed"] == 2
    assert lenient["failed"] == 1

    strict = client.get(url, headers=headers, params={"pass_percentage": 90}).json()
    assert strict["passed"] == 0
    assert strict["failed"] == 3
    assert strict["pass_rate"] == 0.0


def test_the_distribution_places_every_submission(
    client, api, auth_headers, teacher, cohort
):
    body = client.get(
        f"{api}/exams/{cohort['exam_id']}/analytics", headers=auth_headers(teacher)
    ).json()

    buckets = {bucket["label"]: bucket["count"] for bucket in body["distribution"]}
    assert sum(buckets.values()) == 3, "every submission lands in exactly one band"
    assert buckets["0-20%"] == 1, "the student who skipped everything"
    assert buckets["61-80%"] == 1, "the student who got both right"


def test_question_accuracy_shows_which_question_was_hard(
    client, api, auth_headers, teacher, cohort
):
    body = client.get(
        f"{api}/exams/{cohort['exam_id']}/analytics", headers=auth_headers(teacher)
    ).json()
    questions = {q["position"]: q for q in body["questions"]}

    # Q1: two right, one skipped. Q2: one right, one wrong, one skipped.
    assert questions[1]["correct"] == 2
    assert questions[1]["wrong"] == 0
    assert questions[1]["skipped"] == 1
    assert questions[1]["correct_rate"] == pytest.approx(66.7, abs=0.1)

    assert questions[2]["correct"] == 1
    assert questions[2]["wrong"] == 1
    assert questions[2]["skipped"] == 1


def test_a_written_question_reports_marks_not_accuracy(
    client, api, auth_headers, teacher, cohort
):
    body = client.get(
        f"{api}/exams/{cohort['exam_id']}/analytics", headers=auth_headers(teacher)
    ).json()
    written = next(q for q in body["questions"] if q["type"] == "SHORT_ANSWER")

    # "Correct" is meaningless for prose, so it is absent rather than guessed at.
    assert written["is_auto_marked"] is False
    assert written["correct"] is None
    assert written["correct_rate"] is None
    assert written["awaiting_marks"] == 2, "two students wrote something"
    assert written["average_marks"] is None, "nothing marked yet"


def test_marking_feeds_back_into_the_figures(client, api, auth_headers, teacher, cohort):
    headers = auth_headers(teacher)
    queue = client.get(f"{api}/exams/{cohort['exam_id']}/grading", headers=headers).json()
    for entry in queue:
        answers = client.get(
            f"{api}/attempts/{entry['attempt_id']}/grading", headers=headers
        ).json()["answers"]
        for answer in answers:
            if answer["answer_id"] is not None:
                client.post(
                    f"{api}/attempts/{entry['attempt_id']}/answers/"
                    f"{answer['answer_id']}/evaluate",
                    headers=headers,
                    json={"marks_awarded": 6},
                )

    body = client.get(f"{api}/exams/{cohort['exam_id']}/analytics", headers=headers).json()
    written = next(q for q in body["questions"] if q["type"] == "SHORT_ANSWER")
    assert written["awaiting_marks"] == 0
    assert written["average_marks"] == 6.0
    assert body["scores"]["highest"] == pytest.approx(86.7, abs=0.1)


def test_an_exam_nobody_has_sat_reports_nothing_rather_than_zero(
    client, api, auth_headers, teacher, teacher_course, make_published_exam
):
    exam = make_published_exam(teacher, teacher_course)
    body = client.get(
        f"{api}/exams/{exam.id}/analytics", headers=auth_headers(teacher)
    ).json()

    # 0% would read as "everyone failed"; null reads as "nobody has sat it".
    assert body["scores"]["average"] is None
    assert body["scores"]["highest"] is None
    assert body["pass_rate"] is None
    assert body["cohort"]["submitted"] == 0
    assert sum(bucket["count"] for bucket in body["distribution"]) == 0


def test_students_who_never_started_are_counted_absent(
    client, api, auth_headers, teacher, teacher_course, student, make_published_exam,
    enroll, make_join_request,
):
    exam = make_published_exam(teacher, teacher_course)
    enroll(teacher_course, student)
    make_join_request(exam, student, status="approved")

    body = client.get(
        f"{api}/exams/{exam.id}/analytics", headers=auth_headers(teacher)
    ).json()
    assert body["cohort"]["approved"] == 1
    assert body["cohort"]["absent"] == 1
    assert body["cohort"]["submitted"] == 0


def test_another_teacher_cannot_read_my_analytics(
    client, api, auth_headers, other_teacher, cohort
):
    response = client.get(
        f"{api}/exams/{cohort['exam_id']}/analytics", headers=auth_headers(other_teacher)
    )
    assert response.status_code == 404


def test_students_cannot_read_analytics(client, api, auth_headers, student, cohort):
    response = client.get(
        f"{api}/exams/{cohort['exam_id']}/analytics", headers=auth_headers(student)
    )
    assert response.status_code == 403


def test_an_absurd_pass_threshold_is_rejected(client, api, auth_headers, teacher, cohort):
    response = client.get(
        f"{api}/exams/{cohort['exam_id']}/analytics",
        headers=auth_headers(teacher),
        params={"pass_percentage": 150},
    )
    assert response.status_code == 422
