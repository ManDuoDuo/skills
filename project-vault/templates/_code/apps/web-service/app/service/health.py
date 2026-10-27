from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.constants.version import APP_VERSION
from app.exception.errors import DatabaseUnavailable
from app.schema.health import HealthResponse


async def get_health(session: AsyncSession) -> HealthResponse:
    try:
        await session.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        raise DatabaseUnavailable from exc
    return HealthResponse(status="ok", database="ok", version=APP_VERSION)
