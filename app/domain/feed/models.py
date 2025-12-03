from sqlalchemy import Column, Integer, DateTime, ForeignKey
from sqlalchemy.sql import func
from app.core.database import Base

class FeedEntry(Base):
    __tablename__ = "feed_entries"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True) # The user whose feed this is
    post_id = Column(Integer, ForeignKey("posts.id"), nullable=False)
    source_user_id = Column(Integer, ForeignKey("users.id"), nullable=False) # The author of the post
    created_at = Column(DateTime(timezone=True), server_default=func.now(), index=True)
