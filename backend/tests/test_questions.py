from __future__ import annotations

from tests.conftest import mcq_payload


def _add(client, api, headers, exam_id, **kwargs):
    return client.post(f"{api}/exams/{exam_id}/questions", headers=headers, json=mcq_payload(**kwargs))


def test_adding_an_mcq_updates_the_exam_total(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)

    response = _add(client, api, headers, exam.id, marks=5)
    assert response.status_code == 201
    body = response.json()
    assert body["display_order"] == 0
    assert body["marks_snapshot"] == 5
    assert body["is_frozen"] is False
    assert len(body["question"]["options"]) == 4

    exam_body = client.get(f"{api}/exams/{exam.id}", headers=headers).json()
    assert exam_body["total_marks"] == 5
    assert exam_body["question_count"] == 1

    _add(client, api, headers, exam.id, text="Second question", marks=3)
    exam_body = client.get(f"{api}/exams/{exam.id}", headers=headers).json()
    assert exam_body["total_marks"] == 8, "total_marks is derived, never client-supplied"
    assert exam_body["question_count"] == 2


def test_the_teacher_view_includes_the_answer_key(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    _add(client, api, headers, exam.id, correct_index=2)

    options = client.get(f"{api}/exams/{exam.id}/questions", headers=headers).json()[0][
        "question"
    ]["options"]
    correct = [option for option in options if option["is_correct"]]
    assert len(correct) == 1
    assert correct[0]["display_order"] == 2


def test_questions_without_exactly_one_correct_answer_are_rejected(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    url = f"{api}/exams/{exam.id}/questions"

    no_correct = mcq_payload()
    for option in no_correct["options"]:
        option["is_correct"] = False
    assert client.post(url, headers=headers, json=no_correct).status_code == 422

    two_correct = mcq_payload()
    two_correct["options"][0]["is_correct"] = True
    two_correct["options"][1]["is_correct"] = True
    assert client.post(url, headers=headers, json=two_correct).status_code == 422


def test_a_question_needs_at_least_two_distinct_options(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    url = f"{api}/exams/{exam.id}/questions"

    single = mcq_payload(options=["Only one"], correct_index=0)
    assert client.post(url, headers=headers, json=single).status_code == 422

    duplicates = mcq_payload(options=["Same", "same "], correct_index=0)
    assert client.post(url, headers=headers, json=duplicates).status_code == 422


def test_unimplemented_question_types_are_refused(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    # The column allows every type, but nothing may create one the app cannot render.
    exam = make_exam(teacher, teacher_course)
    payload = mcq_payload()
    payload["type"] = "CODE_ANSWER"
    response = client.post(
        f"{api}/exams/{exam.id}/questions", headers=auth_headers(teacher), json=payload
    )
    assert response.status_code == 422


def test_another_teacher_cannot_add_questions_to_my_exam(
    client, api, auth_headers, teacher, other_teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    assert _add(client, api, auth_headers(other_teacher), exam.id).status_code == 404


def test_another_teacher_cannot_read_my_questions(
    client, api, auth_headers, teacher, other_teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    _add(client, api, auth_headers(teacher), exam.id)
    response = client.get(f"{api}/exams/{exam.id}/questions", headers=auth_headers(other_teacher))
    assert response.status_code == 404


def test_editing_a_question_replaces_its_options_and_marks(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    link_id = _add(client, api, headers, exam.id, marks=2).json()["id"]

    response = client.put(
        f"{api}/exams/{exam.id}/questions/{link_id}",
        headers=headers,
        json=mcq_payload(text="Rewritten", marks=7, options=["Yes", "No"], correct_index=0),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["question"]["question_text"] == "Rewritten"
    assert [option["option_text"] for option in body["question"]["options"]] == ["Yes", "No"]
    assert body["marks_snapshot"] == 7

    exam_body = client.get(f"{api}/exams/{exam.id}", headers=headers).json()
    assert exam_body["total_marks"] == 7


def test_removing_a_question_recalculates_and_closes_the_gap(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    first = _add(client, api, headers, exam.id, text="Q1", marks=2).json()["id"]
    _add(client, api, headers, exam.id, text="Q2", marks=3)
    _add(client, api, headers, exam.id, text="Q3", marks=4)

    assert client.delete(
        f"{api}/exams/{exam.id}/questions/{first}", headers=headers
    ).status_code == 204

    remaining = client.get(f"{api}/exams/{exam.id}/questions", headers=headers).json()
    assert [q["question"]["question_text"] for q in remaining] == ["Q2", "Q3"]
    # No gap left behind, so the student's question palette numbers 1..n.
    assert [q["display_order"] for q in remaining] == [0, 1]
    assert client.get(f"{api}/exams/{exam.id}", headers=headers).json()["total_marks"] == 7


def test_questions_can_be_reordered(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    ids = [
        _add(client, api, headers, exam.id, text=f"Q{n}").json()["id"] for n in range(1, 4)
    ]

    response = client.put(
        f"{api}/exams/{exam.id}/questions/order",
        headers=headers,
        json={"question_ids": [ids[2], ids[0], ids[1]]},
    )
    assert response.status_code == 200
    assert [item["question"]["question_text"] for item in response.json()] == ["Q3", "Q1", "Q2"]


def test_a_partial_reorder_is_rejected(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    headers = auth_headers(teacher)
    ids = [_add(client, api, headers, exam.id, text=f"Q{n}").json()["id"] for n in range(1, 4)]

    response = client.put(
        f"{api}/exams/{exam.id}/questions/order",
        headers=headers,
        json={"question_ids": ids[:2]},
    )
    assert response.status_code == 422


def test_a_question_from_another_exam_cannot_be_edited_through_mine(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    mine = make_exam(teacher, teacher_course, title="Mine")
    other = make_exam(teacher, teacher_course, title="Other")
    headers = auth_headers(teacher)
    foreign_link = _add(client, api, headers, other.id).json()["id"]

    response = client.put(
        f"{api}/exams/{mine.id}/questions/{foreign_link}", headers=headers, json=mcq_payload()
    )
    assert response.status_code == 404
