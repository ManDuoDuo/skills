from unittest.mock import AsyncMock

import pytest
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.exception.errors import DatabaseUnavailable
from app.service.health import get_health


async def test_get_health() -> None:
    session = AsyncMock(spec=AsyncSession)

    result = await get_health(session)

    assert result.status == "ok"
    assert result.database == "ok"
    session.execute.assert_awaited_once()


async def test_get_health_wraps_database_errors() -> None:
    session = AsyncMock(spec=AsyncSession)
    session.execute.side_effect = SQLAlchemyError("boom")

    with pytest.raises(DatabaseUnavailable):
        await get_health(session)
