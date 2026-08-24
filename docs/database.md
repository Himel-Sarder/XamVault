# UniExam — Database Design

Engine: **PostgreSQL** (Render for development). ORM: **SQLAlchemy 2.x**. Migrations: **Alembic**.

Legend: 🟢 = created by the Phase 1 migration · ⚪ = designed now, migrated in its own phase.

---

## 1. Entity–Relationship diagram

### 1.1 Identity & academic core 🟢

```mermaid
erDiagram
    DEPARTMENTS ||--o{ USERS : "belongs to"
    DEPARTMENTS ||--o{ COURSES : offers
    DEPARTMENTS ||--o{ STUDENT_PROFILES : "belongs to"
    DEPARTMENTS ||--o{ TEACHER_PROFILES : "belongs to"
    USERS ||--o| STUDENT_PROFILES : has
    USERS ||--o| TEACHER_PROFILES : has
    USERS ||--o{ COURSES : creates
    USERS ||--o{ COURSE_ENROLLMENTS : "enrolled as student"
    COURSES ||--o{ COURSE_ENROLLMENTS : has
    USERS ||--o{ REFRESH_TOKENS : holds

    DEPARTMENTS {
        int id PK
        string code UK
        string name
        bool is_active
    }
    USERS {
        int id PK
        string user_id UK "login id, e.g. 20261234"
        string password_hash
        string name
        string email UK
        string role "admin|teacher|student"
        int department_id FK
        bool is_active
        timestamptz created_at
        timestamptz updated_at
    }
    STUDENT_PROFILES {
        int id PK
        int user_id FK
        string student_id UK
        int department_id FK
        int semester
        string session
    }
    TEACHER_PROFILES {
        int id PK
        int user_id FK
        string teacher_id UK
        int department_id FK
        string designation
    }
    COURSES {
        int id PK
        string course_code
        string course_name
        int department_id FK
        int semester
        string session
        int created_by FK
        bool is_active
        timestamptz created_at
    }
    COURSE_ENROLLMENTS {
        int id PK
        int course_id FK
        int student_id FK
        timestamptz created_at
    }
    REFRESH_TOKENS {
        int id PK
        string jti UK
        int user_id FK
        timestamptz expires_at
        timestamptz revoked_at
    }
```

### 1.2 Exams, questions & attempts ⚪

```mermaid
erDiagram
    COURSES ||--o{ EXAMS : hosts
    USERS ||--o{ EXAMS : authors
    EXAMS ||--|| EXAM_SETTINGS : configures
    EXAMS ||--o{ EXAM_QUESTIONS : contains
    QUESTIONS ||--o{ EXAM_QUESTIONS : "snapshotted into"
    QUESTIONS ||--o{ QUESTION_OPTIONS : has
    QUESTIONS ||--o{ CODE_TEST_CASES : "verified by"
    EXAMS ||--o{ JOIN_REQUESTS : receives
    USERS ||--o{ JOIN_REQUESTS : requests
    EXAMS ||--o{ EXAM_ATTEMPTS : "attempted in"
    USERS ||--o{ EXAM_ATTEMPTS : attempts
    EXAM_ATTEMPTS ||--o{ ATTEMPT_QUESTIONS : freezes
    EXAM_ATTEMPTS ||--o{ STUDENT_ANSWERS : records
    EXAM_ATTEMPTS ||--o{ CODE_SUBMISSIONS : records
    EXAM_ATTEMPTS ||--o{ SECURITY_EVENTS : emits
    EXAM_ATTEMPTS ||--|| RESULTS : produces

    EXAMS {
        int id PK
        int course_id FK
        int teacher_id FK
        string title
        text description
        timestamptz start_at
        int duration_minutes
        timestamptz expires_at
        int total_marks
        string status "draft|published|running|completed|cancelled"
        timestamptz published_at
    }
    EXAM_SETTINGS {
        int id PK
        int exam_id FK
        bool shuffle_questions
        bool shuffle_answers
        bool allow_back_navigation
        bool auto_submit
        bool secure_mode
        bool show_result_immediately
        int max_attempts
    }
    QUESTIONS {
        int id PK
        string type "TEXT_MCQ|IMAGE_TEXT_OPTIONS|IMAGE_IMAGE_OPTIONS|SHORT_ANSWER|CODE_ANSWER"
        text question_text
        string question_image_url
        int marks
        string difficulty
        string topic
        int created_by FK
    }
    QUESTION_OPTIONS {
        int id PK
        int question_id FK
        text option_text
        string option_image_url
        int display_order
        bool is_correct "never serialised to students"
    }
    EXAM_QUESTIONS {
        int id PK
        int exam_id FK
        int question_id FK
        jsonb question_snapshot "immutable copy taken at publish"
        int marks_snapshot
        int display_order
    }
    CODE_TEST_CASES {
        int id PK
        int question_id FK
        text stdin
        text expected_stdout
        bool is_hidden
        int weight
    }
    JOIN_REQUESTS {
        int id PK
        int exam_id FK
        int student_id FK
        string status "pending|approved|rejected"
        timestamptz requested_at
        timestamptz reviewed_at
        int reviewed_by FK
    }
```

