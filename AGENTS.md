# MLOps Canada Construction — Agent Context

## 1. System Overview
  ← A 2026-era MLOps system ingesting Canada federal building registry data (OBD), federal address to coordinate mapping (ODA), and building permits data across multiple Canadian cities, along with synthetic data for transactions transferring ownership of these addresses.

## 2. Core Tech Stack
  ← Categorized table: Runtime, Package Manager, Frontend, LLM Tooling, Data, Testing & Quality, Utilities
  ← All placeholders — the user fills in their actual tools

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

## 5. Workflow: Issue Tracking with github projects

Tie work to github project tickets. Ideally to an existing ticket that already exists (should generally be specified at the start of a piece of work in almost eery case), or by creating a ticket to track work that is doesn't already have a github project ticket assigned for it.

## 6. Workflow: Starting New Work
- Git worktree procedure (create worktree, move session, work, commit, push)
- Generalized from the existing script — no project-specific assumptions

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
- Generalized template: "Run linter → type checker → tests before every commit"
- Placeholder commands the user fills in for their toolchain

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