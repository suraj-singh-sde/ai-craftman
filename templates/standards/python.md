# Python standards (FastAPI / services)

## Layout (src layout)
```
src/<package>/
  main.py                    # create_app(): wiring only
  core/config.py             # pydantic-settings Settings
  core/errors.py             # AppError hierarchy + exception handlers (the only HTTP mapping)
  core/logging.py            # structured logging setup
  core/middleware.py         # request id, access log, timeouts, overload limit
  core/pagination.py         # cursor encode/decode and other technical helpers
  api/deps.py                # Depends() providers: settings, session, services
  api/v1/<resource>.py       # APIRouter per resource, thin handlers
  schemas/<resource>.py      # pydantic request/response models
  services/<resource>.py     # business logic, raises domain errors
  repositories/<resource>.py # SQLAlchemy queries only
  models/<resource>.py       # SQLAlchemy ORM models
  adapters/<thing>.py        # storage, external clients, behind a Protocol
migrations/                  # Alembic
tests/unit/..., tests/integration/..., tests/conftest.py
pyproject.toml               # ruff (lint+format), mypy --strict, pytest
```

## Libraries (prefer over hand-rolled)
- FastAPI `UploadFile` / `File()` for uploads and `StreamingResponse`/`FileResponse` for downloads; typed path params (`file_id: UUID`)
- pydantic v2 and pydantic-settings
- SQLAlchemy 2.0 (typed `Mapped[]`) + Alembic, even for SQLite. Hand-rolled migration runners (`PRAGMA user_version` loops) are not acceptable.
- Upload size limits: `UploadFile` spools to disk (bounded memory). Enforce the limit with a `Content-Length` check plus a counting stream wrapper or a server/proxy body limit. A low-level multipart parser is justified only if an NFR explicitly forbids temporary disk usage.
- httpx with timeouts, and tenacity for retries
- Downloads of local files: Starlette `FileResponse` (handles `Range`, `HEAD`, `ETag`, and closes the file on disconnect) instead of a hand-written chunk generator.
- JWKS: PyJWT `PyJWKClient` with its own key cache (`cache_keys=True`, `lifespan=`) instead of a custom cache and lock.
- `logging` with a JSON formatter, or structlog

## Rules
- Handlers: `async def` with `Depends()`-injected services; return schemas. No `request.app.state` reach-ins.
- Blocking IO (sync DB drivers, file IO) goes through `run_in_threadpool`/`anyio.to_thread`, or you use async drivers (aiosqlite, asyncpg, aiofiles).
- No `except BaseException`. `except Exception` only in the global handler or cleanup paths, and always logs.
- `raise DomainError(...) from e` when translating library errors.
- No mutable default arguments, no bare `except:`, no `assert` for runtime checks.
- `ruff check`, `ruff format --check`, `mypy --strict` clean.
- Tests run in parallel with `pytest-xdist` (`-n auto`), so tests share no global state or fixed ports/paths (use `tmp_path`). Long tests (memory, load, real servers) carry `@pytest.mark.slow`; the fast loop runs `-m "not slow"`, QA and release run everything.
- Settings use `SettingsConfigDict(env_prefix="<SERVICE>_")`.
- Translate `sqlalchemy.exc.OperationalError` / `sqlite3.OperationalError` (busy, locked) to `UnavailableError`, and `OSError` with `errno.ENOSPC`/`EDQUOT` to `InsufficientStorageError`, in the repository or adapter.
- Timeouts: uvicorn `timeout_keep_alive`, plus `anyio.fail_after` around body reads (or a proxy timeout named in the architecture). uvicorn's `limit_concurrency` answers with plain text, so put the limit in middleware that returns the error format, or in the proxy.
- Auth dependencies are `async def` unless they really block (a JWKS fetch). A static-key check doesn't need the threadpool.
- `FastAPI(docs_url=..., openapi_url=...)` come from settings and are `None` in production.

## Review checklist
- `eval`/`exec`/`pickle` on untrusted data; `subprocess` with `shell=True`
- SQL built with f-strings (use the ORM or bound parameters)
- Missing `await`; blocking calls inside `async def`
- Files and sessions closed via context managers
- `threading.Lock` held around a network call
- `except OSError` / `sqlite3.Error` left untranslated on request paths
