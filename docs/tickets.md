# Ticket Format

How we write GitHub issues for this repository. A ticket states **what to build
and how to prove it works** — nothing else. Scope metadata lives in GitHub
Projects fields and milestones, so issue bodies never turn into Jira-style
forms.

## Title

```text
<type>(<scope>): <imperative summary>
```

- `<type>` matches the branch prefixes in [`branches.md`](branches.md):
  `feat`, `fix`, `hotfix`, `refactor`, `docs`, `test`, `ci`, `chore`, `ai`.
- `<scope>` is the area touched: `infra`, `ingest`, `contracts`, `spatial`,
  `transform`, `orchestration`, `privacy`, `rag`, `analytics`, `repo`.
- Write an imperative summary of the outcome, not the file or the tool.
- No trailing period; keep it under ~72 characters.

Examples:

```text
feat(infra): stand up Garage S3 buckets and Lakekeeper REST catalog
fix(spatial): handle null postal codes in ODA join
docs(repo): document ticket and PR formats
```

The same shape is used for PR titles, so squash-merge history on `main` stays
consistent. See [`pull-requests.md`](pull-requests.md).

## Milestones

Each phase of the build is a GitHub **Milestone**. The milestone is the only
phase marker — it does not appear in the title and there is no phase field.

| Milestone |
| --- |
| Phase 0 — Repo Hygiene, City Discovery & Dev Bootstrap |
| Phase 1 — Storage & Catalog Foundation (Garage, Postgres, Lakekeeper) |
| Phase 2 — Dual-Track Ingestion & Shift-Left Contracts (Adapters + Redpanda) |
| Phase 3 — SQLMesh Transformations, Spatial Joins & Virtual CI/CD |
| Phase 4 — Dagster Orchestration & OpenLineage/Marquez Spine |
| Phase 5 — Soda Core Observability & Tag-Driven Privacy Scrubbing |
| Phase 6 — Unstructured RAG Pipeline & Eval Gate (LanceDB) |
| Phase 7 — Boring Semantic Layer, FinOps, Chaos GameDay & Map North Star |

Assign the matching milestone **when the issue is created**. Enable the project's
**Auto-add to project** workflow so new issues also land on the board.

## Body template

Copy this into the issue body — the issue form at
`.github/ISSUE_TEMPLATE/work-item.yml` pre-populates it.

````markdown
### Goal

<!-- 1–2 sentences: what this unlocks and why it belongs in this phase. -->

### Scope

- [ ] ...
- [ ] ...

### Out of Scope

<!-- 1–2 bullets to prevent side-quests (especially GIS or tooling rabbit holes). -->
- ...

### DataOps Guardrails

<!-- Check off what applies or mark N/A for pure infra/chore tickets. -->
- [ ] **Privacy / PII:** Zero real PII in Git, fixtures, or post-wall models
- [ ] **Offline CI:** Runnable with synthetic fixtures (`USE_FIXTURES=true`) and no external API calls
- [ ] **Docs / Contracts:** Updated relevant YAML contracts, `.env.example`, or `docs/architecture.md`

### Verification (Done When)

<!-- Exact commands or observable outputs that prove the ticket is finished. -->
- [ ] `...`
````

Keep the body short. If a section needs a paragraph of justification, the
ticket is probably scoped wrong.

## Project fields (not the body)

These are set on the GitHub Project board, never in the Markdown body. There is
no phase field — use the milestone for that.

| Field | Type | Values |
| --- | --- | --- |
| **Plane** | Single select | Data & Compute · Control & Contract · Observability & Governance · Repo / Infra |
| **Effort** | Single select | Low · Medium · High |
| **Status** | Built-in | Backlog → Todo → In progress → In review → Done (plus Not planned / Duplicate) |

Effort guide:

| Value | Rough guide |
| --- | --- |
| **Low** | < ~2h |
| **Medium** | Half day |
| **High** | 1–2 days |

If a ticket does not fit in **High**, split it before starting.

