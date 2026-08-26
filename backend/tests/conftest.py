"""Shared test fixtures.

The environment is configured *before* importing anything from ``app`` because
``app.core.config`` caches its Settings instance at import time.
"""

from __future__ import annotations

import os
import tempfile
from datetime import UTC, datetime, timedelta
from collections.abc import Iterator
from typing import Any
from pathlib import Path

import pytest

os.environ["ENV"] = "test"
os.environ["RATE_LIMIT_ENABLED"] = "false"
os.environ["JWT_SECRET_KEY"] = "test-only-secret-key-that-is-long-enough-32chars"
os.environ["ACCESS_TOKEN_EXPIRE_MINUTES"] = "30"
os.environ["CORS_ORIGINS"] = ""

# By default the suite runs on a throwaway SQLite file. Point TEST_DATABASE_URL at a
# PostgreSQL instance to run the same tests on the real dialect:
#
#     TEST_DATABASE_URL=postgresql://... python -m pytest
#
# WARNING: every table in that database is emptied after each test. Never point it at a
# database holding data you want to keep.
_TEST_DB_FILE = Path(tempfile.gettempdir()) / "uniexam_test.sqlite3"
_TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL")
os.environ["DATABASE_URL"] = (
    _TEST_DATABASE_URL or f"sqlite+pysqlite:///{_TEST_DB_FILE.as_posix()}"
)

from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import Session, sessionmaker  # noqa: E402

from app.core.config import settings  # noqa: E402
from app.core.database import Base  # noqa: E402
from app.core.database import get_db  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.main import app  # noqa: E402
from app.models.course import Course, CourseEnrollment  # noqa: E402
from app.models.exam import Exam, ExamQuestion, ExamSettings  # noqa: E402
from app.models.attempt import ExamAttempt  # noqa: E402
from app.models.join_request import JoinRequest  # noqa: E402
from app.models.question import Question, QuestionOption  # noqa: E402
from app.models.department import Department  # noqa: E402
from app.models.enums import UserRole  # noqa: E402
from app.models.user import StudentProfile, TeacherProfile, User  # noqa: E402

TEST_PASSWORD = "TestPassw0rd!"

# Distinguishes "argument not given" from "explicitly None" in the fixtures below.
UNSET: Any = object()


@pytest.fixture(scope="session")
def engine():
    """A real, migrated database.

    Tests run against the schema Alembic produces rather than ``metadata.create_all``, so
    a migration that drifts from the models fails here instead of on Render.
    """
    from alembic import command
    from alembic.config import Config

    using_sqlite = settings.DATABASE_URL.startswith("sqlite")
    if using_sqlite and _TEST_DB_FILE.exists():
        _TEST_DB_FILE.unlink()

    backend_dir = Path(__file__).resolve().parents[1]
    alembic_cfg = Config(str(backend_dir / "alembic.ini"))
    alembic_cfg.set_main_option("script_location", str(backend_dir / "alembic"))
    command.upgrade(alembic_cfg, "head")

    eng = create_engine(settings.DATABASE_URL, future=True)
    yield eng
    eng.dispose()
    if using_sqlite:
        # A PostgreSQL target keeps its (now empty) schema; only the scratch file goes.
        _TEST_DB_FILE.unlink(missing_ok=True)


@pytest.fixture
def db(engine) -> Iterator[Session]:
    """A real session per test; every table is emptied afterwards.

    The usual "wrap the test in a transaction and roll back" trick is not used here:
    pysqlite manages transactions itself and does not honour the SAVEPOINTs that pattern
    needs, so a service ``commit()`` would survive the rollback and leak into the next
    test. Deleting the rows is slower but actually isolates.
    """
    TestSession = sessionmaker(bind=engine, expire_on_commit=False, autoflush=False)
    session = TestSession()
    try:
        yield session
    finally:
        session.close()
        with engine.begin() as connection:
            for table in reversed(Base.metadata.sorted_tables):
                connection.execute(table.delete())


