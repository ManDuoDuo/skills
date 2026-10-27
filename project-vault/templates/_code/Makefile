APP_DIR := apps/web-service
ADMIN_DIR := web/admin

.PHONY: install server admin test test-unit test-integration test-e2e lint build db-migrate db-upgrade archive-progress

install:
	uv sync --all-packages
	pnpm --dir $(ADMIN_DIR) install

server:
	cd $(APP_DIR) && uv run uvicorn app.main:app --reload --port 8000

admin:
	pnpm --dir $(ADMIN_DIR) dev

test:
	cd $(APP_DIR) && uv run pytest

test-unit:
	cd $(APP_DIR) && uv run pytest test/unit --no-cov

test-integration:
	cd $(APP_DIR) && uv run pytest test/integration --no-cov

test-e2e:
	cd $(APP_DIR) && uv run pytest test/e2e --no-cov

lint:
	uv run ruff check .
	uv run ruff format --check .
	pnpm --dir $(ADMIN_DIR) lint

build:
	pnpm --dir $(ADMIN_DIR) build

db-migrate:
	cd $(APP_DIR) && uv run alembic revision --autogenerate -m "$(msg)"

db-upgrade:
	cd $(APP_DIR) && uv run alembic upgrade head

archive-progress:
	bash scripts/archive-progress.sh
