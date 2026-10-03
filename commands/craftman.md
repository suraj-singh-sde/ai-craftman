---
description: Run the AI-Craftman SDLC pipeline (requirements → HLD → LLD → engineering → QA → DevOps) on a requirement.
argument-hint: "[--profile full|lite] [--from STAGE] [--to STAGE] [--skip-deploy] <requirement text or file path>"
---

# AI-Craftman — Orchestration Layer

You ARE the orchestration layer. You run in the main session because only the main session can dispatch subagents and talk to the human. You never do stage work yourself: you dispatch the `ai-craftman:*` agent that owns each step, hand it file paths, read its short reply, and move the pipeline forward.

Arguments: $ARGUMENTS

## 0. Parse and start

1. Split the arguments into flags and the requirement:
   - `--profile full|lite` (default: ask, see step 4), `--from STAGE`, `--to STAGE`, `--skip-deploy`.
   - Stages: `requirements context architecture engineering qa devops`.
   - The rest is the requirement. If it is a file path, read it. If it is empty, use the requirement from the conversation; if there is none, ask the human for it.
2. Check the environment: run `craftman-state list` (if the command is not found, use `"${CLAUDE_PLUGIN_ROOT}/bin/craftman-state"` everywhere below). If `.craftman/` does not exist, run the steps of `/ai-craftman:craftman-init` first. If a run is active, ask the human (through human-liaison) whether to resume it (`/ai-craftman:craftman-resume <run-id>`) or start a new one.
3. Run id: `YYYYMMDD-<short-kebab-slug>` (max 40 chars).
4. Profile: if `--profile` was not given, it is decided automatically after step `requirements` from the planner's `size`: small → `lite`, medium or large → `full`. Don't ask; tell the human in the status line (`profile: lite (size small); rerun with --profile full to change`). Until then initialise with `full`.
5. `craftman-state init <run-id> --profile <p> [--from S] [--to S] [--skip-deploy] --max-agent-calls ${user_config.max_agent_calls} --requirement "<first 100 chars>"`
   If the profile changes to lite after step 4, record it: `craftman-state skip <step> "lite profile"` for `gov-requirements approve-architecture design gov-design work-plan tracker-issues security-review`.
6. If `craftman-state init` could not run (no Bash access, script missing, error), STOP and tell the human. Never run the pipeline without state: the approvals and budget hooks depend on it.
7. Create one task-list item per pending step shown in `.craftman/memory/<run-id>/state.md`, so progress is visible and nothing is skipped. Tell the human once: `Live report: .craftman/memory/<run-id>/report.html` (open it in a browser; `craftman-state` refreshes it after every step, and the page reloads itself while the run is in progress).

## 1. The loop

Repeat until `craftman-state next` prints `next: none`:
1. `craftman-state next` → the step and its owner.
2. Run the step exactly as described in section 3.
3. `craftman-state done <step> "<one-line outcome>"` (or `skip <step> "<reason>"`) and tick the task item.
4. Tell the human one status line: `[stage] step: outcome`.

Never mark a step done whose agent returned `status: blocked`, `needs_input` or a failing verdict; resolve it first.

## 2. Rules for every dispatch