@pytest.fixture
def client(db: Session) -> Iterator[TestClient]:
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


# --------------------------------------------------------------------- factories


@pytest.fixture
def department(db: Session) -> Department:
    dept = Department(code="CSE", name="Computer Science & Engineering")
    db.add(dept)
    db.commit()
    return dept


@pytest.fixture
def make_user(db: Session, department: Department):
    counter = {"n": 0}

    def _make(
        role: UserRole,
        *,
        login_id: str | None = None,
        password: str = TEST_PASSWORD,
        is_active: bool = True,
        name: str | None = None,
    ) -> User:
        counter["n"] += 1
        login_id = login_id or f"{role.value}{counter['n']:03d}"
        user = User(
            user_id=login_id,
            password_hash=hash_password(password),
            name=name or f"{role.value.title()} {counter['n']}",
            email=f"{login_id}@example.edu",
            role=role.value,
            department_id=department.id,
            is_active=is_active,
        )
        db.add(user)
        db.flush()
        if role == UserRole.STUDENT:
            db.add(
                StudentProfile(
                    user_id=user.id,
                    student_id=login_id,
                    department_id=department.id,
                    semester=6,
                    session="2025-2026",
                )
            )
        elif role == UserRole.TEACHER:
            db.add(
                TeacherProfile(
                    user_id=user.id,
                    teacher_id=login_id,
                    department_id=department.id,
                    designation="Lecturer",
                )
            )
        db.commit()
        return user

    return _make


@pytest.fixture
def admin(make_user) -> User:
    return make_user(UserRole.ADMIN, login_id="admin001")


@pytest.fixture
def teacher(make_user) -> User:
    return make_user(UserRole.TEACHER, login_id="T1001")


@pytest.fixture
def other_teacher(make_user) -> User:
    return make_user(UserRole.TEACHER, login_id="T2002")


@pytest.fixture
def student(make_user) -> User:
    return make_user(UserRole.STUDENT, login_id="20261234")


@pytest.fixture
def other_student(make_user) -> User:
    return make_user(UserRole.STUDENT, login_id="20265678")


@pytest.fixture
def make_course(db: Session, department: Department):
    counter = {"n": 0}

    def _make(owner: User, *, code: str | None = None, session: str = "2025-2026") -> Course:
        counter["n"] += 1
        course = Course(
            course_code=code or f"CSE-{300 + counter['n']}",
            course_name="Database Management System",
            department_id=department.id,
            semester=6,
            session=session,
            created_by=owner.id,
        )
        db.add(course)
        db.commit()
        return course

    return _make


@pytest.fixture
def enroll(db: Session):
    def _enroll(course: Course, student_user: User) -> CourseEnrollment:
        enrollment = CourseEnrollment(course_id=course.id, student_id=student_user.id)
        db.add(enrollment)
        db.commit()
        return enrollment

    return _enroll


# ------------------------------------------------------------------ auth helpers


@pytest.fixture
def login(client: TestClient):
    def _login(user: User, password: str = TEST_PASSWORD):
        response = client.post(
            f"{settings.API_V1_PREFIX}/auth/login",
            json={"user_id": user.user_id, "password": password},
        )
        return response

    return _login


@pytest.fixture
def auth_headers(login):
    def _headers(user: User, password: str = TEST_PASSWORD) -> dict[str, str]:
        response = login(user, password)
        assert response.status_code == 200, response.text
        return {"Authorization": f"Bearer {response.json()['access_token']}"}

    return _headers


@pytest.fixture
def api() -> str:
    return settings.API_V1_PREFIX


# ------------------------------------------------------------------ exam helpers


def mcq_payload(
    *,
    text: str = "What is the time complexity of binary search?",
    marks: int = 1,
    correct_index: int = 1,
    options: list[str] | None = None,
    **extra,
) -> dict:
    """A valid TEXT_MCQ body. Tests override single fields to make one thing invalid."""
    labels = options or ["O(n)", "O(log n)", "O(n^2)", "O(1)"]
    return {
        "type": "TEXT_MCQ",
        "question_text": text,
        "marks": marks,
        "options": [
            {"option_text": label, "is_correct": index == correct_index}
            for index, label in enumerate(labels)
        ],
        **extra,
    }


