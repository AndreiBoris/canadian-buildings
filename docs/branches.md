# Git Branches

Please use structured slash-and-kebab-case format:  
\<type\>/\<optional-ticket\>-\<short-kebab-case-description\>  

Examples:

* feat/eng-412-permit-geocoding-buffer  
* fix/auth-token-refresh-race  
* refactor/duckdb-parquet-partitioning  
* chore/upgrade-sqlmesh-deps

### **Core Rules That Hold Up in Practice**

* **Use lowercase and hyphens (kebab-case)**: Avoid uppercase letters, spaces, and underscores. Case-insensitive filesystems (like macOS APFS and Windows NTFS) can cause subtle ref/checkout collisions when casing differs, and hyphens stay URL- and CLI-friendly.  
* **Lead with a clear type prefix**: Use the standard set of prefixes for all branches (see below).
* **Include a ticket or issue ID when tracked**: Putting the issue key right after the slash (feat/PROJ-123-...) makes cross-referencing PRs, logs, and issue trackers effortless without bloating branch names with full titles.  
* **Keep the description concise (3–5 words)**: Aim for intent \+ scope, not a sentence. If a branch feels like it needs a paragraph to explain what's in it, the scope is usually too broad. (The hook enforces 1–5 words; 3–5 is the target.)  
* **Avoid personal prefixes for shared work**: Names like andrei/fix-something tie work to a person rather than the change. If you do personal scratch branches locally, keep them short-lived and don't let them become long-lived integration branches.  
* **Delete after merge**: Short-lived topic branches paired with main (or trunk-based workflows) keep git branch \-a and remote refs clean.

### Prefixes to use

- `feat/`
- `fix/`
- `hotfix/`
- `refactor/`
- `docs/`
- `test/`
- `ci/`
- `chore/`
- `ai/` (automated PRs without human drive)

### Enforcement

A local git hook enforces this convention on every commit and push. Install it once per clone:

```bash
make hooks
```

This sets `core.hooksPath` to the versioned `.githooks/` directory, which lives in the shared git config, so the hook applies to every worktree. Disable it with `make hooks-off`; run the rule's tests with `make hooks-test`.

Accepted shapes:

```text
<type>/<ticket>-<description>
<type>/<description>
```

- `<type>` is one of the prefixes above.
- `<ticket>` is optional and lowercase: `42` or `eng-412`.
- `<description>` is 1–5 lowercase kebab-case words.
- A ticket is optional, but a description is not — a branch cannot be just a number or a ticket key (`chore/412` and `feat/eng-412` are rejected).
- `main` is always allowed; a detached HEAD (rebase, merge, CI checkout) is skipped.

The hook is a convenience, not a guarantee: `git commit --no-verify` and `git push --no-verify` bypass it.
