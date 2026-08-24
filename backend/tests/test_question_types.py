"""Phase 5 — the four question types beyond plain text MCQ (§19-§22)."""

from __future__ import annotations

from tests.conftest import code_payload, image_mcq_payload, png_bytes, short_answer_payload


def _upload(client, api, headers) -> str:
    response = client.post(
        f"{api}/questions/upload-image",
        headers=headers,
        files={"file": ("d.png", png_bytes(), "image/png")},
    )
    assert response.status_code == 200, response.text
    return response.json()["url"]


def _add(client, api, headers, exam_id, payload):
    return client.post(f"{api}/exams/{exam_id}/questions", headers=headers, json=payload)


def test_an_image_question_with_text_options(
    client, api, auth_headers, teacher, teacher_course, make_exam, upload_dir
):
    headers = auth_headers(teacher)
    exam = make_exam(teacher, teacher_course)
    url = _upload(client, api, headers)

    response = _add(client, api, headers, exam.id, image_mcq_payload(image_url=url))
    assert response.status_code == 201
    question = response.json()["question"]
    assert question["type"] == "IMAGE_TEXT_OPTIONS"
    assert question["question_image_url"] == url
    assert [option["option_text"] for option in question["options"]] == [
        "AND", "OR", "XOR", "NAND",
    ]


def test_an_image_question_with_image_options(
    client, api, auth_headers, teacher, teacher_course, make_exam, upload_dir
):
    headers = auth_headers(teacher)
    exam = make_exam(teacher, teacher_course)
    stem = _upload(client, api, headers)
    options = [_upload(client, api, headers) for _ in range(3)]

    response = _add(
        client, api, headers, exam.id,
        image_mcq_payload(image_url=stem, option_images=options),
    )
    assert response.status_code == 201
    question = response.json()["question"]
    assert question["type"] == "IMAGE_IMAGE_OPTIONS"
    assert [option["option_image_url"] for option in question["options"]] == options


def test_an_image_question_without_its_image_is_rejected(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    payload = image_mcq_payload(image_url="/uploads/x.png")
    payload.pop("question_image_url")
    exam = make_exam(teacher, teacher_course)

    response = _add(client, api, auth_headers(teacher), exam.id, payload)
    assert response.status_code == 422


def test_image_options_missing_an_image_are_rejected(
    client, api, auth_headers, teacher, teacher_course, make_exam, upload_dir
):
    headers = auth_headers(teacher)
    exam = make_exam(teacher, teacher_course)
    stem = _upload(client, api, headers)
    payload = image_mcq_payload(image_url=stem, option_images=[stem, stem])
    payload["options"][1] = {"option_text": "no image here"}

    assert _add(client, api, headers, exam.id, payload).status_code == 422


def test_a_short_answer_question(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    response = _add(client, api, auth_headers(teacher), exam.id, short_answer_payload())

    assert response.status_code == 201
    question = response.json()["question"]
    assert question["type"] == "SHORT_ANSWER"
    assert question["options"] == []
    assert response.json()["marks_snapshot"] == 10


def test_a_short_answer_question_may_not_carry_options(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    payload = short_answer_payload()
    payload["options"] = [{"option_text": "a", "is_correct": True}, {"option_text": "b"}]
    exam = make_exam(teacher, teacher_course)

    assert _add(client, api, auth_headers(teacher), exam.id, payload).status_code == 422


def test_a_code_question_carries_its_configuration(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    response = _add(client, api, auth_headers(teacher), exam.id, code_payload())

    assert response.status_code == 201
    question = response.json()["question"]
    assert question["type"] == "CODE_ANSWER"
    assert question["language"] == "cpp"
    assert question["time_limit_seconds"] == 2
    assert question["memory_limit_mb"] == 256


def test_a_code_question_without_a_language_is_rejected(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    payload = code_payload()
    payload.pop("language")
    exam = make_exam(teacher, teacher_course)

    assert _add(client, api, auth_headers(teacher), exam.id, payload).status_code == 422


def test_an_unknown_language_is_rejected(
    client, api, auth_headers, teacher, teacher_course, make_exam
):
    exam = make_exam(teacher, teacher_course)
    payload = code_payload(language="brainfuck")

    assert _add(client, api, auth_headers(teacher), exam.id, payload).status_code == 422


def test_a_mixed_exam_totals_every_type(
    client, api, auth_headers, teacher, teacher_course, make_exam, upload_dir
):
    from tests.conftest import mcq_payload

    headers = auth_headers(teacher)
    exam = make_exam(teacher, teacher_course)
    url = _upload(client, api, headers)

    _add(client, api, headers, exam.id, mcq_payload(marks=1))
    _add(client, api, headers, exam.id, image_mcq_payload(image_url=url, marks=5))
    _add(client, api, headers, exam.id, short_answer_payload(marks=10))
    _add(client, api, headers, exam.id, code_payload(marks=10))

    body = client.get(f"{api}/exams/{exam.id}", headers=headers).json()
    assert body["question_count"] == 4
    assert body["total_marks"] == 26


def test_a_mixed_exam_publishes(
    client, api, auth_headers, teacher, teacher_course, make_exam, upload_dir
):
    from tests.conftest import mcq_payload

    headers = auth_headers(teacher)
    exam = make_exam(teacher, teacher_course)
    url = _upload(client, api, headers)
    _add(client, api, headers, exam.id, mcq_payload())
    _add(client, api, headers, exam.id, image_mcq_payload(image_url=url))
    _add(client, api, headers, exam.id, short_answer_payload())
    _add(client, api, headers, exam.id, code_payload())

    check = client.get(f"{api}/exams/{exam.id}/publish-check", headers=headers).json()
    assert check["can_publish"] is True, check["issues"]
    assert client.post(f"{api}/exams/{exam.id}/publish", headers=headers).status_code == 200


def test_publishing_blocks_an_image_question_that_lost_its_image(
    client, api, auth_headers, teacher, teacher_course, make_exam, upload_dir, db
):
    from sqlalchemy import select

    from app.models.question import Question

    headers = auth_headers(teacher)
    exam = make_exam(teacher, teacher_course)
    url = _upload(client, api, headers)
    _add(client, api, headers, exam.id, image_mcq_payload(image_url=url))

    # The API cannot create this state, but an import or a direct edit could.
    question = db.execute(select(Question)).scalars().one()
    question.question_image_url = None
    db.commit()

    response = client.post(f"{api}/exams/{exam.id}/publish", headers=headers)
    assert response.status_code == 422
    assert any("image" in issue["message"] for issue in response.json()["issues"])
