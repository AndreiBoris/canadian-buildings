# Pull Request Format

A ticket defines **what to build and how to prove it**. A PR captures **what
actually changed, the trade-offs made along the way, and proof the verification
passed**. Never copy the ticket body into the PR — link the ticket and show
receipts.

## Title

```text
<type>(<scope>): <imperative summary>
```

Examples:

```text
feat(infra): stand up Garage buckets and Lakekeeper catalog
fix(spatial): handle null postal codes in ODA join
docs(repo): document ticket and PR formats
```

- `<type>` and `<scope>` follow [`branches.md`](branches.md) and
  [`tickets.md`](tickets.md).
- GitHub uses the PR title as the squash commit message, so Conventional Commit
  titles give `main` a clean linear history for free.
- Enable **Default to PR title for squash merge commits** in the repository's
  merge settings (one-time, human-owned).
- No phase tags in PR titles. The phase lives in the linked ticket's milestone.

## Body template

`.github/PULL_REQUEST_TEMPLATE.md` pre-fills this on every new PR.

````markdown
<!-- Use `Closes #<num>` on the final PR. If stacking multiple PRs for one ticket, use `Part of #<num>` on earlier PRs and note `Base: #<pr>`. -->
Closes #

### What Changed & Why
<!-- 2–4 bullets covering key changes, architectural trade-offs, or deviations from the ticket. -->
-

### DataOps & Contract Impact
<!-- Mark N/A for pure repo/tooling chores. -->
- **Contracts / Schemas:** None | Updated `<contract or table>`
- **SQLMesh / Data Diff:** N/A | Virtual env plan clean (see CI diff comment)
- **Privacy / PII Boundary:** Zero real PII in diff, fixtures, or post-wall models

### Verification
<!-- Exact commands run and the actual observed results matching the ticket's "Done When". -->
- [ ] `<command>` — `<result>`
- [ ] Offline fixture run (`USE_FIXTURES=true`) passes
- [ ] Secret scan clean

### Pre-Merge Check
- [ ] Updated `.env.example`, contracts, or `docs/architecture.md` if boundaries changed
- [ ] No raw data dumps, local DBs, or storage volumes staged
````

## Stacked PRs

- Use `Part of #<num>` on every PR except the last, plus `Base: #<pr>` naming
  the PR it stacks on.
- Put `Closes #<num>` **only on the final PR**.
- Why: `Closes` auto-closes the issue and moves the project card to Done the
  moment it merges. On PR 1 of 3, that would mark unfinished work complete.

## Keep the body lightweight

- Do not paste large diffs or table/schema comparisons. Once Phase 3 is wired
  up, GitHub Actions posts the SQLMesh dev-vs-prod diff as an automated PR
  comment; the body stays scannable months later.
- Deviations from the ticket belong in **What Changed & Why** — call them out
  explicitly rather than silently diverging.

## Example PR

Title: `feat(infra): stand up Garage S3 buckets and Lakekeeper REST catalog`

Branch: `feat/4-garage-lakekeeper-backbone`

````markdown
Closes #4

### What Changed & Why
- Added `docker-compose.yml` services for Garage (`s3.local`), shared Postgres 16 (`catalog_db`, `dagster_db`, `marquez_db`), and Lakekeeper with path-style S3 access enabled.
- Added an idempotent bootstrap script creating `landing` (30-day S3 lifecycle rule using Garage's `<Filter>` XML syntax), `warehouse` (no TTL), and `serving` (no TTL).
- Documented `/etc/hosts` setup and SeaweedFS migration constraints in `infra/README.md`.
- *Deviation from ticket:* Pinned Garage to a fixed layout version in `garage.toml` so restarts don't reset bucket keys locally.

### DataOps & Contract Impact
- **Contracts / Schemas:** None (smoke-test table only)
- **SQLMesh / Data Diff:** N/A
- **Privacy / PII Boundary:** Confirmed — synthetic 10-row smoke test only

### Verification
- [x] `docker compose up -d && docker stats --no-stream` — all 3 containers healthy at ~340 MB combined idle RAM
- [x] `pytest tests/infra/test_lakekeeper_smoke.py` — 1 passed (committed 10 rows to `warehouse`, verified snapshot ID via Lakekeeper REST API)
- [x] `aws --endpoint-url http://s3.local:3900 s3api get-bucket-lifecycle-configuration --bucket landing` — confirmed 30-day expiration; `warehouse` and `serving` return `NoSuchLifecycleConfiguration`
- [x] Offline fixture run (`USE_FIXTURES=true`) passes
- [x] Secret scan clean

### Pre-Merge Check
- [x] Updated `.env.example` and `infra/README.md`
- [x] No raw data dumps, local DBs, or storage volumes staged
````