### 1.3 Attempt runtime, grading & cross-cutting ⚪

```mermaid
erDiagram
    EXAM_ATTEMPTS {
        int id PK
        int exam_id FK
        int student_id FK
        timestamptz started_at
        timestamptz expires_at "server-owned, never client-supplied"
        timestamptz submitted_at
        string status "active|submitted|auto_submitted|terminated"
        jsonb question_order
        jsonb option_orders
    }
    ATTEMPT_QUESTIONS {
        int id PK
        int attempt_id FK
        int exam_question_id FK
        int display_order
    }
    STUDENT_ANSWERS {
        int id PK
        int attempt_id FK
        int question_id FK
        int selected_option_id FK
        text answer_text
        numeric marks_awarded
        text feedback
        int evaluated_by FK
        timestamptz evaluated_at
        string status "pending|evaluated"
    }
    CODE_SUBMISSIONS {
        int id PK
        int attempt_id FK
        int question_id FK
        string language
        text source_code
        string status "queued|running|done|error"
        jsonb run_result
        numeric marks_awarded
    }
    RESULTS {
        int id PK
        int exam_id FK
        int student_id FK
        int attempt_id FK
        numeric mcq_score
        numeric short_answer_score
        numeric code_score
        numeric total_score
        numeric percentage
        string status "pending|published"
        timestamptz published_at
    }
    SECURITY_EVENTS {
        int id PK
        int attempt_id FK
        int student_id FK
        string event_type
        timestamptz timestamp
        jsonb metadata
        string severity
    }
    NOTIFICATIONS {
        int id PK
        int user_id FK
        string title
        text body
        string category
        bool is_read
        jsonb payload
    }
    AUDIT_LOGS {
        int id PK
        int actor_id FK
        string action
        string entity_type
        int entity_id
        jsonb metadata
        string ip_address
    }
    EXAM_ATTEMPTS ||--o{ ATTEMPT_QUESTIONS : freezes
    EXAM_ATTEMPTS ||--o{ STUDENT_ANSWERS : records
    EXAM_ATTEMPTS ||--o{ CODE_SUBMISSIONS : records
    EXAM_ATTEMPTS ||--o{ SECURITY_EVENTS : emits
    EXAM_ATTEMPTS ||--|| RESULTS : produces
```

---

## 2. Phase 1 PostgreSQL schema (authoritative)

Produced by `alembic upgrade head`. Enumerations are stored as **VARCHAR + CHECK**, not
native PostgreSQL `ENUM` types: adding a role or status later becomes an ordinary
migration instead of an `ALTER TYPE`, and the identical DDL also runs on SQLite, which is
what the test suite uses.