**Status** follows `AGENTS.md` §8. Move the ticket as the work moves; the board
should reflect reality.

## Creating a ticket

1. Use the **Work Item** issue form (or copy the body template).
2. Set the title in `<type>(<scope>): <imperative summary>` form.
3. Assign the matching phase **milestone**.
4. Set **Plane** and **Effort** on the project board.
5. Fill every section of the body; no empty required sections.

## Example ticket

Title: `feat(infra): stand up Garage S3 buckets and Lakekeeper REST catalog`

Milestone: `Phase 1 — Storage & Catalog Foundation (Garage, Postgres, Lakekeeper)`

Project fields: Plane `Data & Compute` · Effort `Medium`

````markdown
### Goal

Stand up the local S3 object store (Garage), shared Postgres 16 metadata DB, and
Lakekeeper REST catalog so all downstream phases can commit Iceberg snapshots
without bucket-TTL collisions.

### Scope

- [ ] Add `docker-compose.yml` services for Garage (`s3.local`), Postgres 16 (`catalog_db`, `dagster_db`, `marquez_db`), and Lakekeeper
- [ ] Bootstrap three Garage buckets: `landing` (30-day S3 lifecycle rule), `warehouse` (no TTL), and `serving` (no TTL)
- [ ] Configure `s3.path-style-access = true` and document SeaweedFS portability rules in `infra/README.md`
- [ ] Add a 10-row PyIceberg smoke test writing/reading a dummy table in `warehouse` via Lakekeeper

### Out of Scope

- Deploying Marquez or Redpanda (handled in separate tickets)
- Ingesting real municipal permit data or StatCan ODB/ODA files

### DataOps Guardrails

- [x] **Privacy / PII:** N/A (synthetic 10-row smoke test only)
- [x] **Offline CI:** Smoke test runs fully locally with zero external network calls
- [x] **Docs / Contracts:** Document `/etc/hosts` (`127.0.0.1 s3.local`), `.env.example` keys, and Garage-to-SeaweedFS rules

### Verification (Done When)

- [ ] `docker compose up -d` brings all three services to healthy state under ~400 MB idle RAM
- [ ] `pytest tests/infra/test_lakekeeper_smoke.py` creates an Iceberg namespace/table, commits 10 rows, and reads snapshot metadata back via Lakekeeper
- [ ] Lifecycle check confirms `landing` has a 30-day expiration rule while `warehouse` and `serving` have none
````

## Using a ticket as an agent prompt

Because every ticket states Goal, Scope, Out of Scope, and exact verification
commands, it can be handed straight to a coding agent:

```bash
gh issue view <num>
```

The **Out of Scope** section is the single best guardrail against both solo
scope creep and agents over-engineering adjacent layers. Keep it specific.

## Comments

Comments are for **state**, not scope: where the work is, what is left, and how
to resume. Scope changes belong in the body (edit it) or in a new ticket.

- Append; never rewrite history. If a note goes stale, add a comment that
  supersedes it instead of editing the old one.
- Lead with a one-line status, then a checklist of what is done and what is
  left, so the boundary is visible at a glance.
- Use GitHub-flavored Markdown checkboxes in comments too: `- [ ]` open,
  `- [x]` done. Never use `☐`, `☑`, `✓`, or other Unicode box or tick
  characters — they render as literal text and do not tick.
- Name the branch and commit (`chore/9-robust-yaml`, `3fb40e8`) so the comment is
  actionable without a follow-up question.
- When work pauses for a human step (rebuild, credentials, review), state
  exactly what to run, from where, and what the next agent should do on return.
- Do not record remote actions as done. Pushes, `gh` calls, and PRs belong to
  the human (`AGENTS.md` §4.5); a comment records intent, not a push.

## Branch and PR linkage

- Branches follow [`branches.md`](branches.md), not the ticket title, e.g.
  `feat/4-garage-lakekeeper-backbone`.
- PRs follow [`pull-requests.md`](pull-requests.md).
- Reference the ticket in the PR body with `Closes #<num>` so the project status
  can move to Done automatically.