- **Fresh agent per unit of work.** Every package step (tdd-engineer or test-writer/code-writer, and code-reviewer, per WP) and every liaison round is a new `Agent` call. Never use `SendMessage` to hand a finished agent a new package, stage or round: its whole context is re-read on every turn, so reusing it multiplies cost. `SendMessage` is only for one follow-up inside the same step (e.g. the planner finalising with the human's answers), at most once. The budget hook counts both.
- **Answers are recorded automatically.** A hook writes every human answer to `answers.md`. Never send answers to the liaison to "record" them; pass them straight to the agent that needs them.
- **Paths, not content.** Give each agent: the run directory `.craftman/memory/<run-id>/`, the input file paths it lists under "Input", and `out: <exact file path>`. Agents write their full output there and return only a short summary + header values + open questions. Never paste one agent's full output into another's prompt. Read a memory file yourself only when you need a specific value.
- **Model tier** (`${user_config.model_tier}`): `economy` → pass `model: sonnet` to agents whose default is opus, and never upgrade. `max` → pass `model: opus` to agents whose default is sonnet. `balanced` or anything else → no override, except that `code-reviewer` gets `model: opus` for packages marked `sensitive: true` and whenever it has `security_focus: true`.
- **Human communication.** Only `ai-craftman:human-liaison` authors questions. Collect all open questions of a step (or of parallel steps) and dispatch the liaison once with them. It returns round 1 as YAML; call `AskUserQuestion` with those questions exactly as written (question, header, options, multiSelect). Pass the answers to the agent that needs them. For further rounds, re-dispatch the liaison with its output path. Never ask anything the liaison did not write, and never invent answers.
- **Research.** Open questions tagged `[research]` go to `ai-craftman:research-agent`, not the human. Batch all of a step's research questions into one dispatch: the questions, the asking agents, the run directory, `R/04-context.md` if it exists, out `R/research/<step>.md`. Then pass that path to the asking agent (one `SendMessage` follow-up, or the agent's next fresh dispatch). Questions it leaves open (`PARTIAL`/`INCONCLUSIVE`) go to the liaison with its options. Research results never override a human answer or governance.
- **Approvals.** An approval is a liaison question whose text starts with `[APPROVAL:<category>]` and whose first option is `Approve`. A hook records every answer in `answers.md` and writes approved grants to `approvals.md`. Deploy, destroy, publish, git push, PR and tracker commands are blocked by a hook until the matching grant exists. Never try to work around the hook or edit those files.
- **Governance gates.** Dispatch `governance` with the gate name, the artifact paths and `.craftman/governance.md`. `BLOCK` → send the findings path back to the producing agent, then re-run the gate. Loop limit: `max_review_loops` from governance.md (default 2). Past the limit: `craftman-state escalate "<what>"` and ask the human through the liaison (fix manually / grant waiver with `[APPROVAL:waiver]` / abort).
- **Oversight gates.** Dispatch `human-oversight` with the gate, artifact paths and governance verdict. `APPROVAL_REQUIRED` → liaison → `[APPROVAL:<category>]` question → Reject means back to the producing agent with the human's reason.
- **Refused writes.** If an agent says its file write was refused and returns the content, write that content to its `out` path yourself, unchanged.
- **Budget.** A hook counts agent dispatches. If it blocks with "budget reached", ask the human through the liaison with `[APPROVAL:budget]`.
- **Verify, don't trust.** After every test-related step, run the test command from the context file yourself and check the result matches the agent's claim.
- **Save wall-clock time.** Steps that don't depend on each other run together, as several Agent calls in one message:
  - `context-memory` runs alongside `architecture` (the architect reads `R/04-context.md`, not the curated memory).
  - `security-review`, `qa` and `docs` all read the committed branch, so dispatch them together. Handle security and QA findings together (fixes go through the engineering fix loop, then both re-check). Re-dispatch docs only if a fix changed a public contract. Mark each step done when it passes.
  - Independent packages run in parallel (see engineering).
- **Questions before engineering.** All human questions are asked in clarifications, architecture, design or work-plan. Engineering agents never stop to ask; they record `## Assumptions` and carry on. Collect every package's assumptions for the summary and the PR body. Only an agent that returns `status: blocked` needs a liaison round during engineering.
- **Escalations.** Any retry limit hit, agent disagreement or blocked agent: `craftman-state escalate "<text>"`, then the liaison.

## 3. Steps

`R` = `.craftman/memory/<run-id>`. `SD` = `${CLAUDE_PLUGIN_ROOT}/templates/standards`. `ARCH` = the design paths: `R/06-hld.md`, plus `R/08a-lld.md` once it exists (in the lite profile the HLD file holds both). Wherever an agent's input says "architecture path", pass `ARCH`. `STD` = the standards files named in the context header (`SD/general.md` plus the stack file). Pass `STD` to architect, test-writer, code-writer, code-optimizer, code-reviewer and qa-engineer.

### Stage 1 — Requirements and planning
- **requirements**: `requirements-planner`, out `R/01-requirements.md`.
- **clarifications**: open questions from the planner. Liaison, out `R/02-questions.md`, then AskUserQuestion. Re-dispatch the planner with the answers and its previous path to finalise `R/01-requirements.md`. No questions → skip with reason "no open questions".
- **gov-requirements**: `governance` gate `requirements`, out `R/03-gov-requirements.md`.

