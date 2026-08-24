# UniExam — Security Architecture

## 1. Authentication

**Password storage.** Argon2id via `pwdlib`, with a bcrypt verifier kept in the hash
context so existing bcrypt hashes (if any are ever imported) still verify and are
transparently re-hashed on next login. Plaintext passwords never touch the database, logs,
or exception messages.

**Tokens.** Two JWTs, both signed HS256 with `JWT_SECRET_KEY`:

| | Access | Refresh |
|---|---|---|
| Lifetime | 30 min (`ACCESS_TOKEN_EXPIRE_MINUTES`) | 7 days (`REFRESH_TOKEN_EXPIRE_DAYS`) |
| Claims | `sub`, `role`, `type=access`, `exp`, `iat`, `jti` | `sub`, `type=refresh`, `exp`, `iat`, `jti` |
| Server state | none | row in `refresh_tokens` |
| Sent on | every request | only `/auth/refresh`, `/auth/logout` |

`type` is checked on every decode. An access token cannot be replayed at `/auth/refresh`
and a refresh token is rejected as a bearer credential — without that check the long-lived
token becomes a long-lived API key.

**Rotation.** `/auth/refresh` revokes the presented `jti` and issues a new pair inside one
transaction. Presenting an already-revoked `jti` is treated as theft: **every** refresh
token for that user is revoked and the client is forced back to login.

**Role in the token.** `role` is a convenience claim for fast rejection; every
authorization decision re-reads the user row, so a role change or deactivation takes effect
on the next request rather than at token expiry.

## 2. Authorization

Two distinct layers, both required:

```
Role check          — "is this user a teacher?"        FastAPI dependency
Object-level check  — "is this teacher's id on this    service layer
                       course/exam row?"
```

Role alone is never sufficient. Teacher A holding a valid teacher token must still be
refused teacher B's course, which only an ownership comparison on the row can decide.
Dependencies used: `get_current_user`, `require_roles(...)`, plus per-service
`assert_can_view` / `assert_owns` helpers.

## 3. Server-authoritative state

The client is a renderer. These values are computed by FastAPI and any client-sent
equivalent is ignored — the fields do not exist on the request schemas:

```
identity · role · enrolment · approval status · exam availability window
started_at · expires_at · remaining time · answer correctness · marks
result visibility · submission time · attempt status
```

Concretely, the exam-start decision evaluates all of §32 in `AttemptService.start`, and
`remaining_seconds` is `expires_at - now()` computed on the server on every response —
including every answer save, so the client's countdown is re-synced constantly and is
purely cosmetic. A student who changes the device clock, patches the APK, or replays a
request changes nothing about their remaining time.

`expires_at` is `min(started_at + duration, exam.expires_at)`: starting late does not
extend the exam past its own window. Grading scores against the snapshot frozen at
publish, so neither a later question edit nor anything the client sends can move a mark.

## 4. Data exposure

`is_correct` is absent from student response classes rather than stripped from them, so a
leak requires adding a field, not forgetting to remove one. The same principle covers
`password_hash` (never on any response schema) and other users' rows (queries are scoped by
the requesting user's id, not filtered client-side).

## 5. Transport & HTTP hardening

- **CORS** — explicit origin allow-list from `CORS_ORIGINS`; never `*` together with
  credentials.
- **Security headers** middleware: `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`,
  `Content-Security-Policy: default-src 'none'` (the API returns JSON, not pages),
  `Strict-Transport-Security` when running behind TLS.
- **Rate limiting** — SlowAPI, tightest on `/auth/login` and `/auth/refresh`.
- **Request size** — upload endpoints cap body size (`MAX_UPLOAD_SIZE_MB`) before reading
  the stream, so a large upload cannot exhaust memory.
- **Request id** — every response carries `X-Request-ID`, echoed into logs, so a report
  from a device can be traced to a server log line.

## 6. Injection & input

All queries go through SQLAlchemy expression constructs with bound parameters; no query is
built by string concatenation. Every request body is a Pydantic model with explicit types,
lengths and ranges. Responses are JSON with no HTML rendering, so XSS is a client-side
concern — Flutter renders text into `Text` widgets, never into a WebView.

## 7. File upload validation (phase 5)

Accepted only when *all* hold: extension allow-list, MIME sniffed from content (not the
`Content-Type` header), decoded successfully as an image by Pillow, dimensions within
bounds, size under the cap. The stored filename is a server-generated UUID — the
client-supplied name is never used as a path component, which is what makes path traversal
impossible rather than merely unlikely.

