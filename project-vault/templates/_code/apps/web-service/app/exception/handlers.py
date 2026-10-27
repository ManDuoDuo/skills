from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.exception.errors import DatabaseUnavailable


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(DatabaseUnavailable)
    async def database_unavailable(_request: Request, _exc: DatabaseUnavailable) -> JSONResponse:
        return JSONResponse(
            status_code=503,
            content={"error": {"code": "database_unavailable", "message": "数据库不可用"}},
        )
