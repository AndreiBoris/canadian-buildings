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
