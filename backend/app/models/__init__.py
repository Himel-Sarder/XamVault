"""SQLAlchemy models.

Importing this package registers every mapper on ``Base.metadata``; Alembic's env.py and
the test fixtures both rely on that, so new model modules must be added here.
"""

from app.models.attempt import ExamAttempt, StudentAnswer
from app.models.course import Course, CourseEnrollment
from app.models.department import Department
from app.models.enums import (
    AnswerStatus,
    AttemptStatus,
    ExamStatus,
    JoinRequestStatus,
    NotificationCategory,
    QuestionType,
    ResultStatus,
    SecurityEventType,
    SecuritySeverity,
    UserRole,
)
from app.models.exam import Exam, ExamQuestion, ExamSettings
from app.models.join_request import JoinRequest
from app.models.notification import Notification
from app.models.question import Question, QuestionOption
from app.models.refresh_token import RefreshToken
from app.models.result import Result
from app.models.security_event import SecurityEvent
from app.models.upload import UploadedImage
from app.models.user import StudentProfile, TeacherProfile, User

__all__ = [
    "AnswerStatus",
    "AttemptStatus",
    "Course",
    "CourseEnrollment",
    "Department",
    "Exam",
    "ExamAttempt",
    "ExamQuestion",
    "ExamSettings",
    "ExamStatus",
    "JoinRequest",
    "JoinRequestStatus",
    "Notification",
    "NotificationCategory",
    "Question",
    "QuestionOption",
    "QuestionType",
    "RefreshToken",
    "Result",
    "ResultStatus",
    "SecurityEvent",
    "UploadedImage",
    "SecurityEventType",
    "SecuritySeverity",
    "StudentAnswer",
    "StudentProfile",
    "TeacherProfile",
    "User",
    "UserRole",
]
