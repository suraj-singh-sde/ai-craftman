# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [0.6.0] - 2026-10-03

### Added
- Skills, preloaded into engineering agents through `skills:` frontmatter:
  - `karpathy-guidelines` from [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) (MIT), with a note mapping "ask" to open questions and assumptions in the pipeline.
  - `root-cause-debugging`, used for fix loops after test, review and QA failures.
- A self-check that every skill an agent preloads exists in `skills/`.
- Run report: `.craftman/memory/<run-id>/report.html` with Status, Design (HLD/LLD with mermaid diagrams) and Results tabs. `craftman-state` refreshes it after every step; `craftman-state report [run-id]` rebuilds it on demand. It is read-only and sanitizes agent output.

### Changed
- Architecture is split into HLD and LLD. The architect writes the HLD (`06-hld.md`: components, data stores, integrations, libraries, ADRs), which passes the governance and human approval gates. A fresh architect then writes the LLD (`08a-lld.md`: structure, contracts, error model, data model, limits), checked by a new governance `design` gate (`08b-gov-design.md`). The lite profile writes one combined design.
- code-reviewer: changes outside the work package and speculative code are medium findings.

## [0.5.0] - 2026-10-01

Faster runs. In v2, engineering took 62% of a 2-hour run, with three packages built one after another.

### Added
- `tdd-engineer` (sonnet): test-first development in one context (red run recorded, then green and refactor) for small and medium packages. Large or security-sensitive packages keep test-writer plus code-writer.
- Step timing: `craftman-state` records how long each step took, plus the run's `finished` time and `duration`. The summary names the three slowest steps.
- `fast_test_command` in the context, for fail-fast, parallel test runs with slow tests excluded. pytest-xdist and the `slow` marker are in the Python standard.

### Changed
- Work plans build a skeleton package first, then put the independent slices in one parallel group.
- Questions come before engineering. The architect and work plan raise every open decision; engineering agents record `## Assumptions` instead of stopping.
- Review: only critical and high findings get a fix round, and the re-review uses `scope: verify-fixes`. Medium and low findings from all packages are fixed in one cleanup pass at the end.
- Parallel dispatches: context-memory alongside architecture; security review, QA and docs together.
- Profile is chosen automatically from size (small → lite) instead of asking. Lite also skips the separate security review; the reviewer runs with `security_focus: true` on opus.
- code-writer and code-reviewer default to sonnet. The reviewer uses opus for packages marked `sensitive` and for security-focused reviews.

## [0.4.0] - 2026-10-01

### Added
- `research-agent` (sonnet; WebSearch and WebFetch). Agents tag open questions `[research]` when documentation or the web can answer them; the orchestrator batches them per step to the research agent instead of asking the human.
- It reuses earlier answers (under 90 days old), prefers primary sources, verifies them against the project's versions, and writes cited answers to `research/<step>.md`.
- It treats web content as untrusted, never searches with secrets or private code, and caps searches per question.
- Questions it cannot settle go to the human.

## [0.3.3] - 2026-10-01

### Added
Standards and reviewer rules from the file-service-v2 review:
- Infrastructure errors are translated in repositories and adapters: database busy or locked becomes 503, disk full becomes 507, never a generic 500. New `UnavailableError` and `InsufficientStorageError`. Error messages are defined once on the domain error.
- Writes that span two stores need a reconciler for orphans, not just a log line.
- Resource limits: time and size bounds on every request, per-user quotas where users store data, and overload responses in the API error format.
- Caches: no lock held across I/O; stale-while-revalidate refresh. No per-request threadpool hop for cheap sync work.
- Security: permission checks beyond authentication; JWT issuer and audience required; user-supplied names sanitized; API docs off in production.
- Separate liveness and readiness probes.
- Service-prefixed env vars; no settings or abstractions for a single option; unused code deleted.
- Blob storage: content hash, `HEAD`/`Range`, sharded directories.
- Python: `FileResponse` for downloads, `PyJWKClient` key cache, `env_prefix`, error translation, timeouts, `core/middleware.py`.
- code-reviewer has a production-readiness check and the expanded severity rubric.

## [0.3.2] - 2026-09-30

