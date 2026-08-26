from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import ForeignKey, Integer, LargeBinary, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.types import UTCDateTime, utcnow

if TYPE_CHECKING:
    from app.models.user import User


class UploadedImage(Base):
    """An image for a question or an option, stored as bytes in the database.

    The bytes live here rather than on disk because the disk is not somewhere they can
    survive. The deployment target has no persistent volume: anything written to the
    container's filesystem is lost the moment the instance is replaced, which for a free
    plan is routine rather than exceptional. An exam question whose diagram silently
    disappears between the day it was written and the day it is sat is worse than one
    that could never hold a diagram at all.

    This is a deliberate trade, not an ideal. Object storage is the right home for
    binaries at scale, and §5 of the architecture still says so. Until credentials for
    one exist, the database is the only place in this system that actually keeps things.
    The cost is bounded by the upload cap and by how many images an exam paper has, both
    of which are small; the benefit is that an image is as durable as the question that
    refers to it, and is included in the same backup.

    Deletion is deliberately not cascaded from anywhere. A row here is referenced by URL
    string rather than by foreign key, so nothing can quietly take an image out from
    under a published paper -- see ``UploadService.delete``, which refuses while any
    question or option still points at it.
    """

    __tablename__ = "uploaded_images"

    #: The UUID hex that appears in the URL. Not a serial: an image's address should not
    #: reveal how many have been uploaded, nor let one be guessed from another.
    id: Mapped[str] = mapped_column(String(32), primary_key=True)

    #: Kept so the response can be served with the type Pillow actually decoded, rather
    #: than one inferred from a filename the client chose.
    content_type: Mapped[str] = mapped_column(String(40), nullable=False)
    extension: Mapped[str] = mapped_column(String(8), nullable=False)

    width: Mapped[int] = mapped_column(Integer, nullable=False)
    height: Mapped[int] = mapped_column(Integer, nullable=False)
    byte_size: Mapped[int] = mapped_column(Integer, nullable=False)

    data: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)

    uploaded_by: Mapped[int] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        UTCDateTime, nullable=False, default=utcnow
    )

    uploader: Mapped["User"] = relationship()

    @property
    def url(self) -> str:
        return f"/uploads/{self.id}{self.extension}"

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"<UploadedImage {self.id} {self.content_type} {self.byte_size}B>"