```sql
CREATE TABLE departments (
    id          SERIAL PRIMARY KEY,
    code        VARCHAR(20)  NOT NULL UNIQUE,
    name        VARCHAR(150) NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id             SERIAL PRIMARY KEY,
    user_id        VARCHAR(50)  NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    name           VARCHAR(150) NOT NULL,
    email          VARCHAR(255) UNIQUE,
    role           VARCHAR(20)  NOT NULL,
    department_id  INTEGER      REFERENCES departments(id) ON DELETE SET NULL,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_users_role CHECK (role IN ('admin','teacher','student'))
);
CREATE INDEX ix_users_role          ON users(role);
CREATE INDEX ix_users_department_id ON users(department_id);

CREATE TABLE student_profiles (
    id             SERIAL PRIMARY KEY,
    user_id        INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    student_id     VARCHAR(50) NOT NULL UNIQUE,
    department_id  INTEGER REFERENCES departments(id) ON DELETE SET NULL,
    semester       INTEGER,
    session        VARCHAR(20),
    CONSTRAINT ck_student_profiles_semester
        CHECK (semester IS NULL OR (semester >= 1 AND semester <= 12))
);

CREATE TABLE teacher_profiles (
    id             SERIAL PRIMARY KEY,
    user_id        INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    teacher_id     VARCHAR(50) NOT NULL UNIQUE,
    department_id  INTEGER REFERENCES departments(id) ON DELETE SET NULL,
    designation    VARCHAR(100)
);

CREATE TABLE courses (
    id             SERIAL PRIMARY KEY,
    course_code    VARCHAR(30)  NOT NULL,
    course_name    VARCHAR(200) NOT NULL,
    department_id  INTEGER REFERENCES departments(id) ON DELETE SET NULL,
    semester       INTEGER,
    session        VARCHAR(20),
    created_by     INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_courses_code_session UNIQUE (course_code, session)
);
CREATE INDEX ix_courses_created_by    ON courses(created_by);
CREATE INDEX ix_courses_department_id ON courses(department_id);

CREATE TABLE course_enrollments (
    id          SERIAL PRIMARY KEY,
    course_id   INTEGER NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    student_id  INTEGER NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_enrollment_course_student UNIQUE (course_id, student_id)
);
CREATE INDEX ix_course_enrollments_student_id ON course_enrollments(student_id);

CREATE TABLE refresh_tokens (
    id          SERIAL PRIMARY KEY,
    jti         VARCHAR(64) NOT NULL UNIQUE,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at  TIMESTAMPTZ NOT NULL,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ix_refresh_tokens_user_id ON refresh_tokens(user_id);
```

`refresh_tokens` is not in the original table list, but refresh-token **rotation and
revocation** are impossible without server-side state: with stateless refresh tokens a
stolen token stays valid until it expires and logout cannot be enforced.

---

## 3. Integrity rules that live in the database

Constraints, not conventions — an application bug cannot violate them.

| Rule | Mechanism | Phase |
|---|---|---|
| One login id per user | `users.user_id UNIQUE` | 1 |
| At most one profile per user | `student_profiles.user_id UNIQUE`, `teacher_profiles.user_id UNIQUE` | 1 |
| A student enrols in a course at most once | `UNIQUE (course_id, student_id)` | 1 |
| Role is one of three values | `CHECK (role IN ('admin','teacher','student'))` | 1 |
| Course code reusable across sessions, unique within one | `UNIQUE (course_code, session)` | 1 |
| A refresh token can be used once | `jti UNIQUE` + `revoked_at` set on rotation | 1 |
| One attempt running per (exam, student) | partial unique index on `(exam_id, student_id) WHERE status = 'active'` — **live** | 9 |
| No duplicate pending join request | partial unique index on `(exam_id, student_id) WHERE status = 'pending'` — **live** | 8 |
| One result per attempt | `results.attempt_id UNIQUE` — **live**; makes submission idempotent | 16 |
| One answer per (attempt, question) | `UNIQUE (attempt_id, exam_question_id)` — **live** | 9 |
| An attempt cannot be submitted twice | `UPDATE ... WHERE status = 'active'`, checked rowcount — **live** | 9 |

## 4. Connection & pooling

`DATABASE_URL` is read from the environment and normalised at startup
(`postgres://` → `postgresql+psycopg://`, the scheme Render hands out vs. the one
SQLAlchemy 2.x needs). Render's managed Postgres drops idle connections, so the engine
sets `pool_pre_ping=True` and `pool_recycle=1800`; pool size is an env var because a free
instance permits far fewer connections than a paid one.

## 5. Migration workflow

```bash
alembic revision --autogenerate -m "describe the change"   # always review the output
alembic upgrade head
alembic downgrade -1                                       # every revision must reverse
```

The production schema is never edited by hand.
