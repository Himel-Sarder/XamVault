# UniExam — API Design

Base path: `/api/v1` · Auth: `Authorization: Bearer <access_token>` · Content: JSON
(multipart only for uploads). Interactive docs: `/docs` (disabled when `ENV=production`).

## 1. Conventions

| Concern | Rule |
|---|---|
| Errors | `{"detail": "...", "code": "SNAKE_CASE"}` with the right status |
| Time | every timestamp is UTC ISO-8601 with offset (`2026-08-23T10:00:00+00:00`) |
| Paging | `?page=1&page_size=20` → `{"items": [...], "total": n, "page": 1, "page_size": 20}` |
| Ids | server-assigned integers; clients never propose ids |
| Idempotency | re-submitting a completed action returns the existing state, not a duplicate |

Status codes: `400` malformed, `401` missing/invalid token, `403` authenticated but not
permitted (includes "not your object"), `404` absent *or* not visible to you, `409`
conflict (duplicate enrolment, already submitted), `422` schema validation, `429` rate
limited.

`403` vs `404`: the API returns `404` when revealing existence would itself leak
information (another teacher's exam), and `403` when the object is legitimately visible but
the action is not allowed.

## 2. Implemented in Phase 1

### Health
```
GET  /health                    → {"status":"ok","database":"ok","version":"..."}
```
No auth. Used by Render's health check. Returns `503` when the database is unreachable so
a broken instance is not kept in rotation.

### Auth — `/api/v1/auth`
```
POST /auth/login                {user_id, password}      → TokenResponse
POST /auth/refresh              {refresh_token}          → TokenResponse   (rotates)
POST /auth/logout               {refresh_token}          → 204             (revokes)
GET  /auth/me                   —                        → UserResponse
POST /auth/change-password      {current_password, new_password} → 204     (revokes all)
```

`TokenResponse`:
```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "bearer",
  "expires_in": 1800,
  "user": {"id": 1, "user_id": "20261234", "name": "Student Name", "role": "student"}
}
```

Login is rate limited per IP. A wrong password and an unknown user id produce the same
message and comparable timing — the endpoint is not a user-id oracle.

### Users — `/api/v1/users`
```
GET  /users/me                  —                → UserProfileResponse (incl. profile)
GET  /users                     admin            → paged UserResponse
POST /users                     admin            → UserResponse   (creates user + profile)
GET  /users/{id}                admin            → UserResponse
PATCH /users/{id}               admin            → UserResponse   (name/email/active/dept)
```

### Departments — `/api/v1/departments`
```
GET  /departments               any role         → [DepartmentResponse]
POST /departments               admin            → DepartmentResponse
GET  /departments/{id}          any role         → DepartmentResponse
PATCH /departments/{id}         admin            → DepartmentResponse
```

### Courses — `/api/v1/courses`
```
GET  /courses                   role-scoped      → paged CourseResponse
POST /courses                   teacher, admin   → CourseResponse
GET  /courses/{id}              must be visible  → CourseResponse
PATCH /courses/{id}             owner, admin     → CourseResponse
POST /courses/{id}/enrollments  owner, admin     → EnrollmentResponse
GET  /courses/{id}/enrollments  owner, admin     → [EnrollmentResponse]
DELETE /courses/{id}/enrollments/{student_id}  owner, admin → 204
```

`GET /courses` is *scoped by role inside the query*, not filtered after the fact:

- student → courses they are enrolled in
- teacher → courses they created
- admin → all courses

### Exams — `/api/v1/exams` (teacher/admin)

```
POST   /exams                              → TeacherExamResponse   (draft)
GET    /exams            ?course_id&status → paged TeacherExamResponse
GET    /exams/{id}                         → TeacherExamResponse
PATCH  /exams/{id}                         → TeacherExamResponse   (draft only)
PUT    /exams/{id}/settings                → TeacherExamResponse   (draft only)
DELETE /exams/{id}                         → 204                   (draft only)

GET    /exams/{id}/publish-check           → PublishCheckResponse
POST   /exams/{id}/publish                 → TeacherExamResponse

GET    /exams/{id}/questions               → [ExamQuestionResponse]
POST   /exams/{id}/questions               → ExamQuestionResponse  (draft only)
PUT    /exams/{id}/questions/order         → [ExamQuestionResponse] (draft only)
PUT    /exams/{id}/questions/{qid}         → ExamQuestionResponse  (draft only)
DELETE /exams/{id}/questions/{qid}         → 204                   (draft only)
```

Server-owned on every one of these: `teacher_id`, `status`, `total_marks`, `expires_at`,
`published_at`, `display_order` and `is_correct` scoring. None appears on a `*Create`
schema, so a client cannot propose them even by sending them. `total_marks` is recomputed
from the attached questions after every change; `expires_at` is derived at publish from
`start_at + duration_minutes`.

**Publish validation.** `POST /exams/{id}/publish` returns `422` with *every* failed check
at once, not just the first:

```json
{
  "detail": "This exam is not ready to publish",
  "code": "validation_failed",
  "issues": [
    {"field": "questions", "message": "Add at least one question before publishing"},
    {"field": "start_at",  "message": "Set the date and time the exam starts"}
  ]
}
```

`GET /exams/{id}/publish-check` returns the same list without attempting the publish, so
the UI can disable the button and explain why.

**Freezing.** Publishing writes an immutable `question_snapshot` (including the answer
key) for every attached question and flips the exam out of `draft`. From then on every
mutating route returns `409 exam_not_editable`. Editing the underlying question — which
the Phase 6 question bank will allow, since a question can be reused — cannot change an
exam students have already been shown.

**Question types.** All five types from §14 are accepted, and validation is *per type*
rather than one-size-fits-all:

| Type | Requires | Marked by |
|---|---|---|
| `TEXT_MCQ` | 2–8 distinct text options, exactly one correct | server, at submission |
| `IMAGE_TEXT_OPTIONS` | a question image, plus text options as above | server, at submission |
| `IMAGE_IMAGE_OPTIONS` | a question image, and an image on every option | server, at submission |
| `SHORT_ANSWER` | no options | the teacher, afterwards |
| `CODE_ANSWER` | no options; a language, and optional time/memory limits | the teacher, afterwards |

Sending options with a written type, a language with a non-code type, or an image type
without its image is `422`.

### Image upload — `POST /api/v1/questions/upload-image`

Multipart, teacher only. Returns `{url, width, height, bytes}`; the `url` is what goes
into `question_image_url` or `option_image_url`.

A file is accepted only when *every* check passes: size under `MAX_UPLOAD_SIZE_MB` (read
in chunks, so an oversized upload is rejected without being held in memory), decodable by
Pillow, a format on the allow-list, and dimensions between 16 and 4096 px. The decode is
the check that matters — a shell script named `diagram.png` with `Content-Type:
image/png` fails here, where trusting the extension or the header would let it through.
The stored filename is a server-generated UUID; the client's name is never used as a path
component.

In development the files are served from `/uploads`; in production that mount does not
exist and `UPLOAD_DIR` is replaced by object storage.

### Student view of exams

`GET /exams` and `GET /exams/{id}` are **role-dispatched**: the response *class* differs
by who asks, which is what keeps teacher-only fields away from students. A student gets
`StudentExamResponse` — no `teacher_id`, no `status`, no `published_at`, no answer key —
plus state the server computes for them:

```json
{
  "id": 1, "course_code": "CSE-301", "title": "Mid Term Quiz",
  "start_at": "...", "duration_minutes": 30, "expires_at": "...",
  "total_marks": 8, "question_count": 2,
  "availability": "upcoming",          // upcoming | open | closed
  "join_request_status": "none",       // none | pending | approved | rejected
  "can_request_join": true,
  "settings": {"secure_mode": true, "allow_back_navigation": true, "max_attempts": 1}
}
```

The list is scoped inside the query to published exams in courses the student is enrolled
in, on an active course. Finished exams are omitted unless `?include_closed=true`. A
student asking for any other exam gets `404` — whether it is a draft, another cohort's, or
absent, so nothing is disclosed either way.

Because the two roles get different classes, `response_model` is deliberately omitted on
these two routes and the correct schema is constructed in the handler; the OpenAPI entry
documents both shapes in its description.

### Join requests — `/api/v1`

```
POST   /exams/{id}/join-request                 student  → JoinRequestResponse (pending)
GET    /exams/{id}/join-requests    ?status     owner    → [JoinRequestResponse]
POST   /exams/{id}/join-requests/approve-all    owner    → BulkReviewResponse
POST   /exams/{id}/join-requests/reject-all     owner    → BulkReviewResponse
POST   /join-requests/{id}/approve              owner    → JoinRequestResponse
POST   /join-requests/{id}/reject               owner    → JoinRequestResponse
GET    /join-requests/mine                      student  → [StudentJoinRequestResponse]
```

Rules, all enforced server-side:

| Situation | Result |
|---|---|
| Request for an exam the student cannot see | `404` |
| Request while one is already pending | `409 request_pending` |
| Request after approval | `409 already_approved` |
| Request after the exam window closed | `409 exam_closed` |
| Request after a rejection | allowed — a rejection is not a permanent ban |
| Deciding a request already decided | `409 already_reviewed` |
| Deciding a request on another teacher's exam | `404` |
| Student calling approve/reject | `403` |

The "no duplicate pending request" rule is a **partial unique index**
(`UNIQUE (exam_id, student_id) WHERE status = 'pending'`), not just a service check — so
two requests fired at once cannot both land. The service catches the resulting
`IntegrityError` and returns the same `409`.

Bulk review accepts an optional `request_ids` list. The app always sends the ids that were
on screen, so a request that arrived after the list loaded is left for the teacher to look
at rather than being swept up unseen. The whole batch is applied in one transaction.

The bulk routes are nested under the exam (`/exams/{id}/join-requests/approve-all`) rather
than the flat `/join-requests/approve-all` sketched in the original spec: the exam is the
authorization target, and putting it in the path means it cannot be omitted.

### Attempts — `/api/v1`

```
POST   /exams/{id}/start                student  → AttemptResponse (starts or resumes)
GET    /attempts/{id}                   owner    → AttemptResponse (restores state)
POST   /attempts/{id}/answers           owner    → AnswerAck
POST   /attempts/{id}/submit            owner    → SubmitResponse
```

`POST /exams/{id}/start` evaluates every condition in §32 server-side:

| Condition | Failure |
|---|---|
| Published, and in a course the student is enrolled in | `404` (one query enforces both) |
| Join request approved | `403 not_approved` |
| Server clock ≥ `start_at` | `409 not_started` |
| Server clock < `expires_at` | `409 exam_closed` |
| Attempts remaining under `max_attempts` | `409 no_attempts_left` |
| Exam has questions | `409 exam_empty` |

Calling it again while an attempt is running **resumes** that attempt — same id, same
`started_at`, same `expires_at`, same question order. An app restart must not hand out a
fresh clock.

**The clock.** `expires_at` is written once, as `min(started_at + duration, exam.expires_at)`
— a late start does not extend the exam past its own window. `remaining_seconds` is
recomputed from the server clock on every response, including every answer save, so the
client's countdown is re-synced constantly and is purely cosmetic. A partial unique index
(`WHERE status = 'active'`) means a student cannot have two attempts running at once.

**Randomisation** (§35, §36). `question_order` and `option_orders` are generated once at
creation and stored on the attempt. `option_orders` holds option **ids**, not letters —
the letter a student saw is meaningless when grading. Order is stable across reloads and
differs per student.

**The paper carries no answer key.** `AttemptOptionResponse` declares `id`,
`option_text`, `option_image_url` and nothing else, so `is_correct` cannot appear in a
response a student is looking at.

**Submission** (§41) is one transaction, guarded by
`UPDATE ... WHERE status = 'active'`: two racing submissions both try to move the row out
of `active` and only one can, so an attempt is never graded twice. A second attempt
returns `409 already_submitted`; answering afterwards returns `409 attempt_closed`. A
submission that arrives after the deadline is recorded as `auto_submitted` — accurate, and
it still keeps the answers.

**Auto-submit** (§42) has three layers: the app asks the server when its countdown hits
zero; the server closes an expired attempt whenever one is read; and
`python -m app.utils.sweep_attempts` closes the rest, for a device that died mid-exam and
never came back. Schedule the last as a cron job.

### Grading and results — `/api/v1`

```
GET    /results                         student  → [StudentResultResponse]  (published only)
GET    /results/{id}                    owner    → StudentResultResponse
GET    /exams/{id}/results              owner    → [TeacherResultResponse]
POST   /exams/{id}/results/publish      owner    → PublishResultsResponse
```

MCQ marking (§43) runs at submission, scored against the **snapshot** frozen at publish —
a question edited afterwards cannot change a mark already earned. Scores are split by
question kind (`mcq` / `short_answer` / `code`) because each is graded by a different
mechanism; the latter two are `0` until their phases land. `total_score` and `percentage`
are derived, never client-supplied.

A result is `pending` until the teacher releases it, unless the exam sets
`show_result_immediately`. A student's own unpublished result returns `404`, the same as
one that does not exist — learning that a mark exists but is being withheld is itself a
disclosure. Publishing is one transaction over every pending result for the exam;
publishing twice returns `409 nothing_to_publish`.

## 2b. Bulk enrolment

`POST /courses/{course_id}/enrollments/bulk` — course owner or admin.

```json
{ "student_user_ids": ["20261234", "20261235", "ghost-id"] }
```

```json
{
  "enrolled": [{ "id": 80, "user_id": "20261234", "name": "Demo Student", "role": "student" }],
  "skipped": [{ "student_user_id": "ghost-id", "reason": "not_found" }]
}
```

`reason` is one of `not_found`, `not_a_student`, `deactivated`, `already_enrolled`.

Two things distinguish it from `POST /exams/{id}/join-requests/approve-all`, which is
all-or-nothing. First, its input is a roll list a human typed or pasted, so a bad entry
is expected rather than exceptional; refusing fifty-nine good ids over one typo would
help nobody. Second, the caller needs to know *which* ids failed — a bare count sends a
teacher back to compare two lists by eye, which is the work the batch was meant to save.

The whole batch still commits once, so nothing is left half-written, and 200 is returned
even when nothing was created: an all-duplicate list is a legitimate outcome, not an
error. At most 200 ids per request; repeats within one list are collapsed before any
lookup, so a duplicate is not reported as "already enrolled".

## 2c. Removing things

`DELETE /notifications/{id}` and `DELETE /notifications/read` — your own inbox only.

Safe outright, unlike most deletion in this API: a notification is a *copy* of news, not
the news itself. Removing "your result is available" leaves the result exactly where it
was. `DELETE /notifications/read` clears only what has been read, and returns
`{"cleared": n}` — it must never be able to remove something the reader has not seen.

`DELETE /exams/{id}` — two gates.

An exam **nobody has sat** goes straight away, draft or published. It holds nothing
worth keeping, and refusing would leave a teacher unable to clear their own mistakes.
Publishing freezes the questions; it does not commit anyone to keeping a mistake.

An exam students **have** sat must be cancelled first, otherwise `409
exam_has_attempts`. That is not bureaucracy: cancelling destroys nothing, so it leaves
the teacher in a state where the exam is already stopped and they can see exactly what
they would be throwing away before they throw it away. Deleting straight from published
would make one tap the difference between a live exam and a cohort's results being gone.

Once cancelled, deleting removes the attempts, answers and results too. The single-exam
read carries `attempt_count` so the confirmation can name that number *before* the act
rather than explaining it after.

`POST /exams/{id}/cancel` — for exactly that refused case.

Nothing is removed. Attempts, answers and released results all stay readable. The exam
simply stops being `published`, and starting an attempt already requires that, so no new
sitting can begin. A cancelled exam also stops being visible to students who had not sat
it, so *their* requests to start it return 404 rather than a refusal — the same
"not visible means not found" convention the rest of the API follows.

This is the same shape as departments and users, which are archived and deactivated
rather than deleted: destroy what nothing depends on, and stop the rest.

## 2d. Deleting an account

`GET /users/{id}/deletion-impact` then `DELETE /users/{id}` — admin only.

Three refusals, each for its own reason.

**Your own account** (`cannot_delete_self`). There may be no other administrator, and
the account cannot restore itself. Checked before the deactivate-first rule, because
deactivating yourself locks you out at the next request — so this is the only point at
which the message still reaches the person who needs it.

**An active account** (`deactivate_first`). Deactivating is the reversible version of
the same intent, so doing it first means nobody destroys a live account in one step.
Same shape as cancelling an exam before deleting it.

**An author of courses, exams or questions** (`user_owns_content`). This one is not a
policy choice: those columns are `ON DELETE RESTRICT`, because an exam other students
sat must not lose its author. Checking in the service turns an integrity error into a
sentence an administrator can act on.

What does go: the person's own attempts, answers, results, enrolments, notifications,
sessions and uploads, by database cascade. `deletion-impact` returns those counts so the
confirmation names them before the act rather than after.

> Note: SQLite ignores foreign keys unless told otherwise, so before the pragma was
> added neither the cascade nor the RESTRICT was exercised by any test. Both are now.

## 2e. Assigning a course to a teacher

`POST /courses/{id}/assign` with `{"teacher_user_id": "T1001"}` — admin only.

Ownership of a course is `created_by`, and that is what decides who may edit it, publish
exams on it and manage its roll. So assigning is the act of putting somebody in charge
of running it, and it is administrative rather than editorial: a teacher cannot hand
their own course to someone else.

It deliberately does **not** move the exams already written on the course. An exam
carries its own `teacher_id`, its results point at that person, and rewriting authorship
because the course changed hands would misattribute somebody's work. The response says
how many stayed:

```json
{ "course": { ... }, "exams_kept_by_previous_teacher": 2 }
```

That count exists so an administrator learns it from the response rather than from a
teacher who cannot open a paper they expected to inherit.

Refused for a student or a deactivated account (`400 not_a_teacher`,
`400 user_deactivated`) and for the teacher who already holds it (`409 already_assigned`).

Every course response now carries `teacher_name`, eager-loaded with the page, so a list
of every course in the system can be read without resolving integers by hand.

## 3. Planned surface (later phases)

```
/api/v1/questions            standalone CRUD, TeacherQuestionResponse only
/api/v1/question-bank        search by topic/difficulty/type
/api/v1/questions/upload-image   multipart, validated (§20)

/api/v1/reports            GET /reports/exams/{id}/pdf · /excel · /results/{id}/pdf
/api/v1/security           POST /attempts/{id}/security-events
/api/v1/notifications      GET /notifications · POST /notifications/read
```

## 4. Response schema separation

One ORM model, several serialisations — chosen by *who is asking*, enforced by the
`response_model` on each route rather than by manual field deletion:

| Model | Teacher schema | Student schema | Difference |
|---|---|---|---|
| `Question` | `TeacherQuestionResponse` | `StudentQuestionResponse` | student class has no `is_correct` field at all |
| `Exam` | `TeacherExamResponse` | `StudentExamResponse` | student sees no draft fields, no per-student stats |
| `Attempt` | — | `AttemptResponse` | `remaining_seconds` computed server-side |
| `Result` | `TeacherResultResponse` | `StudentResultResponse` | student sees own row only, and only when published |

Because `StudentQuestionResponse` does not *declare* `is_correct`, a future refactor that
forgets to filter cannot leak the answer key: Pydantic drops undeclared fields.

## 5. Versioning

The prefix is `/api/v1`. Breaking changes land under `/api/v2` with `v1` kept alive long
enough for installed apps to update — mobile clients cannot be forced to upgrade in step
with the server.


---

## 6. Attempts, marking and results

### Sitting an exam — `/api/v1`

```
POST   /exams/{id}/start                        student  → AttemptResponse
GET    /attempts/{id}                           owner    → AttemptResponse (restores state)
POST   /attempts/{id}/answers                   owner    → AnswerAck
POST   /attempts/{id}/submit                    owner    → SubmitResponse
```

`start` evaluates every condition in §32 server-side — published, enrolled, approved,
inside the window, attempts remaining — and **resumes** rather than duplicating if an
attempt is already running, so an app restart returns the same clock and the same paper.

`expires_at` is `min(started_at + duration, exam.expires_at)`: starting late does not
extend the exam past its own window. Every response carries `remaining_seconds` computed
from the server clock, and `AnswerAck` carries it too, so the client's countdown is
re-synced on every keystroke and tap. The client's own timer is decoration.

An answer takes one of two shapes and the server enforces which: `selected_option_id` for
the three choice types, `answer_text` for short answer and code. An option id belonging to
a different question is rejected outright rather than stored and silently marked wrong.

Submission is guarded by an `UPDATE ... WHERE status = 'active'` whose row count is
checked, so two submissions racing each other cannot both grade the attempt. A submission
that arrives after the deadline is recorded as `auto_submitted` — accurate about what
happened, and the answers still count.

### Marking — `/api/v1`

```
GET    /exams/{id}/grading                      owner    → [GradingQueueEntry]
GET    /attempts/{id}/grading                   owner    → AttemptGradingResponse
POST   /attempts/{id}/answers/{aid}/evaluate    owner    → EvaluatedAnswerResponse
```

Choice questions are marked automatically at submission, against the snapshot frozen at
publish. Short answers and code are left `pending` — explicitly unmarked rather than
scored zero, so "not yet marked" and "marked zero" stay distinguishable.

Awarding marks rebuilds the result from the answers rather than incrementing it, so
re-marking a correction cannot drift the total. The upper bound is the question's own
marks, checked against the snapshot: a teacher cannot award 20 out of 10. An answer that
was marked automatically cannot be overridden through this route.

### Results — `/api/v1`

```
GET    /results                                 student  → [StudentResultResponse]
GET    /results/{id}                            student  → StudentResultResponse
GET    /exams/{id}/results                      owner    → [TeacherResultResponse]
POST   /exams/{id}/results/publish              owner    → PublishResultsResponse
```

A student's results are **not filtered after loading** — an unpublished result is never
loaded for a student at all. Asking for one directly returns `404`, the same as a result
that does not exist, because confirming it exists but is withheld is itself a disclosure.

`show_result_immediately` releases a result at submission only when nothing on the paper
still needs marking; a partial score shown as final would be wrong.


---

## 7. Security events and analytics

### Security events — `/api/v1`

```
POST   /attempts/{id}/security-events           student  → [SecurityEventResponse]
GET    /attempts/{id}/security-events           owner    → AttemptSecurityReport
```

The device reports **what**; the server decides **how serious** and records **when**.
`severity` and any timestamp in the request body are ignored — a patched client cannot
file its own screenshot attempt as harmless, nor backdate one. Events arrive in batches
(they queue while offline), are capped per attempt, and are refused once the attempt is
closed. A student cannot read their own trail; only the exam's owner can.

Nothing here ends an attempt or flags a student (§38).

### Analytics — `GET /exams/{id}/analytics`

```
?pass_percentage=40      the threshold to compute pass/fail against
```

Returns cohort counts (approved / submitted / in progress / absent), a score summary,
a five-band distribution, and per-question figures.

Two deliberate choices:

- **Score fields are `null`, not `0`, when nobody has submitted.** `0%` would read as
  "everyone failed" rather than "nobody has sat it".
- **The pass mark is a parameter, not a constant.** The platform does not know a
  university's pass mark, so it is supplied per request and echoed back beside the
  figures it produced.

Per question, `correct`/`wrong`/`correct_rate` are populated only for the three choice
types. A short-answer or code question reports `average_marks` and `awaiting_marks`
instead — "correct" is meaningless for prose, so it is absent rather than guessed at.


---

## 8. Reports — `/api/v1/reports`

```
GET /reports/exams/{id}/pdf        owner            → application/pdf
GET /reports/exams/{id}/excel      owner            → .xlsx
GET /reports/results/{id}/pdf      owner or student → application/pdf
```

Built in memory and streamed — nothing touches disk, so there are no temporary files to
clean up or leak between requests. Each carries
`Content-Disposition: attachment; filename="CSE-301-Mid-Term-results.pdf"`, and
`Access-Control-Expose-Headers` so a browser client can actually read that name.

A report is a *rendering* of data the caller can already read as JSON, and the same
ownership rules apply: `/reports/results/{id}/pdf` is open to both roles under the rule
each already has — the exam's owner may print any of its results, a student may print
their own once released. An unreleased result is `404` for its own student, exactly as
the JSON endpoint returns.

The Excel export writes **numbers as numbers**, with the percentage stored as a fraction
under a `0.0%` format — a spreadsheet nobody can sum is not much of an export.

`UNIVERSITY_NAME` is configuration: the platform has no way to know a university's name,
so it is not a hardcoded string.


---

## 9. Question bank — `/api/v1/question-bank`

```
GET    /question-bank        ?type&difficulty&topic&search&page  → paged BankQuestionResponse
POST   /question-bank                                            → BankQuestionResponse
GET    /question-bank/topics                                     → the topics I have used
GET    /question-bank/{id}
PUT    /question-bank/{id}
DELETE /question-bank/{id}                                       → 204

POST   /exams/{id}/questions/from-bank   {question_ids: [...]}   → [ExamQuestionResponse]
```

A question always lived independently of any exam — `exam_questions` is only the link —
so the bank exposes that library directly rather than introducing a new concept. Scope is
per teacher; another teacher's question is `404`, and cannot be borrowed into an exam.

**Editing a reused question is safe, and this is why:** a published exam renders and
grades from the snapshot frozen when it was published, so an edit here cannot disturb a
paper students have already sat. A *draft* exam does follow the edit — including its
`total_marks`, which is recomputed — which is what a teacher would expect. Each response
carries `used_in_exams` and `used_in_published` so the teacher can see what is in
circulation before changing it.

**Removing a question from an exam no longer deletes it.** Before the bank existed, a
question with no exam links was orphaned junk and was cleaned up. Now it is a library
entry, and deletion is an explicit act through `DELETE /question-bank/{id}` — which is
refused (`409 question_in_use`) while any exam still links to it.


---

## 10. Notifications — `/api/v1/notifications`

```
GET  /notifications        ?unread_only&page   → paged NotificationResponse
GET  /notifications/unread-count               → {unread}
POST /notifications/{id}/read                  → NotificationResponse
POST /notifications/read-all                   → {updated}
```

Notifications are **stored**, not merely pushed. A student whose app was closed when
their exam was published must still see it when they open it, so the database row *is*
the notification; any push is a second channel for the same row.

Every list is scoped to the caller inside the query — there is no id to ask for and no
filter to forget. Another person's notification is `404`.

Six events, each raised inside the transaction of the action that caused it, so a
rolled-back action leaves no notification claiming it happened:

| Event | Who hears | Category |
|---|---|---|
| An exam is published | every student enrolled in the course | `exam_published` |
| A student asks to join | the exam's teacher | `join_request_received` |
| A request is approved | the student | `join_request_approved` |
| A request is rejected | the student | `join_request_rejected` |
| An attempt is submitted | the exam's teacher | `exam_submitted` |
| Results are released | each student whose result moved | `result_published` |

`payload` is a pointer for the app to navigate with (`{"exam_id": 11}`), not a copy of
the record. Where a tap leads depends on who is reading: the same exam id opens the
teacher's exam screen or the student's exam details.

### Push delivery — not implemented

`NotificationService._emit` is where a push channel would fan out, and it is deliberately
empty. Firebase Cloud Messaging needs three things this project does not have:

1. a Firebase project and a **service-account key** for the server,
2. **`google-services.json`** in `mobile/android/app/`,
3. a **device-token** table and registration endpoint, so the server knows where to send.

Adding a client that silently drops every message would look finished and deliver
nothing, so it was left out. The in-app channel is complete and does not depend on it.
