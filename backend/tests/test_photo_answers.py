"""A question answered by photographing work done on paper.

For anything a keyboard is the wrong tool for — a derivation, a circuit, a proof —
where typing the answer would test transcription rather than the subject.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from app.models.enums import MAX_ANSWER_PHOTOS
from tests.conftest import png_bytes


@pytest.fixture
def photo_exam(client, api, auth_headers, teacher, teacher_course, make_exam, student, enroll):
    """A published exam whose single question is answered with photographs."""
    enroll(teacher_course, student)
    # Open now, so the student can sit it in the same test.
    exam = make_exam(
        teacher, teacher_course, start_at=datetime.now(UTC) - timedelta(minutes=1)
    )
    headers = auth_headers(teacher)
    created = client.post(
        f"{api}/exams/{exam.id}/questions",
        headers=headers,
        json={
            "type": "PHOTO_ANSWER",
            "question_text": "Derive the result and photograph your working.",
            "marks": 10,
        },
    )
    assert created.status_code == 201, created.text
    assert client.post(f"{api}/exams/{exam.id}/publish", headers=headers).status_code == 200
    return exam


@pytest.fixture
def sitting(client, api, auth_headers, student, photo_exam, make_join_request):
    make_join_request(photo_exam, student, status="approved")
    started = client.post(
        f"{api}/exams/{photo_exam.id}/start", headers=auth_headers(student)
    )
    assert started.status_code == 200, started.text
    attempt = started.json()
    return attempt, attempt["questions"][0]["exam_question_id"]


def _add_photo(client, api, headers, attempt_id, question_id, name="page.png"):
    return client.post(
        f"{api}/attempts/{attempt_id}/answers/{question_id}/photos",
        headers=headers,
        files={"file": (name, png_bytes(), "image/png")},
    )


def test_a_teacher_can_set_a_photo_question(client, api, auth_headers, teacher, photo_exam):
    questions = client.get(
        f"{api}/exams/{photo_exam.id}/questions", headers=auth_headers(teacher)
    ).json()
    assert questions[0]["question"]["type"] == "PHOTO_ANSWER"
    # No options: there is nothing to choose between.
    assert questions[0]["question"]["options"] == []


def test_a_student_photographs_their_work(client, api, auth_headers, student, sitting):
    attempt, question_id = sitting
    response = _add_photo(client, api, auth_headers(student), attempt["id"], question_id)

    assert response.status_code == 201, response.text
    body = response.json()
    assert len(body["answer_image_urls"]) == 1
    assert body["answer_image_urls"][0].startswith("/uploads/")
    # A photographed answer counts as answered, or the progress figure would tell a
    # student who has photographed every page that they have answered nothing.
    assert body["answered_count"] == 1


def test_the_photograph_can_be_fetched_back(client, api, auth_headers, student, sitting):
    attempt, question_id = sitting
    url = _add_photo(
        client, api, auth_headers(student), attempt["id"], question_id
    ).json()["answer_image_urls"][0]

    served = client.get(url)
    assert served.status_code == 200
    assert served.content == png_bytes()


def test_three_is_the_limit_and_the_server_enforces_it(
    client, api, auth_headers, student, sitting
):
    """A cap that lives only in the UI is a suggestion."""
    attempt, question_id = sitting
    headers = auth_headers(student)

    for index in range(MAX_ANSWER_PHOTOS):
        assert _add_photo(
            client, api, headers, attempt["id"], question_id, f"page{index}.png"
        ).status_code == 201

    refused = _add_photo(client, api, headers, attempt["id"], question_id, "page4.png")
    assert refused.status_code == 409
    assert refused.json()["code"] == "photo_limit_reached"


def test_a_rejected_upload_leaves_nothing_behind(
    client, api, auth_headers, student, sitting, db
):
    from app.models.upload import UploadedImage

    attempt, question_id = sitting
    headers = auth_headers(student)
    for index in range(MAX_ANSWER_PHOTOS):
        _add_photo(client, api, headers, attempt["id"], question_id, f"page{index}.png")

    before = db.query(UploadedImage).count()
    _add_photo(client, api, headers, attempt["id"], question_id, "page4.png")
    # Counted before the file is stored, so the refusal does not orphan an image.
    assert db.query(UploadedImage).count() == before


def test_a_photograph_can_be_removed_and_another_added(
    client, api, auth_headers, student, sitting
):
    attempt, question_id = sitting
    headers = auth_headers(student)
    for index in range(MAX_ANSWER_PHOTOS):
        _add_photo(client, api, headers, attempt["id"], question_id, f"page{index}.png")

    urls = client.get(f"{api}/attempts/{attempt['id']}", headers=headers).json()[
        "questions"
    ][0]["answer_image_urls"]
    removed = client.delete(
        f"{api}/attempts/{attempt['id']}/answers/{question_id}/photos",
        headers=headers,
        params={"url": urls[1]},
    )
    assert removed.status_code == 200
    assert urls[1] not in removed.json()["answer_image_urls"]
    assert len(removed.json()["answer_image_urls"]) == 2

    # And the freed slot is usable.
    assert _add_photo(
        client, api, headers, attempt["id"], question_id, "replacement.png"
    ).status_code == 201


def test_removing_a_photograph_removes_the_stored_bytes(
    client, api, auth_headers, student, sitting
):
    attempt, question_id = sitting
    headers = auth_headers(student)
    url = _add_photo(client, api, headers, attempt["id"], question_id).json()[
        "answer_image_urls"
    ][0]
    assert client.get(url).status_code == 200

    client.delete(
        f"{api}/attempts/{attempt['id']}/answers/{question_id}/photos",
        headers=headers,
        params={"url": url},
    )
    assert client.get(url).status_code == 404


def test_a_photo_question_is_not_answered_by_typing(
    client, api, auth_headers, student, sitting
):
    attempt, question_id = sitting
    response = client.post(
        f"{api}/attempts/{attempt['id']}/answers",
        headers=auth_headers(student),
        json={"exam_question_id": question_id, "answer_text": "I will describe it instead"},
    )
    assert response.status_code == 400
    assert response.json()["code"] == "photo_question"


def test_another_student_cannot_add_to_my_answer(
    client, api, auth_headers, other_student, sitting
):
    attempt, question_id = sitting
    # Uploading is answering, so it is scoped the same way: not yours, not found.
    assert _add_photo(
        client, api, auth_headers(other_student), attempt["id"], question_id
    ).status_code == 404


def test_no_photographs_after_submitting(client, api, auth_headers, student, sitting):
    attempt, question_id = sitting
    headers = auth_headers(student)
    assert client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers).status_code == 200

    refused = _add_photo(client, api, headers, attempt["id"], question_id)
    assert refused.status_code == 409
    assert refused.json()["code"] == "attempt_closed"


def test_a_file_that_is_not_an_image_is_refused(client, api, auth_headers, student, sitting):
    attempt, question_id = sitting
    response = client.post(
        f"{api}/attempts/{attempt['id']}/answers/{question_id}/photos",
        headers=auth_headers(student),
        files={"file": ("page.png", b"#!/bin/sh\nrm -rf /\n", "image/png")},
    )
    # Decoded, not trusted by extension — the same rule as every other upload.
    assert response.status_code == 400
    assert response.json()["code"] == "not_an_image"


def test_the_marker_sees_the_photographs(
    client, api, auth_headers, teacher, student, sitting
):
    attempt, question_id = sitting
    headers = auth_headers(student)
    _add_photo(client, api, headers, attempt["id"], question_id)
    _add_photo(client, api, headers, attempt["id"], question_id, "page2.png")
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)

    queue = client.get(
        f"{api}/attempts/{attempt['id']}/grading", headers=auth_headers(teacher)
    )
    assert queue.status_code == 200, queue.text
    answer = queue.json()["answers"][0]
    assert answer["type"] == "PHOTO_ANSWER"
    # Nothing can mark a photograph of handwriting but a person, so it waits for one.
    assert answer["status"] == "pending"
    assert len(answer["answer_image_urls"]) == 2


# ------------------------------------------------------- marking, and the total


def test_marking_a_photo_answer_reaches_the_result(
    client, api, auth_headers, teacher, student, photo_exam, sitting
):
    """The mark a teacher awards has to arrive in the total.

    PHOTO_ANSWER was added to the manually marked types, so it reached the queue and
    accepted a mark -- but the total was rebuilt by an if/elif over the other types,
    and a photo answer matched none of them. The mark was stored on the answer and
    then silently added to nothing.
    """
    attempt, question_id = sitting
    headers = auth_headers(student)
    assert _add_photo(client, api, headers, attempt["id"], question_id).status_code == 201
    assert client.post(
        f"{api}/attempts/{attempt['id']}/submit", headers=headers
    ).status_code == 200

    teacher_headers = auth_headers(teacher)
    queue = client.get(
        f"{api}/attempts/{attempt['id']}/grading", headers=teacher_headers
    )
    assert queue.status_code == 200, queue.text
    pending = queue.json()["answers"]
    assert len(pending) == 1, "a photographed answer needs a person to mark it"

    marked = client.post(
        f"{api}/attempts/{attempt['id']}/answers/{pending[0]['answer_id']}/evaluate",
        headers=teacher_headers,
        json={"marks_awarded": 7, "feedback": "Clear working"},
    )
    assert marked.status_code == 200, marked.text

    results = client.get(
        f"{api}/exams/{photo_exam.id}/results", headers=teacher_headers
    )
    assert results.status_code == 200, results.text
    row = results.json()[0]
    assert float(row["total_score"]) == 7.0, "the awarded mark must reach the total"
    assert float(row["percentage"]) == 70.0


def test_the_student_sees_the_mark_once_it_is_released(
    client, api, auth_headers, teacher, student, photo_exam, sitting
):
    attempt, question_id = sitting
    headers = auth_headers(student)
    _add_photo(client, api, headers, attempt["id"], question_id)
    client.post(f"{api}/attempts/{attempt['id']}/submit", headers=headers)

    teacher_headers = auth_headers(teacher)
    pending = client.get(
        f"{api}/attempts/{attempt['id']}/grading", headers=teacher_headers
    ).json()["answers"]
    client.post(
        f"{api}/attempts/{attempt['id']}/answers/{pending[0]['answer_id']}/evaluate",
        headers=teacher_headers,
        json={"marks_awarded": 9},
    )
    released = client.post(
        f"{api}/exams/{photo_exam.id}/results/publish", headers=teacher_headers
    )
    assert released.status_code == 200, released.text

    mine = client.get(f"{api}/results", headers=headers)
    assert mine.status_code == 200, mine.text
    assert float(mine.json()[0]["total_score"]) == 9.0
