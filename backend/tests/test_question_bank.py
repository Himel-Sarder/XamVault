"""Phase 6 — the reusable question library (§6)."""

from __future__ import annotations

from tests.conftest import code_payload, mcq_payload, short_answer_payload


def _create(client, api, headers, payload):
    return client.post(f"{api}/question-bank", headers=headers, json=payload)


def test_a_teacher_builds_a_library(client, api, auth_headers, teacher):
    headers = auth_headers(teacher)

    response = _create(
        client, api, headers,
        mcq_payload(text="What is normalization?", marks=5) | {"topic": "Databases",
                                                              "difficulty": "medium"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["topic"] == "Databases"
    assert body["difficulty"] == "medium"
    # Nothing uses it yet, so it can still be deleted.
    assert body["used_in_exams"] == 0
    assert body["used_in_published"] is False


def test_the_library_is_searchable(client, api, auth_headers, teacher):
    headers = auth_headers(teacher)
    _create(client, api, headers, mcq_payload(text="What is normalization?") | {"topic": "Databases"})
    _create(client, api, headers, mcq_payload(text="What is a deadlock?") | {"topic": "Operating Systems"})
    _create(client, api, headers, short_answer_payload(text="Explain TCP") | {"topic": "Networks"})

    everything = client.get(f"{api}/question-bank", headers=headers).json()
    assert everything["total"] == 3

    by_type = client.get(
        f"{api}/question-bank", headers=headers, params={"type": "SHORT_ANSWER"}
    ).json()
    assert by_type["total"] == 1

    by_topic = client.get(
        f"{api}/question-bank", headers=headers, params={"topic": "Databases"}
    ).json()
    assert by_topic["total"] == 1

    by_text = client.get(
        f"{api}/question-bank", headers=headers, params={"search": "deadlock"}
    ).json()
    assert by_text["total"] == 1
    assert "deadlock" in by_text["items"][0]["question_text"]


def test_topics_are_offered_for_filtering(client, api, auth_headers, teacher):
    headers = auth_headers(teacher)
    _create(client, api, headers, mcq_payload(text="Q1") | {"topic": "Databases"})
    _create(client, api, headers, mcq_payload(text="Q2") | {"topic": "Networks"})
    _create(client, api, headers, mcq_payload(text="Q3") | {"topic": "Databases"})

    topics = client.get(f"{api}/question-bank/topics", headers=headers).json()["topics"]
    assert topics == ["Databases", "Networks"], "distinct and sorted"


def test_an_unknown_type_filter_is_rejected(client, api, auth_headers, teacher):
    response = client.get(
        f"{api}/question-bank", headers=auth_headers(teacher), params={"type": "ESSAY"}
    )
    assert response.status_code == 400


def test_one_teachers_library_is_invisible_to_another(
    client, api, auth_headers, teacher, other_teacher
):
    created = _create(client, api, auth_headers(teacher), mcq_payload()).json()
    intruder = auth_headers(other_teacher)

    assert client.get(f"{api}/question-bank", headers=intruder).json()["total"] == 0
    assert client.get(
        f"{api}/question-bank/{created['id']}", headers=intruder
    ).status_code == 404


def test_students_have_no_library(client, api, auth_headers, student):
    assert client.get(f"{api}/question-bank", headers=auth_headers(student)).status_code == 403


def test_a_question_can_be_reused_across_exams(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    headers = auth_headers(teacher)
    question = _create(client, api, headers, mcq_payload(marks=5)).json()
    first = make_exam(teacher, teacher_course, title="Mid Term")
    second = make_exam(teacher, teacher_course, title="Final")

    for exam in (first, second):
        response = client.post(
            f"{api}/exams/{exam.id}/questions/from-bank",
            headers=headers,
            json={"question_ids": [question["id"]]},
        )
        assert response.status_code == 201
        assert response.json()[0]["question"]["id"] == question["id"]

    # One question, two papers — which is the whole point of a bank.
    reread = client.get(f"{api}/question-bank/{question['id']}", headers=headers).json()
    assert reread["used_in_exams"] == 2
    assert reread["used_in_published"] is False

    for exam in (first, second):
        body = client.get(f"{api}/exams/{exam.id}", headers=headers).json()
        assert body["question_count"] == 1
        assert body["total_marks"] == 5


def test_the_same_question_cannot_be_added_twice_to_one_exam(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    headers = auth_headers(teacher)
    question = _create(client, api, headers, mcq_payload()).json()
    exam = make_exam(teacher, teacher_course)
    url = f"{api}/exams/{exam.id}/questions/from-bank"

    assert client.post(url, headers=headers, json={"question_ids": [question["id"]]}).status_code == 201
    again = client.post(url, headers=headers, json={"question_ids": [question["id"]]})
    assert again.status_code == 409
    assert again.json()["code"] == "already_attached"


def test_several_questions_can_be_added_at_once(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    headers = auth_headers(teacher)
    ids = [
        _create(client, api, headers, mcq_payload(text=f"Q{n}", marks=3)).json()["id"]
        for n in range(3)
    ]
    exam = make_exam(teacher, teacher_course)

    response = client.post(
        f"{api}/exams/{exam.id}/questions/from-bank",
        headers=headers,
        json={"question_ids": ids},
    )
    assert response.status_code == 201
    assert [item["display_order"] for item in response.json()] == [0, 1, 2]
    assert client.get(f"{api}/exams/{exam.id}", headers=headers).json()["total_marks"] == 9


def test_questions_cannot_be_added_to_a_published_exam(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    headers = auth_headers(teacher)
    question = _create(client, api, headers, mcq_payload()).json()
    exam = make_exam(teacher, teacher_course)
    client.post(f"{api}/exams/{exam.id}/questions", headers=headers, json=mcq_payload(text="First"))
    client.post(f"{api}/exams/{exam.id}/publish", headers=headers)

    response = client.post(
        f"{api}/exams/{exam.id}/questions/from-bank",
        headers=headers,
        json={"question_ids": [question["id"]]},
    )
    assert response.status_code == 409
    assert response.json()["code"] == "exam_not_editable"


def test_another_teachers_question_cannot_be_borrowed(
    client, api, auth_headers, teacher, other_teacher, teacher_course, make_exam
):
    theirs = _create(client, api, auth_headers(other_teacher), mcq_payload()).json()
    exam = make_exam(teacher, teacher_course)

    response = client.post(
        f"{api}/exams/{exam.id}/questions/from-bank",
        headers=auth_headers(teacher),
        json={"question_ids": [theirs["id"]]},
    )
    assert response.status_code == 404


def test_editing_a_question_updates_draft_exams_but_not_published_ones(
    client, api, auth_headers, teacher, teacher_course, make_exam, db
):
    """The whole reason reuse is safe: a published paper renders from its own snapshot."""
    from sqlalchemy import select

    from app.models.exam import ExamQuestion

    headers = auth_headers(teacher)
    question = _create(
        client, api, headers, mcq_payload(text="Original wording", marks=5)
    ).json()

    published = make_exam(teacher, teacher_course, title="Already Published")
    draft = make_exam(teacher, teacher_course, title="Still A Draft")
    for exam in (published, draft):
        client.post(
            f"{api}/exams/{exam.id}/questions/from-bank",
            headers=headers,
            json={"question_ids": [question["id"]]},
        )
    assert client.post(f"{api}/exams/{published.id}/publish", headers=headers).status_code == 200

    edited = client.put(
        f"{api}/question-bank/{question['id']}",
        headers=headers,
        json=mcq_payload(text="Rewritten wording", marks=9),
    )
    assert edited.status_code == 200
    assert edited.json()["used_in_published"] is True

    # The published exam is untouched: same wording, same marks.
    frozen = db.execute(
        select(ExamQuestion).where(ExamQuestion.exam_id == published.id)
    ).scalar_one()
    assert frozen.question_snapshot["question_text"] == "Original wording"
    assert frozen.marks_snapshot == 5
    assert client.get(f"{api}/exams/{published.id}", headers=headers).json()["total_marks"] == 5

    # The draft follows the edit, and its total follows with it.
    draft_body = client.get(f"{api}/exams/{draft.id}", headers=headers).json()
    assert draft_body["total_marks"] == 9
    draft_questions = client.get(
        f"{api}/exams/{draft.id}/questions", headers=headers
    ).json()
    assert draft_questions[0]["question"]["question_text"] == "Rewritten wording"
    assert draft_questions[0]["marks_snapshot"] == 9


def test_a_question_in_use_cannot_be_deleted(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    headers = auth_headers(teacher)
    question = _create(client, api, headers, mcq_payload()).json()
    exam = make_exam(teacher, teacher_course)
    client.post(
        f"{api}/exams/{exam.id}/questions/from-bank",
        headers=headers,
        json={"question_ids": [question["id"]]},
    )

    response = client.delete(f"{api}/question-bank/{question['id']}", headers=headers)
    assert response.status_code == 409
    assert response.json()["code"] == "question_in_use"


def test_an_unused_question_can_be_deleted(client, api, auth_headers, teacher):
    headers = auth_headers(teacher)
    question = _create(client, api, headers, mcq_payload()).json()

    assert client.delete(f"{api}/question-bank/{question['id']}", headers=headers).status_code == 204
    assert client.get(f"{api}/question-bank/{question['id']}", headers=headers).status_code == 404


def test_removing_a_question_from_an_exam_frees_it_for_deletion(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    headers = auth_headers(teacher)
    question = _create(client, api, headers, mcq_payload()).json()
    exam = make_exam(teacher, teacher_course)
    link = client.post(
        f"{api}/exams/{exam.id}/questions/from-bank",
        headers=headers,
        json={"question_ids": [question["id"]]},
    ).json()[0]

    client.delete(f"{api}/exams/{exam.id}/questions/{link['id']}", headers=headers)

    # Detaching must not have destroyed the library copy — it is a link, not ownership.
    still_there = client.get(f"{api}/question-bank/{question['id']}", headers=headers)
    assert still_there.status_code == 200
    assert still_there.json()["used_in_exams"] == 0
    assert client.delete(f"{api}/question-bank/{question['id']}", headers=headers).status_code == 204


def test_another_teacher_cannot_edit_or_delete_my_question(
    client, api, auth_headers, teacher, other_teacher
):
    question = _create(client, api, auth_headers(teacher), mcq_payload()).json()
    intruder = auth_headers(other_teacher)

    assert client.put(
        f"{api}/question-bank/{question['id']}", headers=intruder, json=mcq_payload()
    ).status_code == 404
    assert client.delete(
        f"{api}/question-bank/{question['id']}", headers=intruder
    ).status_code == 404


def test_every_question_type_can_live_in_the_bank(client, api, auth_headers, teacher):
    headers = auth_headers(teacher)
    for payload in (mcq_payload(), short_answer_payload(), code_payload()):
        assert _create(client, api, headers, payload).status_code == 201

    body = client.get(f"{api}/question-bank", headers=headers).json()
    assert {item["type"] for item in body["items"]} == {
        "TEXT_MCQ", "SHORT_ANSWER", "CODE_ANSWER"
    }
    code = next(item for item in body["items"] if item["type"] == "CODE_ANSWER")
    assert code["language"] == "cpp"


def test_bank_questions_are_validated_like_any_other(client, api, auth_headers, teacher):
    headers = auth_headers(teacher)
    no_answer = mcq_payload()
    for option in no_answer["options"]:
        option["is_correct"] = False

    assert _create(client, api, headers, no_answer).status_code == 422
