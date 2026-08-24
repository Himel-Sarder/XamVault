"""Phases 14-15 — a teacher marking short answers and code (§21, §22, §43)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from tests.conftest import code_payload, mcq_payload, short_answer_payload


@pytest.fixture
def sat_exam(client, api, auth_headers, teacher, teacher_course, student, enroll,
             make_join_request, db):
    """A published exam of one MCQ, one short answer and one code question, sat and
    submitted by the student. Built through the API so the whole path is exercised."""
    from app.models.exam import Exam

    headers = auth_headers(teacher)
    created = client.post(
        f"{api}/exams",
        headers=headers,
        json={
            "course_id": teacher_course.id,
            "title": "Mixed Paper",
            "start_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
            "duration_minutes": 60,
        },
    ).json()
    exam_id = created["id"]

    for payload in (mcq_payload(marks=5), short_answer_payload(marks=10), code_payload(marks=10)):
        response = client.post(f"{api}/exams/{exam_id}/questions", headers=headers, json=payload)
        assert response.status_code == 201, response.text

    assert client.post(f"{api}/exams/{exam_id}/publish", headers=headers).status_code == 200

    # Open the window so the student can sit it now.
    exam = db.get(Exam, exam_id)
    exam.start_at = datetime.now(UTC) - timedelta(minutes=1)
    exam.expires_at = datetime.now(UTC) + timedelta(minutes=59)
    db.commit()

    enroll(teacher_course, student)
    make_join_request(exam, student, status="approved")

    student_headers = auth_headers(student)
    attempt = client.post(f"{api}/exams/{exam_id}/start", headers=student_headers).json()
    by_type = {question["type"]: question for question in attempt["questions"]}

    # The student's paper carries no answer key, so the correct option is read from the
    # snapshot here - the same place grading reads it.
    from sqlalchemy import select

    from app.models.exam import ExamQuestion

    mcq = by_type["TEXT_MCQ"]
    link = db.execute(
        select(ExamQuestion).where(ExamQuestion.id == mcq["exam_question_id"])
    ).scalar_one()
    correct_option = next(
        option["id"] for option in link.question_snapshot["options"] if option["is_correct"]
    )
    client.post(
        f"{api}/attempts/{attempt['id']}/answers",
        headers=student_headers,
        json={"exam_question_id": mcq["exam_question_id"],
              "selected_option_id": correct_option},
    )
    for kind, text in [
        ("SHORT_ANSWER", "TCP is connection-oriented and reliable; UDP is neither."),
        ("CODE_ANSWER", "int bsearch(int* a, int n, int k) { /* ... */ }"),
    ]:
        client.post(
            f"{api}/attempts/{attempt['id']}/answers",
            headers=student_headers,
            json={"exam_question_id": by_type[kind]["exam_question_id"], "answer_text": text},
        )

    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=student_headers)
    return {"exam_id": exam_id, "attempt_id": attempt["id"], "questions": by_type}


def test_written_answers_wait_for_a_person(client, api, auth_headers, teacher, sat_exam):
    response = client.get(
        f"{api}/attempts/{sat_exam['attempt_id']}/grading", headers=auth_headers(teacher)
    )
    assert response.status_code == 200
    body = response.json()

    # Only the two written questions appear; the MCQ was marked by the machine.
    assert body["awaiting_marks"] == 2
    assert {answer["type"] for answer in body["answers"]} == {"SHORT_ANSWER", "CODE_ANSWER"}
    for answer in body["answers"]:
        assert answer["status"] == "pending"
        assert answer["marks_awarded"] is None
        assert answer["answer_text"]
    code = next(a for a in body["answers"] if a["type"] == "CODE_ANSWER")
    assert code["language"] == "cpp"
    assert "bsearch" in code["answer_text"]


def test_the_result_holds_only_the_automatic_marks_until_grading(
    client, api, auth_headers, teacher, sat_exam
):
    results = client.get(
        f"{api}/exams/{sat_exam['exam_id']}/results", headers=auth_headers(teacher)
    ).json()
    assert len(results) == 1
    assert results[0]["scores"]["mcq"] == 5.0
    assert results[0]["scores"]["short_answer"] == 0.0
    assert results[0]["scores"]["code"] == 0.0
    assert results[0]["total_score"] == 5.0


def test_awarding_marks_updates_the_total(client, api, auth_headers, teacher, sat_exam):
    headers = auth_headers(teacher)
    attempt_id = sat_exam["attempt_id"]
    answers = client.get(f"{api}/attempts/{attempt_id}/grading", headers=headers).json()["answers"]
    short = next(a for a in answers if a["type"] == "SHORT_ANSWER")

    response = client.post(
        f"{api}/attempts/{attempt_id}/answers/{short['answer_id']}/evaluate",
        headers=headers,
        json={"marks_awarded": 8, "feedback": "Good, but mention ordering."},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["marks_awarded"] == 8.0
    assert body["status"] == "evaluated"
    assert body["awaiting_marks"] == 1, "the code answer is still outstanding"
    assert body["total_score"] == 13.0

    results = client.get(f"{api}/exams/{sat_exam['exam_id']}/results", headers=headers).json()
    assert results[0]["scores"]["short_answer"] == 8.0
    assert results[0]["total_score"] == 13.0


def test_marking_everything_clears_the_queue(client, api, auth_headers, teacher, sat_exam):
    headers = auth_headers(teacher)
    attempt_id = sat_exam["attempt_id"]
    answers = client.get(f"{api}/attempts/{attempt_id}/grading", headers=headers).json()["answers"]

    for answer, marks in zip(answers, [8, 10], strict=True):
        client.post(
            f"{api}/attempts/{attempt_id}/answers/{answer['answer_id']}/evaluate",
            headers=headers,
            json={"marks_awarded": marks},
        )

    grading = client.get(f"{api}/attempts/{attempt_id}/grading", headers=headers).json()
    assert grading["awaiting_marks"] == 0

    results = client.get(f"{api}/exams/{sat_exam['exam_id']}/results", headers=headers).json()
    assert results[0]["total_score"] == 23.0
    assert results[0]["percentage"] == 92.0


def test_re_marking_replaces_rather_than_accumulates(
    client, api, auth_headers, teacher, sat_exam
):
    headers = auth_headers(teacher)
    attempt_id = sat_exam["attempt_id"]
    answers = client.get(f"{api}/attempts/{attempt_id}/grading", headers=headers).json()["answers"]
    short = next(a for a in answers if a["type"] == "SHORT_ANSWER")
    url = f"{api}/attempts/{attempt_id}/answers/{short['answer_id']}/evaluate"

    client.post(url, headers=headers, json={"marks_awarded": 9})
    second = client.post(url, headers=headers, json={"marks_awarded": 4})

    # The total is rebuilt from the answers, so a correction cannot drift the score.
    assert second.json()["total_score"] == 9.0


def test_marks_above_the_question_maximum_are_refused(
    client, api, auth_headers, teacher, sat_exam
):
    headers = auth_headers(teacher)
    attempt_id = sat_exam["attempt_id"]
    answers = client.get(f"{api}/attempts/{attempt_id}/grading", headers=headers).json()["answers"]
    short = next(a for a in answers if a["type"] == "SHORT_ANSWER")

    response = client.post(
        f"{api}/attempts/{attempt_id}/answers/{short['answer_id']}/evaluate",
        headers=headers,
        json={"marks_awarded": 50},
    )
    assert response.status_code == 400
    assert response.json()["code"] == "marks_out_of_range"


def test_the_grading_queue_lists_who_still_needs_marking(
    client, api, auth_headers, teacher, student, sat_exam
):
    queue = client.get(
        f"{api}/exams/{sat_exam['exam_id']}/grading", headers=auth_headers(teacher)
    ).json()

    assert len(queue) == 1
    assert queue[0]["student_name"] == student.name
    assert queue[0]["awaiting_marks"] == 2
    assert queue[0]["total_marks"] == 25


def test_another_teacher_cannot_mark_my_students(
    client, api, auth_headers, teacher, other_teacher, sat_exam
):
    attempt_id = sat_exam["attempt_id"]
    answers = client.get(
        f"{api}/attempts/{attempt_id}/grading", headers=auth_headers(teacher)
    ).json()["answers"]
    intruder = auth_headers(other_teacher)

    assert client.get(f"{api}/attempts/{attempt_id}/grading", headers=intruder).status_code == 404
    assert client.get(
        f"{api}/exams/{sat_exam['exam_id']}/grading", headers=intruder
    ).status_code == 404
    assert client.post(
        f"{api}/attempts/{attempt_id}/answers/{answers[0]['answer_id']}/evaluate",
        headers=intruder,
        json={"marks_awarded": 10},
    ).status_code == 404


def test_students_cannot_mark_anything(client, api, auth_headers, teacher, student, sat_exam):
    attempt_id = sat_exam["attempt_id"]
    answers = client.get(
        f"{api}/attempts/{attempt_id}/grading", headers=auth_headers(teacher)
    ).json()["answers"]

    headers = auth_headers(student)
    assert client.get(f"{api}/attempts/{attempt_id}/grading", headers=headers).status_code == 403
    assert client.post(
        f"{api}/attempts/{attempt_id}/answers/{answers[0]['answer_id']}/evaluate",
        headers=headers,
        json={"marks_awarded": 10},
    ).status_code == 403


def test_an_automatically_marked_answer_cannot_be_overridden_here(
    client, api, auth_headers, teacher, sat_exam, db
):
    """The MCQ is absent from the grading queue, and naming its id directly is refused."""
    from sqlalchemy import select

    from app.models.attempt import StudentAnswer

    attempt_id = sat_exam["attempt_id"]
    mcq_link = sat_exam["questions"]["TEXT_MCQ"]["exam_question_id"]
    mcq_answer = db.execute(
        select(StudentAnswer).where(
            StudentAnswer.attempt_id == attempt_id,
            StudentAnswer.exam_question_id == mcq_link,
        )
    ).scalar_one()

    response = client.post(
        f"{api}/attempts/{attempt_id}/answers/{mcq_answer.id}/evaluate",
        headers=auth_headers(teacher),
        json={"marks_awarded": 0},
    )
    assert response.status_code == 400
    assert response.json()["code"] == "not_manually_graded"


def test_a_written_answer_cannot_be_answered_by_choosing(
    client, api, auth_headers, teacher, teacher_course, student, enroll, make_join_request, db
):
    """And the reverse: the server enforces which shape each question takes."""
    from app.models.exam import Exam

    headers = auth_headers(teacher)
    created = client.post(
        f"{api}/exams",
        headers=headers,
        json={
            "course_id": teacher_course.id,
            "title": "Shapes",
            "start_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
            "duration_minutes": 60,
        },
    ).json()
    client.post(f"{api}/exams/{created['id']}/questions", headers=headers,
                json=short_answer_payload())
    client.post(f"{api}/exams/{created['id']}/questions", headers=headers, json=mcq_payload())
    client.post(f"{api}/exams/{created['id']}/publish", headers=headers)

    exam = db.get(Exam, created["id"])
    exam.start_at = datetime.now(UTC) - timedelta(minutes=1)
    exam.expires_at = datetime.now(UTC) + timedelta(minutes=59)
    db.commit()
    enroll(teacher_course, student)
    make_join_request(exam, student, status="approved")

    student_headers = auth_headers(student)
    attempt = client.post(
        f"{api}/exams/{created['id']}/start", headers=student_headers
    ).json()
    by_type = {question["type"]: question for question in attempt["questions"]}

    typing_at_an_mcq = client.post(
        f"{api}/attempts/{attempt['id']}/answers",
        headers=student_headers,
        json={"exam_question_id": by_type["TEXT_MCQ"]["exam_question_id"],
              "answer_text": "I'd like to write instead"},
    )
    assert typing_at_an_mcq.status_code == 400

    choosing_at_a_written_question = client.post(
        f"{api}/attempts/{attempt['id']}/answers",
        headers=student_headers,
        json={"exam_question_id": by_type["SHORT_ANSWER"]["exam_question_id"],
              "selected_option_id": 1},
    )
    assert choosing_at_a_written_question.status_code == 400
