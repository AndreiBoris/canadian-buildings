# MLOps Canada Construction — Agent Context

## 1. System Overview
  ← A 2026-era MLOps system ingesting Canada federal building registry data (OBD), federal address to coordinate mapping (ODA), and building permits data across multiple Canadian cities, along with synthetic data for transactions transferring ownership of these addresses.

## 2. Core Tech Stack

**Application stack** — TBD. Runtime, frontend, and data layer are not chosen yet;
don't infer them from the sandbox image.

**Sandbox toolchain** — baked into the image at build time and fixed at runtime.
The sandbox allow-list is only `openrouter.ai`, `opencode.ai`, and `mcp.exa.ai`, so
these are the only tools available. Full versions and the add-a-tool procedure:
`docs/agent_sandbox.md`.

| Category | Tools |
| --- | --- |
| Agent | opencode 2.4.0 on OpenRouter, Exa MCP (researcher subagent) |
| Python | uv / uvx 0.13.10, system interpreter 3.14 (no downloads) |
| Lint / format | ruff, yamllint, taplo |
| Type check | pyrefly |
| Schema / config | check-jsonschema, jq, yq |
| CI / shell | actionlint, hadolint, shellcheck |
| Secrets | betterleaks |
| Tests | not baked yet — no test runner in the image |

## 3. Documentation Structure
  ├── docs/
  │   ├── INDEX.md              # Entry point — maps every doc and its status
  │   ├── specs/                # High-level specifications (dated, supersession chain)
  │   │   ├── INDEX.md          # Navigation hub: active spec, superseded specs
  │   │   └── YYYY-MM-DD-*.md   # Dated spec files with YAML front matter
  │   └── development/          # Developer guides (worktrees, stacking, evidence, etc.)
Each spec file has YAML front matter: `title`, `status` (draft/active/superseded), `date`, `supersedes`/`superseded_by`.

## 4. Operational Constraints (generalized principles)
1. **Separation of concerns** — UI files are thin wiring; domain logic lives in separate modules
2. **No secrets in output** — API keys, tokens, credentials never rendered, logged, or echoed
3. **Python/scripts own the numbers** — critical values computed by deterministic code, LLM output is advisory
4. **Determinism settings** — temperature=0, fixed seed (advisory); never set require_parameters
5. **The human owns the remote** — pushing and all remote work (`git push`, `git fetch`, `gh`, PRs) is always done by the human. Commit locally and stop; never ask whether to push.
6. **No runtime installs** — the sandbox network is allow-listed, so `pip install`,
   `uv add`, `uv sync`, `uv tool install`, `uvx <tool>`, and `npm install` all fail
   closed. If a tool is missing, stop and report it. Adding one means editing
   `development/sandbox/opencode-strict/opencode.dockerfile` and rebuilding
   (`make sbx-new`) — a reviewed change, not an agent workaround.

## 5. Workflow: Issue Tracking with github projects

Tie work to github project tickets. Ideally to an existing ticket that already exists (should generally be specified at the start of a piece of work in almost eery case), or by creating a ticket to track work that is doesn't already have a github project ticket assigned for it.

Ticket format (title, body, project fields, milestones): see `docs/tickets.md`.
PR format (title, body, stacking): see `docs/pull-requests.md`.

Draft tickets and PRs from those templates; do not invent sections or omit
required ones. In ticket bodies, use GitHub-flavored Markdown checkboxes:
`- [ ]` for open and `- [x]` for done. Never use `☐` or other Unicode box
characters — they do not render as checkboxes on GitHub.

## 6. Workflow: Starting New Work
- Git worktree procedure (create worktree, move session, work, commit)
- Generalized from the existing script — no project-specific assumptions
- Run `make hooks` once per clone — installs the branch-name hook (see `docs/branches.md`)

## 7. Workflow: Stacked Branches (generalized from Stacked PRs)
- When to stack: distinct independently-reviewable stages where later work depends on earlier
- When not to stack: single concern, speculative work, same-file conflicts
- One stack = one worktree; switch layers with `git checkout` inside it
- Merge bottom-up
- Generalized — not tied to `gh stack`, just describes the branching pattern

## 8. Workflow: Task Status Bookkeeping
- git project statuses map the lifecycle:
- `Backlog` → `Todo` → `In progress` → `In review` → `Done`
- Additional `Not planned` (Won't fix) and `Duplicate` statuses are also available 

## 9. Workflow: Pre-Commit Quality Gate
- Run "linter → type checker → tests before every commit"
- Baked tools for the first two stages: `ruff`, `yamllint`, `taplo`, `pyrefly`
- Test runner is not baked yet and lands with the first `pyproject.toml`
  (baked inventory: §2; dependency plan: `docs/agent_sandbox.md`)

## 10. Workflow: Visual/Functional Evidence Before a PR
- Any UI change requires visual evidence — no exceptions
- Verification loop: capture → verify via separate vision model → read report → publish
- After 5 failed attempts, ask for guidance
- CI gate (if applicable) fails a PR touching UI without evidence

## 11. Coding Standards
- Type hints on all public functions
- Tests for all pure functions in core/ and pipeline/
- Max line length
- Use `| None` over `Optional` (Python 3.10+)
- Run quality gate before committing