@pytest.fixture
def future_start() -> str:
    """A start time comfortably in the future, in the format the API returns."""
    return (datetime.now(UTC) + timedelta(days=1)).isoformat()


@pytest.fixture
def make_exam(db: Session):
    """Creates a draft exam directly, for tests that are not about creation itself."""
    counter = {"n": 0}

    def _make(
        owner: User,
        course: Course,
        *,
        title: str | None = None,
        # UNSET means "give me a sensible future start"; an explicit None means the exam
        # genuinely has no start time, which is a case the publish checks must catch.
        start_at: datetime | None = UNSET,
        duration_minutes: int = 30,
    ) -> Exam:
        counter["n"] += 1
        exam = Exam(
            course_id=course.id,
            teacher_id=owner.id,
            title=title or f"Mid Term {counter['n']}",
            duration_minutes=duration_minutes,
            start_at=(datetime.now(UTC) + timedelta(days=1)) if start_at is UNSET else start_at,
        )
        db.add(exam)
        db.flush()
        db.add(ExamSettings(exam_id=exam.id))
        db.commit()
        return exam

    return _make


@pytest.fixture
def teacher_course(teacher, make_course) -> Course:
    return make_course(teacher)


@pytest.fixture
def make_published_exam(db: Session):
    """A published exam with one MCQ, built directly so tests about discovery and join
    requests do not have to drive the whole teacher workflow first."""
    counter = {"n": 0}

    def _make(
        owner: User,
        course: Course,
        *,
        title: str | None = None,
        starts_in: timedelta = timedelta(days=1),
        duration_minutes: int = 30,
        marks: int = 5,
        show_result_immediately: bool = False,
        shuffle_questions: bool = False,
        shuffle_answers: bool = False,
        question_count: int = 1,
    ) -> Exam:
        counter["n"] += 1
        start_at = datetime.now(UTC) + starts_in
        exam = Exam(
            course_id=course.id,
            teacher_id=owner.id,
            title=title or f"Published Exam {counter['n']}",
            duration_minutes=duration_minutes,
            start_at=start_at,
            expires_at=start_at + timedelta(minutes=duration_minutes),
            total_marks=marks * question_count,
            status="published",
            published_at=datetime.now(UTC),
        )
        db.add(exam)
        db.flush()
        db.add(
            ExamSettings(
                exam_id=exam.id,
                show_result_immediately=show_result_immediately,
                shuffle_questions=shuffle_questions,
                shuffle_answers=shuffle_answers,
            )
        )

        for index in range(question_count):
            question = Question(
                type="TEXT_MCQ",
                question_text=f"Question {index + 1}: what is normalization?",
                marks=marks,
                created_by=owner.id,
            )
            db.add(question)
            db.flush()
            for order, (label, correct) in enumerate(
                [
                    ("Removing redundancy", True),
                    ("Adding redundancy", False),
                    ("Indexing every column", False),
                    ("Denormalising joins", False),
                ]
            ):
                db.add(
                    QuestionOption(
                        question_id=question.id,
                        option_text=f"{label} ({index + 1})",
                        display_order=order,
                        is_correct=correct,
                    )
                )
            db.flush()
            db.add(
                ExamQuestion(
                    exam_id=exam.id,
                    question_id=question.id,
                    marks_snapshot=marks,
                    display_order=index,
                    question_snapshot={
                        "id": question.id,
                        "type": "TEXT_MCQ",
                        "question_text": question.question_text,
                        "marks": marks,
                        "options": [
                            {
                                "id": option.id,
                                "option_text": option.option_text,
                                "display_order": option.display_order,
                                "is_correct": option.is_correct,
                            }
                            for option in question.options
                        ],
                    },
                )
            )
        exam.total_marks = marks * question_count
        db.commit()
        return exam

    return _make


