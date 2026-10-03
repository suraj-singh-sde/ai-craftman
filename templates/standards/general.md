# Engineering standards (all stacks)

Architects design to these, code-writers implement to them, reviewers block on them. Stack files add concrete layouts and libraries.

## Structure
- Layered by responsibility, grouped by feature/resource:
  - **api/transport**: parse and validate input, call a service, map the result. No business logic, no data access.
  - **service**: business rules and orchestration. No HTTP or framework types in or out.
  - **repository / adapter**: persistence and external systems behind an interface.
  - **domain**: entities, value objects and domain errors.
  - **core**: config, logging, error mapping, dependency wiring.
- Dependencies point inward only: api → service → repository/adapter. Domain depends on nothing.
- Wire dependencies explicitly (constructor injection or the framework's DI). No global mutable state.
- One module has one job. Split a file past ~300 lines or with unrelated concerns. Middleware lives in its own module, not inside logging or config.
- Services hold business rules only. Technical helpers (pagination cursors, encoding, parsing, formatting, ID generation) live in their own module (e.g. `core/pagination.py`) and are called by the service.

## Use the platform
Use the framework's built-ins and established libraries for:
- request parsing and file uploads
- validation
- config
- ORM, migrations and query building
- auth, retries, HTTP clients

Hand-rolling any of these is a **high** review finding unless an ADR names a specific requirement (FR/NFR id) that the built-in cannot meet, and says why configuring the built-in is not enough. "More control", "fewer dependencies" or "simpler" are not valid reasons. Governance checks these ADRs at the architecture gate.

## Error handling
- Define a domain error hierarchy in one module, for example:
  - `AppError` (code, message)
  - `NotFoundError`
  - `ConflictError`
  - `ValidationError`
  - `PermissionDeniedError`
  - `PayloadTooLargeError`
  - `ExternalServiceError`
  - `UnavailableError` (retryable: database busy or locked, dependency down)
  - `InsufficientStorageError` (disk full, quota exceeded)
- Each domain error carries its default message. Never repeat the same message literal in several modules.
- Repositories and adapters translate infrastructure errors into domain errors: database busy or locked becomes `UnavailableError` (503 + `Retry-After`), disk full becomes `InsufficientStorageError` (507), and an unreachable dependency becomes `ExternalServiceError` (502/503). A retryable condition must never surface as a generic 500.
- Services raise domain errors. Only one place, the global exception handler at the boundary, maps them to transport status codes and the error response format.
- One error response format for the whole API (RFC 9457 `application/problem+json`, or one documented envelope). It includes a stable machine `code` and the request id, and never stack traces or internals.
- Catch only what you can handle. A broad catch is allowed only at boundaries (global handler, background job loop, cleanup), and it must log with context and re-raise or map. Never swallow an error silently, and never catch base/system exceptions (e.g. `BaseException`, `Throwable`).
- Keep the cause when wrapping (`raise X from e`, `%w`, `new X(msg, cause)`).
- Release resources with language constructs (context managers, `defer`, try-with-resources, `finally`).
- Compensate partial failures, e.g. delete the blob if the DB write fails, and log orphans with ids.
- Writes that span two stores (blob + row, DB + queue) also need a reconciler: a startup or periodic job that removes or repairs what a crash or failed compensation left behind. Logging an orphan is not cleanup.
- Streams handed to the framework (downloads, generators) must release their file or connection when the client disconnects. Prefer the framework's file response, which handles this.
- External calls get timeouts. Retries only for idempotent operations, with backoff.

## Resource limits and abuse
- Every request has an upper bound on time and size: body size limit, body read timeout or idle timeout, and an overall request timeout (in the server, the proxy, or both; the architecture names which).
- When a user can store unbounded data, enforce a per-user quota (bytes and/or object count), or record an ADR that names who enforces it upstream.
- Overload responses (concurrency limit, rate limit) use the API's error format, not the server's plain-text default.
- Rate limits on public or expensive endpoints, in the app or the gateway.

## Caches and concurrency
- Never hold a lock across network or disk I/O on the request path. Refresh shared caches with a single in-flight refresh and keep serving the previous value until it completes (stale-while-revalidate).
- Do not move cheap synchronous work into a thread per request. Use the threadpool only for real blocking I/O.

## Security
- Authentication alone is not authorization. Every operation checks a permission (scope or role, e.g. `files:write`) as well as ownership.
- JWT verification requires `exp`, an algorithm allowlist, **issuer and audience**. Missing issuer or audience is a startup error, not a warning.
- Sanitize user-supplied names before storing them: strip control characters and NUL, and cap the length.
- Interactive API docs (`/docs`, `/openapi.json`) are off in production or behind auth, controlled by a setting.

## Logging and observability
- Structured logs (key=value or JSON) with request id, operation and outcome. Never secrets or PII.
- Log an error once, where it is handled, not at every layer.
- Separate liveness and readiness endpoints (`/livez`, `/readyz`). Liveness checks only that the process responds and never touches dependencies, otherwise a slow database makes the orchestrator restart healthy instances. Readiness checks dependencies cheaply (no writes on every probe).
- Metrics hooks where the stack has a standard.

## Config
- Config comes from typed settings loaded from the environment, validated at startup. No magic numbers in code; named constants or settings.
- Environment variables carry a service prefix (`FILE_SERVICE_PORT`, not `PORT` or `HOST`) so they cannot collide with platform or shell variables.
- No setting, validator or abstraction for a choice that has only one option today. Add it when the second option arrives.

## API design (HTTP)
- Resource-oriented paths, plural nouns, versioned (`/v1`).
- Correct status codes:
  - 201 with `Location` on create
  - 204 on delete
  - 404 when missing or not owned
  - 409 on conflict
  - 422 or 400 on validation, used consistently
- Typed path/query params (e.g. UUID type, not regex).
- Cursor pagination for lists.
- OpenAPI generated from code.

## Blob and file storage
- Store a content hash (sha256) with each object: integrity checks, `ETag`, and optional deduplication.
- Downloads support `HEAD` and `Range` when files can be large. The framework's file response usually does both.
- Shard storage directories (e.g. `ab/cd/<id>`). A flat directory degrades past about a million entries.

## Clean code
- Functions do one thing, ideally ≤ 30 lines. Early returns over nesting.
- Descriptive names. No abbreviations, and no shadowing of built-ins.
- Full type annotations, and strict type checking where the stack supports it.
- Comments explain *why*, not *what*. No commented-out code.
- No clever one-liners that need a comment to decode.
- No dead weight: unused fields, parameters, constants or wrapper functions are deleted, not kept "for later".
- The formatter and linter are clean before every commit.

## Tests
- `tests/unit` mirrors the source tree; `tests/integration` exercises the API through the framework's test client.
- One behavior per test, Arrange-Act-Assert, descriptive names (`test_upload_rejects_file_over_limit`).
- Test through public contracts. Fakes/in-memory adapters for unit tests, the real adapter in integration.
- Coverage target comes from governance (default 80%). Do not chase 100% with trivial tests.
- Tests are independent so they can run in parallel. Slow tests (load, memory, real servers) are marked and excluded from the fast loop, never from QA or release.
- Every test has a time limit from the test runner (about 60s; less for unit tests), so a hang fails in seconds instead of blocking the run. Wait for a condition with a bounded poll, never an unbounded loop or a long fixed sleep.
- A flaky test is a defect. Find the cause; don't rerun it until it passes.
- Tests that start containers, servers or background processes stop them in teardown, also when the test fails or times out (fixture finalizers, `try/finally`). A test run leaves nothing running.
- Never assert placeholder behavior (a stub that returns 501 or raises `NotImplemented`). The next package replaces the stub, so the test breaks by design. Test that routes are registered, not what unfinished ones return.

## Review rubric (severity)
- **critical**: security hole, data loss, crash on a normal path.
- **high**:
  - layer violation (logic in routes, HTTP types in services, data access outside repositories)
  - hand-rolled replacement for a built-in without an ADR
  - swallowed error or a broad catch outside a boundary
  - a missing error path
  - lint or typecheck failure
  - an untested acceptance criterion
  - a retryable infrastructure error (database busy, disk full, dependency down) surfacing as a generic 500
  - a two-store write with no reconciler for orphans
  - unbounded resource use by one client (no body timeout, no quota where users store data)
  - a lock held across network or disk I/O on the request path
  - JWT verification without required issuer and audience, or no permission check beyond authentication
  - a liveness probe that checks dependencies
- **medium**:
  - function over ~50 lines, module with mixed concerns, unclear naming, duplicated logic or message literals, magic numbers
  - speculative code: settings, validators or abstractions for a single option; unused fields, parameters or wrappers
  - unprefixed environment variables
  - overload or framework-default responses outside the API error format
  - user-supplied names stored without sanitizing
  - stream or file handles not released on client disconnect
- **low**: style nits the formatter doesn't catch.