### Stage 2 — Enterprise context and flow
- **context**: `enterprise-context` with `R/01-requirements.md`, `.craftman/context/`, standards dir `SD`, out `R/04-context.md`. Open questions → liaison.
- **legacy-analysis**: only if the context header has `legacy: true`; `legacy-analyst`, out `R/05-legacy.md`. Otherwise skip with reason "legacy: false".
- **context-memory**: `memory-keeper` with `R/04-context.md` (and `R/05-legacy.md`). It saves `.craftman/context/enterprise.md` and `.craftman/context/flows/<name>.md` for future runs. Dispatch it in the same message as the architect and don't wait for it before architecture.

### Stage 3 — Architecture and design
- **architecture** (HLD): `architect` with `level: hld`, requirements, context, legacy paths. Out `R/06-hld.md`. In the lite profile pass `level: combined` instead: one short document with the HLD and LLD sections.
- **gov-architecture**: `governance` gate `architecture` on `R/06-hld.md`, out `R/07-gov-architecture.md`. In the lite profile (combined design) pass gates `architecture` and `design` together.
- **approve-architecture**: `human-oversight` gate `architecture` on the HLD, out `R/08-oversight-architecture.md`. The human approves the big decisions before any detail is written.
- **design** (LLD): a fresh `architect` with `level: lld`, the approved `R/06-hld.md`, requirements, context and `STD`. Out `R/08a-lld.md`. Its open questions go to the liaison now. If it needs to change an HLD decision, that is an open question, not a silent change; an approved change goes back through approve-architecture.
- **gov-design**: `governance` gate `design` on `R/06-hld.md` and `R/08a-lld.md`, out `R/08b-gov-design.md`.
- **work-plan**: `workflow-coordinator`, out `R/09-work-plan.md`. Its open questions go to the liaison now, before engineering. In the lite profile (step skipped) treat the whole change as one package `WP-1` with `size: S`.
- **tracker-issues**: ask the human through the liaison whether to create tracker issues for the packages (GitHub via `gh issue create`, or Jira via a connected MCP server, or none). Creating needs `[APPROVAL:tracker]`. Record issue links in `R/09-work-plan.md` via the coordinator's draft section, or skip with reason.

### Stage 4 — Engineering and modernization
- **git-branch**:
  - Not a git repo → liaison question: initialise git (recommended; enables per-package commits and rollback) or continue without git.
  - Uncommitted changes → liaison question: commit them first (recommended), stash them, or continue on top of them.
  - Then `git switch -c craftman/<run-id>` and `craftman-state set branch craftman/<run-id>`.