@pytest.fixture
def make_join_request(db: Session):
    def _make(exam: Exam, student_user: User, *, status: str = "pending") -> JoinRequest:
        request = JoinRequest(exam_id=exam.id, student_id=student_user.id, status=status)
        db.add(request)
        db.commit()
        return request

    return _make


@pytest.fixture
def make_approved_exam(teacher_course, make_published_exam, enroll, make_join_request):
    """An exam the student is enrolled in, approved for, and that is open right now."""

    def _make(teacher, student, **kwargs) -> Exam:
        enroll(teacher_course, student)
        exam = make_published_exam(
            teacher,
            teacher_course,
            starts_in=timedelta(minutes=-1),
            duration_minutes=60,
            **kwargs,
        )
        make_join_request(exam, student, status="approved")
        return exam

    return _make


@pytest.fixture
def approved_exam(teacher, student, make_approved_exam):
    return make_approved_exam(teacher, student)


@pytest.fixture
def expire_attempt(db: Session):
    """Move an attempt's deadline into the past.

    Faster and more reliable than sleeping, and it exercises exactly what the server
    checks: the stored ``expires_at`` against the real clock.
    """

    def _expire(attempt_id: int, *, seconds_ago: int = 5) -> None:
        attempt = db.get(ExamAttempt, attempt_id)
        attempt.expires_at = datetime.now(UTC) - timedelta(seconds=seconds_ago)
        db.commit()

    return _expire


def png_bytes(width: int = 64, height: int = 48, fmt: str = "PNG") -> bytes:
    """A real, decodable image — the upload path rejects anything it cannot open."""
    import io

    from PIL import Image

    buffer = io.BytesIO()
    Image.new("RGB", (width, height), (30, 90, 155)).save(buffer, format=fmt)
    return buffer.getvalue()


def short_answer_payload(*, text: str = "Explain the difference between TCP and UDP.",
                         marks: int = 10) -> dict:
    return {"type": "SHORT_ANSWER", "question_text": text, "marks": marks}


def code_payload(*, text: str = "Write a program to implement binary search.",
                 marks: int = 10, language: str = "cpp") -> dict:
    return {
        "type": "CODE_ANSWER",
        "question_text": text,
        "marks": marks,
        "language": language,
        "time_limit_seconds": 2,
        "memory_limit_mb": 256,
    }


def image_mcq_payload(*, image_url: str, marks: int = 5,
                      option_images: list[str] | None = None) -> dict:
    """IMAGE_TEXT_OPTIONS by default; pass option_images for IMAGE_IMAGE_OPTIONS."""
    if option_images:
        return {
            "type": "IMAGE_IMAGE_OPTIONS",
            "question_text": "Which circuit matches the diagram?",
            "question_image_url": image_url,
            "marks": marks,
            "options": [
                {"option_image_url": url, "is_correct": index == 0}
                for index, url in enumerate(option_images)
            ],
        }
    return {
        "type": "IMAGE_TEXT_OPTIONS",
        "question_text": "Which logic gate is shown?",
        "question_image_url": image_url,
        "marks": marks,
        "options": [
            {"option_text": "AND", "is_correct": True},
            {"option_text": "OR"},
            {"option_text": "XOR"},
            {"option_text": "NAND"},
        ],
    }


@pytest.fixture
def upload_dir(tmp_path, monkeypatch):
    """Kept for the tests that merely need *an* image to exist.

    Images are stored in the database now, so there is no directory to redirect and
    nothing here to isolate — the per-test truncation already handles that. The fixture
    stays so the many tests that just want a valid upload keep reading naturally, and
    because removing it would be a large diff about nothing.
    """
    from app.core.config import settings as app_settings

    monkeypatch.setattr(app_settings, "UPLOAD_DIR", str(tmp_path))
    return tmp_path
