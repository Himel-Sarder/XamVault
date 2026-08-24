"""Bootstrap the database with a first administrator, and optionally demo data.

    python -m app.utils.seed                 # create the admin from FIRST_ADMIN_* env vars
    python -m app.utils.seed --demo          # also create a department, teacher, student,
                                             # course and enrolment for manual testing

Every operation is idempotent: running it twice does not create duplicates.
"""

from __future__ import annotations

import argparse
import sys

from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.core.security import hash_password
from app.models.course import Course, CourseEnrollment
from app.models.department import Department
from app.models.enums import UserRole
from app.models.user import StudentProfile, TeacherProfile, User
from app.repositories.course_repository import CourseRepository
from app.repositories.department_repository import DepartmentRepository
from app.repositories.user_repository import UserRepository

DEMO_PASSWORD = "Passw0rd!123"


def _get_or_create_user(
    db: Session, *, login_id: str, password: str, name: str, role: UserRole, **extra
) -> tuple[User, bool]:
    users = UserRepository(db)
    existing = users.get_by_login_id(login_id)
    if existing:
        return existing, False
    user = users.add(
        User(
            user_id=login_id,
            password_hash=hash_password(password),
            name=name,
            role=role.value,
            **extra,
        )
    )
    return user, True


def seed_admin(db: Session) -> None:
    if not settings.FIRST_ADMIN_PASSWORD:
        sys.exit(
            "FIRST_ADMIN_PASSWORD is not set. Set it in backend/.env (or the environment) "
            "before seeding — this script will not invent a password for an admin account."
        )
    admin, created = _get_or_create_user(
        db,
        login_id=settings.FIRST_ADMIN_USER_ID,
        password=settings.FIRST_ADMIN_PASSWORD,
        name=settings.FIRST_ADMIN_NAME,
        role=UserRole.ADMIN,
    )
    db.commit()
    print(f"admin  {admin.user_id!r} {'created' if created else 'already present'}")


def seed_demo(db: Session) -> None:
    departments = DepartmentRepository(db)
    users = UserRepository(db)
    courses = CourseRepository(db)

    department = departments.get_by_code("CSE")
    if department is None:
        department = departments.add(
            Department(code="CSE", name="Computer Science & Engineering")
        )
        db.flush()

    teacher, teacher_created = _get_or_create_user(
        db,
        login_id="T1001",
        password=DEMO_PASSWORD,
        name="Dr. Demo Teacher",
        role=UserRole.TEACHER,
        email="teacher@example.edu",
        department_id=department.id,
    )
    if teacher_created:
        db.flush()
        users.add_teacher_profile(
            TeacherProfile(
                user_id=teacher.id,
                teacher_id="T1001",
                department_id=department.id,
                designation="Assistant Professor",
            )
        )

    student, student_created = _get_or_create_user(
        db,
        login_id="20261234",
        password=DEMO_PASSWORD,
        name="Demo Student",
        role=UserRole.STUDENT,
        email="student@example.edu",
        department_id=department.id,
    )
    if student_created:
        db.flush()
        users.add_student_profile(
            StudentProfile(
                user_id=student.id,
                student_id="20261234",
                department_id=department.id,
                semester=6,
                session="2025-2026",
            )
        )

    course = courses.get_by_code_and_session("CSE-301", "2025-2026")
    if course is None:
        course = courses.add(
            Course(
                course_code="CSE-301",
                course_name="Database Management System",
                department_id=department.id,
                semester=6,
                session="2025-2026",
                created_by=teacher.id,
            )
        )
        db.flush()

    if courses.get_enrollment(course.id, student.id) is None:
        courses.add_enrollment(CourseEnrollment(course_id=course.id, student_id=student.id))

    db.commit()
    print(f"demo   department {department.code}, teacher {teacher.user_id}, "
          f"student {student.user_id}, course {course.course_code}")
    print(f"       demo account password: {DEMO_PASSWORD}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--demo", action="store_true", help="also insert demo department/users/course"
    )
    args = parser.parse_args()

    with SessionLocal() as db:
        seed_admin(db)
        if args.demo:
            seed_demo(db)


if __name__ == "__main__":
    main()
