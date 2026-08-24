"""Phase 11 — per-student question and answer order (§35, §36)."""

from __future__ import annotations

from sqlalchemy import select

from app.models.attempt import ExamAttempt
from app.models.enums import UserRole
from app.models.exam import ExamQuestion

QUESTIONS = 8


def _start(client, api, auth_headers, person, exam):
    return client.post(f"{api}/exams/{exam.id}/start", headers=auth_headers(person)).json()


def _canonical_order(db, exam_id: int) -> list[int]:
    links = db.execute(
        select(ExamQuestion)
        .where(ExamQuestion.exam_id == exam_id)
        .order_by(ExamQuestion.display_order)
    ).scalars().all()
    return [link.id for link in links]


def test_without_shuffling_everyone_gets_the_teachers_order(
    client, api, auth_headers, teacher, student, make_approved_exam, db
):
    exam = make_approved_exam(teacher, student, question_count=QUESTIONS)
    attempt = _start(client, api, auth_headers, student, exam)

    assert [q["exam_question_id"] for q in attempt["questions"]] == _canonical_order(db, exam.id)
    assert [q["position"] for q in attempt["questions"]] == list(range(1, QUESTIONS + 1))


def test_shuffling_reorders_the_paper(
    client, api, auth_headers, teacher, student, make_approved_exam, db
):
    exam = make_approved_exam(
        teacher, student, question_count=QUESTIONS, shuffle_questions=True
    )
    attempt = _start(client, api, auth_headers, student, exam)
    order = [q["exam_question_id"] for q in attempt["questions"]]

    assert sorted(order) == sorted(_canonical_order(db, exam.id)), "same questions"
    # With 8 questions the odds of the shuffle reproducing the original order are 1 in
    # 40320, so this is a stable assertion rather than a flaky one.
    assert order != _canonical_order(db, exam.id)


def test_the_order_is_fixed_once_and_does_not_move_under_the_student(
    client, api, auth_headers, teacher, student, make_approved_exam, db
):
    exam = make_approved_exam(
        teacher, student, question_count=QUESTIONS, shuffle_questions=True, shuffle_answers=True
    )
    headers = auth_headers(student)
    first = _start(client, api, auth_headers, student, exam)

    # Re-reading the attempt - a reconnect, a restart - must give the same paper (§35).
    again = client.get(f"{api}/attempts/{first['id']}", headers=headers).json()
    assert [q["exam_question_id"] for q in again["questions"]] == [
        q["exam_question_id"] for q in first["questions"]
    ]
    for before, after in zip(first["questions"], again["questions"], strict=True):
        assert [o["id"] for o in after["options"]] == [o["id"] for o in before["options"]]


def test_two_students_get_different_papers(
    client, api, auth_headers, teacher, teacher_course, student, make_user, make_approved_exam,
    enroll, make_join_request, db,
):
    exam = make_approved_exam(
        teacher, student, question_count=QUESTIONS, shuffle_questions=True
    )
    classmate = make_user(UserRole.STUDENT, login_id="20269001")
    enroll(teacher_course, classmate)
    make_join_request(exam, classmate, status="approved")

    mine = [q["exam_question_id"] for q in _start(client, api, auth_headers, student, exam)["questions"]]
    theirs = [
        q["exam_question_id"] for q in _start(client, api, auth_headers, classmate, exam)["questions"]
    ]

    assert sorted(mine) == sorted(theirs)
    assert mine != theirs


def test_answer_shuffling_reorders_the_options(
    client, api, auth_headers, teacher, student, make_approved_exam, db
):
    exam = make_approved_exam(
        teacher, student, question_count=QUESTIONS, shuffle_answers=True
    )
    attempt = _start(client, api, auth_headers, student, exam)

    links = {
        link.id: link
        for link in db.execute(
            select(ExamQuestion).where(ExamQuestion.exam_id == exam.id)
        ).scalars().all()
    }
    reordered = 0
    for question in attempt["questions"]:
        original = [
            option["id"]
            for option in links[question["exam_question_id"]].question_snapshot["options"]
        ]
        shown = [option["id"] for option in question["options"]]
        assert sorted(shown) == sorted(original), "same options, different order"
        if shown != original:
            reordered += 1
    assert reordered > 0


def test_the_stored_order_is_option_ids_not_letters(
    client, api, auth_headers, teacher, student, make_approved_exam, db
):
    exam = make_approved_exam(teacher, student, question_count=2, shuffle_answers=True)
    attempt = _start(client, api, auth_headers, student, exam)

    stored = db.execute(
        select(ExamAttempt).where(ExamAttempt.id == attempt["id"])
    ).scalar_one()
    # Letters are meaningless at grading time; ids are what identify a choice (§36).
    for option_ids in stored.option_orders.values():
        assert all(isinstance(option_id, int) for option_id in option_ids)


def test_grading_is_correct_despite_shuffling(
    client, api, auth_headers, teacher, student, make_approved_exam, db
):
    """The real point of storing ids: a shuffled paper must still mark correctly."""
    exam = make_approved_exam(
        teacher,
        student,
        question_count=QUESTIONS,
        shuffle_questions=True,
        shuffle_answers=True,
        show_result_immediately=True,
    )
    headers = auth_headers(student)
    attempt = _start(client, api, auth_headers, student, exam)

    links = {
        link.id: link
        for link in db.execute(
            select(ExamQuestion).where(ExamQuestion.exam_id == exam.id)
        ).scalars().all()
    }
    for question in attempt["questions"]:
        correct = next(
            option["id"]
            for option in links[question["exam_question_id"]].question_snapshot["options"]
            if option["is_correct"]
        )
        client.post(
            f"{api}/attempts/{attempt['id']}/answers",
            headers=headers,
            json={
                "exam_question_id": question["exam_question_id"],
                "selected_option_id": correct,
            },
        )

    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)
    results = client.get(f"{api}/results", headers=headers).json()
    assert results[0]["total_score"] == float(exam.total_marks)
    assert results[0]["percentage"] == 100.0
