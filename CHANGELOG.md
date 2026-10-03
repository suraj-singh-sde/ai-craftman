# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [0.7.0] - 2026-10-03

From a review of the plugin and of the 5h25m notification-service run (64 agent dispatches, 5 packages).

### Added
- Gates are enforced by the state machine, not only prompted. `craftman-state done` refuses `gov-*`, `security-review` and `qa` until their result file shows the passing verdict, and `approve-architecture` / `approve-deploy` until the human's grant is recorded. `skip` refuses a gate. A human waiver (`[APPROVAL:waiver]`) is the only way past.
- Engineering agents cannot be dispatched while the architecture gates are pending.
- `craftman-state profile lite`: one command switches a running run to lite. Before, the profile in `state.md` stayed `full` after seven manual skips, so a resumed run read the wrong profile.
- Design diagrams. The LLD now carries mermaid diagrams as well as the HLD (modules by layer, data model, main operations); before, it had none. The report's Design tab opens with every HLD and LLD diagram drawn, and the run opens the report in the browser when the HLD is written.
- Diagrams must render. `craftman-state done architecture|design` refuses a design without diagrams or with ones that will not parse. In the notification-service run both HLD diagrams failed to parse (an unquoted label with parentheses, a `;` in a sequence message), so the approved design showed two error images. The lint agrees with mermaid 11 on all 17 diagrams from four real runs. A diagram that still fails is shown as its source with the reason.
- Spin-down. Agents stop every container, server and background process they start. `craftman-state services` lists what is up now and was not when the run started, and the orchestrator stops it after each engineering group and at the end. After the notification-service run, 12 test containers and a hung pytest were still running hours later.
- `package-lead` agent, opt-in with `--lead` (experimental, not yet proven on a full run): one lead per work package dispatches the build and review agents itself and reports once. In the last run the orchestrator made 213 calls on the session's model and read 44.5M cached tokens, most of them for engineering steps.
- README logo image (`assets/logo.png`).
- `handoff-check` skill, preloaded by tdd-engineer, test-writer and code-writer: prove the checks are green, read the diff once as the reviewer, and check that each test can fail for the right reason. Its items are the blocking review findings of four real runs (in the last one, all five first reviews asked for changes). A red package is no longer sent to review; the reviewer also stops at a red suite.
- Desktop notification (macOS, Linux) when a question or an escalation waits for the human. In the run, the pipeline waited 35 minutes on a crashed Docker daemon before anyone noticed. `CRAFTMAN_NOTIFY=off` disables it. When only the human can unblock a run, the orchestrator now escalates and asks, instead of printing a message and waiting.
- `tracker:` in `governance.md` (`none`, `github`, `jira`), so the tracker question is a project setting, not a question in every run.
- README: a pipeline diagram and a diagram of how the orchestrator, agents, hooks and memory fit together.
- Standards: every test has a time limit; a flaky test is a defect, not something to rerun; tests never assert placeholder behavior (the skeleton's "returns 501 until implemented" test broke in three of five packages).

### Changed
- `tdd-engineer` builds every package by default. The two-agent build with locked tests is kept for packages that implement auth, crypto, payments or data deletion, and `sensitive` is defined that narrowly. In the run, all five packages were marked sensitive: 17 test-writer and 11 code-writer dispatches, and a code-writer blocked by a wrong test it was not allowed to fix.
- No work package for end-to-end, load or "hardening" tests: QA writes those once, after the merge. In the run such a package took 77 minutes on slow tests, depended on every other package, and QA then covered the same flows.
- The git question (not a repository, uncommitted changes) is asked with the first clarification round instead of interrupting again before engineering. Later liaison rounds are read from the liaison's file instead of dispatching it again.
- In a parallel group, each agent caps its test workers. Three suites at `-n auto` crashed the Docker daemon and stalled the run for 45 minutes.
- architect, requirements-planner and workflow-coordinator have `Edit` and revise their document in place. The LLD cost 94k output tokens because each revision rewrote it.
- Every agent pins its reasoning effort (`high`, `medium` or `low` by role), so agents no longer inherit a higher session default.
- Agent descriptions are half as long. They load into every session of every user who has the plugin enabled.
- A push approval no longer covers forced pushes or remote branch deletes; those need their own `[APPROVAL:force-push]`.
- The report reloads itself only when it was rebuilt, and keeps your tab, scroll position and open documents, so it no longer closes the design you are reading.
- The run summary holds only facts from the run files (no estimates or sign-off checklists).

### Fixed
- Agent budget lost counts when agents were dispatched in parallel: 40 concurrent dispatches were counted as 5. `state.md` now has one writer at a time (`craftman-state`, the budget hook and the answer recorder share a lock).
- `.craftman/active-run` could be committed by `git add -A` (it was, in one test project), which switches the guards on for everyone who pulls the branch. `craftman-state init` now keeps it git-ignored.
- deploy-guard: a command that started with `craftman-state` could append to `approvals.md` after a `;` or a newline. Only a lone `craftman-state` call is exempt now. `rm -rf .craftman` is blocked during a run.
- deploy-guard, found in a security review of this release before it reached `main`: the `craftman-state` exemption interpreted quotes itself, so mixed or escaped quotes could hide a chained write to `approvals.md` (quotes are no longer interpreted); `rm -rf .craftman/worktrees/../memory`, `mv .craftman`, `find -delete` and `git clean -x` could remove the run files that keep the guards on; `git push -fu`, a quoted `+ref` or `:ref`, and `--prune` passed as a plain push. A second review pass found more: a redirect such as `>&2026-run/approvals.md` (a file name that starts with digits) was taken for `2>&1` and ignored; a glob (`approval?.md`) avoided the file-name check; a command split with a backslash-newline, or written with a tab, was not recognised; and a forced push shared the `destroy` approval with infrastructure commands. A third pass: a comment ending in a backslash made the guard join the next line into a `craftman-state` call it then exempted, so the exemption is now decided on the command as typed (one line, an allowlist of characters); a command touching several categories was checked for one grant only, and now needs every one; git's abbreviated options (`--del`, `--mir`) and a `+ref` starting with a digit passed as a plain push. A fourth pass: quoting or escaping part of a word (`git 'push'`, `git pu\sh`, `approv''als.md`) avoided the patterns, so quotes and backslashes are dropped before matching; `craftman-state resume` could switch to a finished run and reuse its approvals, so a finished run can no longer be resumed; a forced push now needs `force-push` on top of `git-push` instead of replacing it. A fifth pass: a literal `\n` inside an argument was turned into a line break before matching, which hid the rest of the command (`rm -rf "x\n" .craftman`); `git stash push` was blocked as a push.
- `state.md` could be shaped by text the model types: a step given as a pattern (`x|.*gov-release`) marked a gate done without its check, a line break in the requirement or a note added lines (a second `max_agent_calls`), and a run id could be a path outside the memory folder. Steps are exact names now, notes and requirements stay on one line, and run ids are plain names.
- Gate checks: `craftman-state profile lite` could skip seven gates on any run (now only for `size: small`, before design, and not against a `--profile` the human chose); one waiver unlocked every gate (a waiver now names its gate: `[APPROVAL:waiver-gov-release]`); an old PASS outweighed a newer BLOCK (the newest result decides).
- deploy-guard blocked harmless reads of `state.md` that contained `2>&1`.
- file-guard refused design documents with schema fields such as `password: SecretStr` or `api_key: FILE_SERVICE_API_KEY` as secrets. The keyword rule now needs a value that mixes letters and digits.

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