## 8. Code execution (phase 15)

Student code is **never** executed in the API process. `subprocess.run(student_code)` in a
FastAPI worker gives an attacker the database credentials in the same environment. Design:

```
FastAPI → code_submissions row (status=queued) → worker → container sandbox → result row
```

Sandbox: no network, read-only root plus a small tmpfs, non-root user, CPU/wall/memory
limits, process count limit, container destroyed per run. Until that service exists, code
questions are graded manually — a documented manual path is safer than an unsafe automatic
one.

## 9. Android exam lockdown (phase 12) — implemented

Kotlin over two `MethodChannel`s: one Flutter calls to enter and leave lockdown, one
Android pushes observations up.

| Control | What it actually does |
|---|---|
| `FLAG_SECURE` | Blocks the system screenshot path, blanks the window in recents, and defeats most screen recorders. **The only control an unmanaged device genuinely enforces.** |
| Immersive fullscreen | Hides the status and navigation bars. Cosmetic; a swipe brings them back. |
| `startLockTask()` | Pins the app. Only a real lock when the app is a Device Owner or allow-listed by one; otherwise it is the *pinning* variant the student can dismiss. |
| Back-press interception | An `OnBackPressedCallback` at the activity, plus `PopScope` in the widget tree. |
| `resizeableActivity="false"` | Refuses split-screen. |
| Lifecycle, network and clock watchers | Report `APP_BACKGROUND`, `APP_FOREGROUND`, `NETWORK_DISCONNECT`, `NETWORK_RECONNECT`, `DEVICE_TIME_CHANGE`. |

**The app never claims a protection it did not get.** `enterExamLockdown` returns what
each control actually achieved, including whether the lock is real or merely pinning, and
the exam screen states it plainly to the student: *"Screenshots are blocked. Leaving the
app is recorded"* — not *"you cannot cheat"*. When the platform has no lockdown at all
(Chrome, iOS), the exam still runs and a `LOCKDOWN_UNAVAILABLE` event is recorded, so a
teacher reading the trail can see the exam ran without device protection.

**Stated limitation.** A personal, unmanaged Android phone cannot be made cheat-proof — a
second device, a rooted OS, or a vendor screen-recorder defeats any in-app control. Full
lockdown requires a university-managed device with Device Owner provisioning and Lock Task
allow-listing. On personal devices the app applies the strongest supported restrictions
and *records* what happened; those records are evidence for a human invigilator.

### Security events (§39)

The device reports **what**; the server decides **how serious** and records **when**.
Severity is never taken from the request — a patched client cannot file its own
screenshot attempt as harmless — and the timestamp is the server's, so a device cannot
backdate an event. Events arrive in batches because they queue while offline, are capped
per attempt so a misbehaving client cannot flood the table, and are refused once the
attempt is closed.

Crucially, **nothing here ends an attempt or flags a student**. A backgrounded app may be
an incoming call; a dropped network may be a bad signal. The platform records and
surfaces; a human decides.

## 9a. Flutter Web is not a supported exam client

The project builds for Chrome to speed up development and to run the end-to-end suite in
CI. It is not an exam-taking platform: `flutter_secure_storage` degrades to browser
storage (no Keystore), and every control in §9 — `FLAG_SECURE`, Lock Task, lifecycle
violation reporting — is an Android API with no browser equivalent. Exams are taken on the
Android client.

## 10. Auditing

`audit_logs` records actor, action, entity, metadata and IP for every state-changing
teacher and student operation (§62). Audit writes share the transaction of the action they
describe, so a rolled-back action leaves no misleading log entry.

## 11. Secrets

`JWT_SECRET_KEY` and `DATABASE_URL` come from the environment only. The app **refuses to
start** in production if `JWT_SECRET_KEY` is missing or left at the development default —
a deployment with a known signing key is worse than one that fails loudly. `.env` is
git-ignored; `.env.example` carries names and shapes, never values.

## 12. Phase 1 security test coverage

`backend/tests/test_security.py` asserts, as executable tests:

- a refresh token is rejected as a bearer token, and vice versa
- an expired / tampered / wrong-signature token is rejected
- a revoked refresh token fails, and reuse revokes the whole family
- a deactivated user's still-valid token stops working immediately
- a student cannot reach admin endpoints; a teacher cannot read another teacher's course
- `password_hash` appears in no response body
- unknown user id and wrong password are indistinguishable in status and message
