# UniExam

Secure university examination platform — **Flutter** client, **FastAPI** backend,
**PostgreSQL** on **Render**, with Android-native exam lockdown.

> **Status: the main workflow runs end to end.** Phases 1, 4, 7–11, 13 and 16 are
> complete; Phase 5 covers multiple choice. A teacher creates and publishes an exam, a
> student is admitted, sits it under a server-owned timer with per-student shuffling,
> submits, is graded automatically, and sees the mark once the teacher releases it.
> Remaining: image / short-answer / code questions (5, 14–15), Android exam lockdown (12),
> analytics (17), PDF and Excel export (18), notifications (19). See
> [docs/architecture.md](docs/architecture.md#6-phase-map).

---

## Architecture

```
Flutter app  ──HTTPS──▶  FastAPI  ──SQLAlchemy──▶  PostgreSQL (Render)
     │                      │
 MethodChannel         router → service → repository
     ▼
Android native (Kotlin) — lockdown, FLAG_SECURE, Lock Task
```

The app never connects to PostgreSQL directly. Every authorization decision, every
timestamp and every mark is computed server-side; the client renders state it is given.

| Document | Contents |
|---|---|
| [docs/architecture.md](docs/architecture.md) | System diagram, layering, request lifecycle, trust boundary, phase map |
| [docs/database.md](docs/database.md) | Full ER diagrams, Phase 1 DDL, integrity rules, migration workflow |
| [docs/api.md](docs/api.md) | Endpoint reference, conventions, per-audience response schemas |
| [docs/security.md](docs/security.md) | Auth design, token rotation, RBAC, upload/sandbox/lockdown plans |

---

## Repository layout

```
uniexam/
├── backend/          FastAPI + SQLAlchemy + Alembic
│   ├── app/          core · models · schemas · routers · services · repositories · middleware
│   ├── alembic/      migrations
│   └── tests/        pytest suite
├── mobile/           Flutter client
│   ├── lib/          config · core · models · repositories · providers · features · widgets
│   └── android/      native Android configuration
├── docs/             architecture · database · api · security
├── docker-compose.yml
└── render.yaml       Render blueprint
```

---

## Running the backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows;  source .venv/bin/activate on macOS/Linux
pip install -r requirements-dev.txt

cp .env.example .env             # then set DATABASE_URL and JWT_SECRET_KEY
alembic upgrade head
python -m app.utils.seed --demo  # first admin + demo department/teacher/student/course
uvicorn app.main:app --reload
```

### Scheduled work

```bash
python -m app.utils.sweep_attempts     # close attempts whose time ran out
```

The app asks the server to submit when its countdown hits zero, and the server closes an
expired attempt whenever one is read — but neither helps if a student's device died
mid-exam. Run this as a Render Cron Job every few minutes as the backstop (§42):

```
*/5 * * * *   python -m app.utils.sweep_attempts
```

- API: <http://127.0.0.1:8000>
- Swagger: <http://127.0.0.1:8000/docs>
- Health: <http://127.0.0.1:8000/health>

Generate a JWT secret with:

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

### Pointing at Render PostgreSQL

Copy the **External Database URL** from your Render database into `DATABASE_URL`. Both
`postgres://` and `postgresql://` forms are accepted and normalised at start-up. Then run
`alembic upgrade head` against it.

### Demo accounts (after `--demo`)

| Role | User ID | Password |
|---|---|---|
| Admin | `admin` | value of `FIRST_ADMIN_PASSWORD` |
| Teacher | `T1001` | `Passw0rd!123` |
| Student | `20261234` | `Passw0rd!123` |

Demo credentials are for local development only.

---

## Running the app

```bash
cd mobile
flutter pub get
```

**Android** (the production target):

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

`10.0.2.2` is the Android emulator's alias for your machine. On a physical device use your
LAN address (`http://192.168.x.x:8000/api/v1`); for a deployed backend use the Render
HTTPS URL. Debug builds permit cleartext HTTP to `10.0.2.2`/`localhost` only — release
builds are HTTPS-only.

**Chrome** (fast iteration and CI):

```bash
flutter run -d chrome --web-port=5000   --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

Pin `--web-port` so the origin matches `CORS_ORIGINS` in `backend/.env`
(`http://localhost:5000` is preconfigured). Flutter Web is a **development convenience
only**: `flutter_secure_storage` falls back to browser storage there, and none of the
Phase 12 Android exam-lockdown protections exist in a browser. Exams run on Android.

---

## The workflow that works today

```
TEACHER                                   STUDENT
─────────────────────────────────         ──────────────────────────────
Sign in                                   Sign in
  ↓                                         ↓
Course → Create Exam                      Available Exams
  title · start · duration                  ↓
  settings (shuffle, secure, …)           Exam Details → Request to join
  ↓                                         ↓
Add Text MCQ  × N                         Awaiting approval
  exactly one correct answer                ↑
  ↓                                         │
Publish  ──────────────────────────────▶    │
  validation lists every problem            │
  questions frozen into snapshots           │
  ↓                                         │
Join Requests                               │
  approve / reject, or all at once ─────────┘
  ↓                                       Approved → Start exam
  │                                         ↓
  │                                       Timer (server-owned) · palette
  │                                       personal question + option order
  │                                         ↓
  │                                       Submit  (or auto-submit at 0:00)
  │                                         ↓
  │                                       MCQ graded from the snapshot
  ↓                                         ↓
Results  ·  average / high / low          "Awaiting release"
  Release marks ────────────────────────▶  My Results  12/12  100%
```

Still to come: image, short-answer and code questions (Phases 5, 14–15), Android exam
lockdown (12), analytics (17), PDF and Excel export (18), notifications (19).

---

## Tests

```bash
# Backend — 237 tests, against a schema built by Alembic
cd backend && .venv/Scripts/python -m pytest

# ...and the same suite against real PostgreSQL (empties every table it touches)
TEST_DATABASE_URL="postgresql://..." .venv/Scripts/python -m pytest

# Flutter — 138 unit/widget tests, network faked
cd mobile && flutter analyze && flutter test
```

**End-to-end** (real app → real API → real PostgreSQL). Needs the backend running and
seeded, plus a `chromedriver` matching your installed Chrome:

```bash
chromedriver --port=4444 &
cd mobile
flutter drive   --driver=test_driver/integration_test.dart   --target=integration_test/app_test.dart   -d web-server --browser-name=chrome --web-port=5000   --dart-define=API_BASE_URL=http://localhost:8000/api/v1
```

On a device or emulator the same suite runs without chromedriver:

```bash
flutter test integration_test -d <device-id>   --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

The backend suite runs against a database built by **Alembic**, so a migration that drifts
from the models fails the tests rather than the deployment. The Flutter suite fakes the
network to keep UI logic tests fast; the integration suite fakes nothing.

---

## Deploying to Render

Push the repository, then **New → Blueprint** and point Render at `render.yaml`. It
creates the PostgreSQL instance and the Docker web service, wires `DATABASE_URL`, generates
`JWT_SECRET_KEY`, and health-checks `/health`. Set `CORS_ORIGINS` and
`FIRST_ADMIN_PASSWORD` in the dashboard. Migrations run automatically on container start.
