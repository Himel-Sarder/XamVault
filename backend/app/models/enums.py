"""Domain enumerations.

Stored as ``VARCHAR`` guarded by a CHECK constraint rather than a native PostgreSQL
``ENUM``: adding a value later is an ordinary migration instead of an ``ALTER TYPE``
that cannot run inside a transaction block.
"""

from __future__ import annotations

from enum import StrEnum


def _check_sql(column: str, values: tuple[str, ...]) -> str:
    return f"{column} IN (" + ", ".join(f"'{value}'" for value in values) + ")"


class UserRole(StrEnum):
    ADMIN = "admin"
    TEACHER = "teacher"
    STUDENT = "student"


class ExamStatus(StrEnum):
    DRAFT = "draft"
    PUBLISHED = "published"
    RUNNING = "running"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class JoinRequestStatus(StrEnum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"


class AttemptStatus(StrEnum):
    ACTIVE = "active"
    SUBMITTED = "submitted"
    AUTO_SUBMITTED = "auto_submitted"
    TERMINATED = "terminated"


class AnswerStatus(StrEnum):
    PENDING = "pending"
    EVALUATED = "evaluated"


class ResultStatus(StrEnum):
    PENDING = "pending"
    PUBLISHED = "published"


class SecurityEventType(StrEnum):
    """What the device reported (§39).

    These are observations, not accusations. Several have innocent explanations - a
    phone call arrives, the network drops - so the record exists for a human
    invigilator to interpret, and the platform never draws a conclusion from it.
    """

    APP_BACKGROUND = "APP_BACKGROUND"
    APP_FOREGROUND = "APP_FOREGROUND"
    SCREENSHOT_ATTEMPT = "SCREENSHOT_ATTEMPT"
    SCREEN_RECORDING = "SCREEN_RECORDING"
    EXTERNAL_ACTIVITY = "EXTERNAL_ACTIVITY"
    NETWORK_DISCONNECT = "NETWORK_DISCONNECT"
    NETWORK_RECONNECT = "NETWORK_RECONNECT"
    DEVICE_TIME_CHANGE = "DEVICE_TIME_CHANGE"
    EXAM_RESTART = "EXAM_RESTART"
    LOCKDOWN_ENGAGED = "LOCKDOWN_ENGAGED"
    LOCKDOWN_UNAVAILABLE = "LOCKDOWN_UNAVAILABLE"

    # Conditions the device can see but not prevent. Each is reported once, when the
    # exam starts or when it changes, so a trail says what the room was actually like.
    DEVELOPER_MODE = "DEVELOPER_MODE"
    USB_DEBUGGING = "USB_DEBUGGING"
    SPLIT_SCREEN = "SPLIT_SCREEN"
    EXTERNAL_DISPLAY = "EXTERNAL_DISPLAY"
    OVERLAY_DETECTED = "OVERLAY_DETECTED"


class SecuritySeverity(StrEnum):
    INFO = "info"
    WARNING = "warning"
    CRITICAL = "critical"


class NotificationCategory(StrEnum):
    """What happened (§61). The category decides the icon and where a tap leads."""

    EXAM_PUBLISHED = "exam_published"
    JOIN_REQUEST_RECEIVED = "join_request_received"
    JOIN_REQUEST_APPROVED = "join_request_approved"
    JOIN_REQUEST_REJECTED = "join_request_rejected"
    EXAM_SUBMITTED = "exam_submitted"
    RESULT_PUBLISHED = "result_published"


class QuestionType(StrEnum):
    TEXT_MCQ = "TEXT_MCQ"
    IMAGE_TEXT_OPTIONS = "IMAGE_TEXT_OPTIONS"
    IMAGE_IMAGE_OPTIONS = "IMAGE_IMAGE_OPTIONS"
    SHORT_ANSWER = "SHORT_ANSWER"
    CODE_ANSWER = "CODE_ANSWER"

    #: The student works on paper and photographs it. For anything a keyboard is the
    #: wrong tool for -- a derivation, a circuit, a proof -- where typing the answer
    #: would test transcription rather than the subject.
    PHOTO_ANSWER = "PHOTO_ANSWER"


ROLE_VALUES: tuple[str, ...] = tuple(role.value for role in UserRole)
JOIN_REQUEST_STATUS_VALUES: tuple[str, ...] = tuple(s.value for s in JoinRequestStatus)
ATTEMPT_STATUS_VALUES: tuple[str, ...] = tuple(s.value for s in AttemptStatus)
ANSWER_STATUS_VALUES: tuple[str, ...] = tuple(s.value for s in AnswerStatus)
RESULT_STATUS_VALUES: tuple[str, ...] = tuple(s.value for s in ResultStatus)
SECURITY_EVENT_VALUES: tuple[str, ...] = tuple(e.value for e in SecurityEventType)
SECURITY_SEVERITY_VALUES: tuple[str, ...] = tuple(s.value for s in SecuritySeverity)
NOTIFICATION_CATEGORY_VALUES: tuple[str, ...] = tuple(
    c.value for c in NotificationCategory
)
EXAM_STATUS_VALUES: tuple[str, ...] = tuple(status.value for status in ExamStatus)
QUESTION_TYPE_VALUES: tuple[str, ...] = tuple(kind.value for kind in QuestionType)

# Types answered by choosing one option; the rest are answered with free text.
CHOICE_QUESTION_TYPES: frozenset[str] = frozenset(
    {
        QuestionType.TEXT_MCQ.value,
        QuestionType.IMAGE_TEXT_OPTIONS.value,
        QuestionType.IMAGE_IMAGE_OPTIONS.value,
    }
)

# Types a machine cannot mark on submission; a teacher (or, later, the sandbox) does.
MANUAL_QUESTION_TYPES: frozenset[str] = frozenset(
    {
        QuestionType.SHORT_ANSWER.value,
        QuestionType.CODE_ANSWER.value,
        # Nothing can mark a photograph of handwriting but a person.
        QuestionType.PHOTO_ANSWER.value,
    }
)

# Types whose stem is an image the student must be shown.
IMAGE_STEM_TYPES: frozenset[str] = frozenset(
    {QuestionType.IMAGE_TEXT_OPTIONS.value, QuestionType.IMAGE_IMAGE_OPTIONS.value}
)

ROLE_CHECK_SQL: str = _check_sql("role", ROLE_VALUES)
EXAM_STATUS_CHECK_SQL: str = _check_sql("status", EXAM_STATUS_VALUES)
QUESTION_TYPE_CHECK_SQL: str = _check_sql("type", QUESTION_TYPE_VALUES)
JOIN_REQUEST_STATUS_CHECK_SQL: str = _check_sql("status", JOIN_REQUEST_STATUS_VALUES)
ATTEMPT_STATUS_CHECK_SQL: str = _check_sql("status", ATTEMPT_STATUS_VALUES)
ANSWER_STATUS_CHECK_SQL: str = _check_sql("status", ANSWER_STATUS_VALUES)
RESULT_STATUS_CHECK_SQL: str = _check_sql("status", RESULT_STATUS_VALUES)
SECURITY_EVENT_CHECK_SQL: str = _check_sql("event_type", SECURITY_EVENT_VALUES)
SECURITY_SEVERITY_CHECK_SQL: str = _check_sql("severity", SECURITY_SEVERITY_VALUES)
NOTIFICATION_CATEGORY_CHECK_SQL: str = _check_sql(
    "category", NOTIFICATION_CATEGORY_VALUES
)

# How seriously to treat each observation by default. Leaving the app is routine on a
# personal phone; a screen recorder running is not.
DEFAULT_EVENT_SEVERITY: dict[str, str] = {
    SecurityEventType.APP_BACKGROUND.value: SecuritySeverity.WARNING.value,
    SecurityEventType.APP_FOREGROUND.value: SecuritySeverity.INFO.value,
    SecurityEventType.SCREENSHOT_ATTEMPT.value: SecuritySeverity.CRITICAL.value,
    SecurityEventType.SCREEN_RECORDING.value: SecuritySeverity.CRITICAL.value,
    SecurityEventType.EXTERNAL_ACTIVITY.value: SecuritySeverity.WARNING.value,
    SecurityEventType.NETWORK_DISCONNECT.value: SecuritySeverity.INFO.value,
    SecurityEventType.NETWORK_RECONNECT.value: SecuritySeverity.INFO.value,
    SecurityEventType.DEVICE_TIME_CHANGE.value: SecuritySeverity.WARNING.value,
    SecurityEventType.EXAM_RESTART.value: SecuritySeverity.WARNING.value,
    SecurityEventType.LOCKDOWN_ENGAGED.value: SecuritySeverity.INFO.value,
    SecurityEventType.LOCKDOWN_UNAVAILABLE.value: SecuritySeverity.WARNING.value,
    # Developer mode and USB debugging are ordinary on a developer's own phone and
    # meaningless on their own; they matter as context beside something else.
    SecurityEventType.DEVELOPER_MODE.value: SecuritySeverity.INFO.value,
    SecurityEventType.USB_DEBUGGING.value: SecuritySeverity.WARNING.value,
    # These three put something else on screen beside the paper.
    SecurityEventType.SPLIT_SCREEN.value: SecuritySeverity.CRITICAL.value,
    SecurityEventType.EXTERNAL_DISPLAY.value: SecuritySeverity.CRITICAL.value,
    SecurityEventType.OVERLAY_DETECTED.value: SecuritySeverity.CRITICAL.value,
}

# An attempt in progress. Anything else is finished and frozen.
OPEN_ATTEMPT_STATUSES: frozenset[str] = frozenset({AttemptStatus.ACTIVE.value})

# An exam may only be edited while it is a draft; publishing freezes it.
EDITABLE_EXAM_STATUSES: frozenset[str] = frozenset({ExamStatus.DRAFT.value})

#: Types answered by photographing work done on paper.
PHOTO_QUESTION_TYPES: frozenset[str] = frozenset({QuestionType.PHOTO_ANSWER.value})

#: How many photographs one answer may hold.
#:
#: Three covers a page and its overflow without becoming an upload channel. Enforced by
#: the server, not only by the button: a cap that lives in the UI is a suggestion.
MAX_ANSWER_PHOTOS = 3