### Changed
- requirements-planner states outcomes and measurable limits, not mechanisms (e.g. "bounded memory, 413 over limit" instead of "must not spool to disk"), and adds no unrequested scope.
- Standards: services hold business rules only; technical helpers (pagination cursors, encoding, parsing) go in their own module (`core/pagination.py` in Python).
- code-reviewer flags stale skeleton placeholders, helpers inside services, and redundant tests (duplicates, unparametrized variations, library-behavior tests) as medium.
- doc-writer writes only the architecture's ADRs and never promotes routine choices to ADRs.

## [0.3.1] - 2026-09-30

### Fixed
- Cost blow-up from reusing agents: the orchestrator continued one test-writer/code-writer/liaison across all packages and rounds with `SendMessage` (39 continuations; the code-writer re-read ~27M cached tokens). Now there is a fresh agent per package step and per liaison round, and `SendMessage` is limited to one follow-up within a step.
- The budget hook now counts `SendMessage` continuations (the v2 run showed 16 counted vs 56 real dispatches).
- The orchestrator no longer sends human answers to the liaison to "record" them (the hook already does).
- Architect output is capped (concise, ~400 lines, 2 to 5 ADRs, no speculative scope). The v2 run produced 187k output tokens and 13 ADRs.
- Test budget of about 3 to 6 tests per acceptance criterion, with parametrized variations (the v2 run had 367 tests).
- Hand-rolled replacements need an ADR citing a specific FR/NFR, checked at the governance architecture gate. For Python: Alembic required; `UploadFile` plus a counting size limit for uploads.
- code-writer removes skeleton placeholder docstrings during refactor.

## [0.3.0] - 2026-09-30

### Added
- Engineering standards (`templates/standards/`): layered structure, error model, clean code, test and review rubric; stack layouts and libraries for Python, JS/TS, Go, Java/Kotlin. They replace the review checklists.
- Architect outputs a project structure, error model and library choices. enterprise-context writes a project blueprint for new services.

### Changed
- Engineering loop per package: test-writer, code-writer (green + refactor + format/lint/typecheck), then one review of tests and code together. About 3 agent calls per package instead of 5.
- code-optimizer runs only for performance requirements or findings.
- Work plans are capped by size (1/3/5 packages), as vertical slices, not layers.
- QA fills gaps and targets the governance coverage threshold instead of maximising coverage.
- QA and security review run in parallel.

### Fixed
- Worktree branch names use `craftman/<run>-<WP>`. Git cannot create `craftman/<run>/<WP>` while `craftman/<run>` exists.
- Lint and typecheck now run on the branch after every merge, so merge-introduced errors are caught per group.

## [0.2.0] - 2026-09-30

### Added
- Hooks that enforce approvals, protect run files, block secrets in memory, lock test files for implementers, and cap agent dispatches per run.
- `craftman-state` script: structured run state, profiles (`full`/`lite`), `--from`/`--to`/`--skip-deploy`, escalation log.
- Commands: `craftman-init`, `craftman-status`, `craftman-resume`.
- Agents: `security-reviewer`, `legacy-analyst`, `doc-writer`, `operations-engineer`.
- Git workflow: run branch, one commit per package, worktrees for parallel packages, approval-gated PR.
- Optional tracker issues (GitHub/Jira) per work package.
- `.craftman/context/sources.md` for other repos, docs and MCP-connected systems; stack detection with review checklists.
- `userConfig`: `model_tier`, `max_agent_calls`.
- Eval suite, sample app, self-check script, CI.

### Changed
- Agents write their own memory files with a YAML header and return short summaries. The orchestrator passes paths, not content.
- `memory-keeper` now only curates enterprise context and the run summary.
- `human-liaison` and `human-oversight` run on haiku; oversight uses a configurable autonomy level.
- The test-first loop adds a tests review before implementation, and the orchestrator re-runs the tests itself.
- QA adds lint, typecheck, dependency audit, e2e/benchmarks where applicable, and a manual mutation check.
- `delivery-manager` asks when deployment evidence is weak instead of guessing.

## [0.1.0] - 2026-09-30

### Added
- Initial pipeline command and 15 agents.
