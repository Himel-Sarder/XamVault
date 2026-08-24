"""Close and grade attempts whose time ran out while nobody was looking.

    python -m app.utils.sweep_attempts

The app asks the server to submit when its own countdown reaches zero, and the server
auto-submits whenever an expired attempt is read — but neither helps if the student's
device died mid-exam and nothing ever touches the attempt again. This is the backstop
(§42), and is safe to run repeatedly.

Schedule it as a Render Cron Job (or any cron) every few minutes:

    */5 * * * *  python -m app.utils.sweep_attempts
"""

from __future__ import annotations

import argparse
import logging

from app.core.database import SessionLocal
from app.services.attempt_service import AttemptService

logger = logging.getLogger("uniexam.sweep")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--limit",
        type=int,
        default=200,
        help="Maximum attempts to close in one run (default: 200).",
    )
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)-8s %(message)s")
    with SessionLocal() as db:
        closed = AttemptService(db).sweep_expired(limit=args.limit)
    print(f"auto-submitted {closed} expired attempt(s)")


if __name__ == "__main__":
    main()
