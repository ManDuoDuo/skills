from httpx import ASGITransport, AsyncClient

from app.core.db import get_db
from app.exception.errors import DatabaseUnavailable
from app.main import app


async def test_health_api() -> None:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["database"] == "ok"


async def test_health_api_database_unavailable() -> None:
    async def broken_db() -> None:
        raise DatabaseUnavailable

    app.dependency_overrides[get_db] = broken_db
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/health")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json()["error"]["code"] == "database_unavailable"
