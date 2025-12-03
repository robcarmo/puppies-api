from fastapi import FastAPI
from app.core.config import settings
from app.api.v1.api import api_router
from app.core.database import Base, engine

# Create tables (for simplicity in this MVP, usually handled by Alembic)
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title=settings.PROJECT_NAME,
    openapi_url=f"{settings.API_V1_STR}/openapi.json"
)

app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/health")
def health_check():
    return {"status": "ok"}