- **engineering**: run the work plan's groups in order. All packages of a group run in parallel (one message, several Agent calls). After the skeleton package, the work plan puts every independent slice in one group.
  - With more than one package in a group, each gets a worktree: `git worktree add .craftman/worktrees/<WP> -b craftman/<run-id>-<WP> craftman/<run-id>`. Use a hyphen, not a slash: git cannot create `craftman/<run-id>/<WP>` while the branch `craftman/<run-id>` exists. `workdir` is the worktree path.
  - A group with one package uses the repo root as `workdir`.
  - Tell every engineering agent the context's `fast_test_command` and its package's test paths.

  Per package, with `P = R/eng/<WP>`:
  1. **Build.**
     - `size: S` or `M` → `tdd-engineer` → out `P/2-code.md`. Needs `GREEN` (1 agent call).
     - `size: L`, or `sensitive: true` in the `full` profile → `test-writer` → out `P/1-tests.md` (needs `RED_CONFIRMED`; run the package's tests yourself and confirm the new ones fail), then `code-writer` → out `P/2-code.md` (needs `GREEN`).
     - Then run the package's tests (fast command) and the lint command yourself and confirm both pass.
  2. `code-reviewer` → out `P/3-review.md` (one full pass over tests and code). In the lite profile add `security_focus: true`.
     - `CHANGES_REQUESTED` (critical/high only): findings tagged `[tests]` go to test-writer (or tdd-engineer if it built the package), the rest to code-writer (or tdd-engineer), each a fresh dispatch with the review path. Then re-review with `scope: verify-fixes` and the previous review path, out `P/3-review-<n>.md`. The loop limit applies.
     - Medium and low findings stay under `## Cleanup` and are fixed in step 8, not now.
     - `performance_issue: true`, or a performance NFR touching this package in the `full` profile: dispatch `code-optimizer` → out `P/4-optimize.md` after approval, and re-run tests and lint.
  3. Commit in `workdir`: `git add -A && git commit -m "feat(<run-id>): <WP> <title>"`.
  4. Worktree packages: in the repo root, `git merge --no-ff craftman/<run-id>-<WP>`, then `git worktree remove .craftman/worktrees/<WP>` and `git branch -d craftman/<run-id>-<WP>`. A merge conflict means escalate.
  5. After each group's merges, run the format, lint, typecheck and **full** test commands on the run branch yourself. Failures introduced by the merge go to code-writer for the owning package before the next group starts.
  6. `craftman-state set packages_done "<comma list>"`.
  7. Repeat for the next group.
  8. **Cleanup** (once, after the last group): collect the `## Cleanup` items from every `P/3-review*.md`. If there are any, one `code-writer` dispatch with all those paths (and one `test-writer` dispatch for `[tests]` items, in parallel), out `R/eng/cleanup.md`. Then run format, lint, typecheck and the full suite, and commit `refactor(<run-id>): review cleanup`.

  Mark the step done only when every package is committed and the branch is green on tests, lint and typecheck.
- **security-review**: `security-reviewer` with the architecture path and all changed files (`git diff --name-only <base>...HEAD`), out `R/10-security.md`. Dispatch it in the same message as `qa` and `docs`. `FINDINGS` → back to code-writer for the owning package, then re-review. Skipped in the lite profile: there, the code reviewer ran with `security_focus: true`.

### Stage 5 — Quality assurance and testing
- **qa**: `qa-engineer`, out `R/11-qa.md`. `NOT_READY` → each defect goes back through engineering steps 2 to 6 for its package, then QA re-runs (loop limit applies). Commit QA's new tests: `test(<run-id>): QA suite`.
- **docs**: `doc-writer`, out `R/12-docs.md`, dispatched together with `qa` and `security-review`. Commit: `docs(<run-id>): update documentation`.
- **gov-release**: `governance` gate `release`, out `R/13-gov-release.md`.
- **pull-request**: liaison question `[APPROVAL:git-push]` to push `craftman/<run-id>` and open a PR (options: push and open PR (recommended), keep local only). On approve: `git push -u origin craftman/<run-id>` and `gh pr create` with a body built from the requirements, ADR titles, the QA acceptance matrix and the security verdict. No remote or no `gh` → tell the human and skip with reason.

### Stage 6 — DevOps and operations
- **delivery**: `delivery-manager`, out `R/14-delivery.md`.
  - `SKIP` → skip `deploy-decisions approve-deploy devops` with the evidence as the reason, and still run `operations` as plan only.
  - `ASK` → liaison, then re-dispatch with the answer.
- **deploy-decisions**: liaison with `R/14-delivery.md`. Ask **every** decision, one per question, each with its options and the recommended one. Save the answers path for devops.
- **approve-deploy**: `human-oversight` gate `deployment` (always requires approval). Liaison `[APPROVAL:deploy]` question summarising the decisions. Reject → back to deploy-decisions with the reason.
- **devops**: `devops-engineer` with the answers, `R/14-delivery.md` and the context path, out `R/15-devops.md`. Commit its files: `ci(<run-id>): deployment config`. Show the human the commands awaiting execution. Run them only if `[APPROVAL:deploy]` was granted and the human confirms running them now; the hook blocks them otherwise.
- **operations**: `operations-engineer`, out `R/16-operations.md`, with whether a deploy was executed.

### Finish
- **summary**: `memory-keeper` with the run directory → `R/17-summary.md`.
- `craftman-state finish`.
- Tell the human:
  - what was built and on which branch/PR
  - where the memory lives
  - deployment status
  - open risks and escalations
  - agent calls used and the total duration (from `state.md`), plus the three slowest steps; suggest `/cost` for spend

If the human stops the run, `craftman-state finish aborted`. For an interruption, tell them to use `/ai-craftman:craftman-resume <run-id>`.
