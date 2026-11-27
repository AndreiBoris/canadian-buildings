# Agent Sandbox using Docker Sandboxes (sbx)

## Main Usage

Once set up, run the sandbox from anywhere in the repo — any worktree or
subdirectory:

```bash
make lock   # host only: resolve pyproject.toml into uv.lock
make sbx
```

The sandbox is a single kit and a single sandbox:

- Kit: `~/.config/sbx-kits/opencode`
- Sandbox: `opencode-worktrees`
- State volume: `/home/agent/.local/share/opencode`

`make sbx` computes a content hash over `opencode.dockerfile`, `opencode.yaml`,
`opencode.json`, `pyproject.toml`, `uv.lock`, and `.dockerignore`. It compares
that hash with `~/.cache/opencode-sbx/opencode-worktrees.kit.hash`. If the stamp
matches and the sandbox exists, it re-attaches. Otherwise it runs `make sbx-new`.

`make sbx-new`:

1. runs `sbx-settings` → `sbx-apply` → `apply-rules.sh`, copying the kit,
   `pyproject.toml`, `uv.lock`, `.dockerignore`, and a generated `sandbox.hash`
   into `~/.config/sbx-kits/opencode`;
2. runs `sbx-rm`, which flushes the OpenCode WAL and removes the sandbox while
   keeping the volume;
3. writes the current hash to the kit stamp;
4. runs `SBX_KIT_BUILDER=sandbox sbx run --name opencode-worktrees opencode .`
   from the worktrees root.

Because the sandbox name and volume path do not change, rebuilding keeps the
OpenCode state volume and session history. The sandbox is shared across
worktrees: a dependency or kit change in any worktree changes the hash and
triggers a rebuild.

### Dependency workflow

1. Edit `pyproject.toml`.
2. Run `make lock` on the host. It resolves in a throwaway, unprivileged,
   digest-pinned Python-enabled `uv` container; lock resolution never runs on
   the host.
3. Review the `uv.lock` diff.
4. Run `make sbx`. The new hash triggers `make sbx-new`, which rebuilds the
   sandbox and re-attaches.

`[tool.uv] exclude-newer = "7 days"` in `pyproject.toml` limits resolution to
packages published at least seven days ago.

`make lock` is host-only in practice: the sandbox network allow-list blocks
PyPI and the sandbox does not expose a Docker daemon to the agent. `make
uv-digest` and `make uv-lock-digest` print the expected build and lock image
digests for review.

### Changing config

Editing anything covered by `image-hash.sh` changes the hash. `make sbx`
detects the change and rebuilds automatically. To force a rebuild without a
hash change:

```bash
make sbx-new
```

A running session can block `sbx rm`. For an unattended rebuild, run:

```bash
make sbx-new SBX_RM_FLAGS=--force
```

### Make targets

| Target | What it runs |
| --- | --- |
| `make lock` | `uv lock --no-build --no-python-downloads` in a throwaway digest-pinned Python-enabled `uv` container (host only) |
| `make uv-digest` | prints the build-stage `ghcr.io/astral-sh/uv` index digest for review |
| `make uv-lock-digest` | prints the lock-stage Python-enabled `uv` index digest for review |
| `make sbx` | re-attaches when the hash stamp and sandbox match; otherwise runs `sbx-new` |
| `make sbx-new` | `sbx-settings` → `sbx-rm` (WAL flush) → stamp → `SBX_KIT_BUILDER=sandbox sbx run --name opencode-worktrees opencode .` |
| `make sbx-shell` | ensure the sandbox, then `sbx exec -i [-t] -u agent -w <worktrees root> <sandbox> -- bash -l` |
| `make sbx-exec` | `make sbx-exec CMD="…"`; ensure the sandbox, then run the command in the worktrees root as `agent` |
| `make sbx-apply` | copies kit and locked project files into `~/.config/sbx-kits/opencode` |
| `make sbx-settings` | `sbx settings set kit.shortcuts.opencode "$HOME/.config/sbx-kits/opencode"` |
| `make sbx-check-policy` | asserts the sandbox has exactly the three strict allow-list domains |
| `make sbx-flush` | checkpoints the OpenCode WAL and `sync -f`s the state volume |
| `make sbx-rm` | `make sbx-flush` → `sbx rm …` (prompts; keeps the volume) |
| `make sbx-where` | prints the worktrees root, sandbox name, hash, stamp, and kit dir |
| `make sbx-ls` | `sbx ls` |
| `make sbx-version` | `sbx exec … -- opencode --version` |

The worktrees root is derived from `git rev-parse --git-common-dir` (two levels
up from `main/.git`), so the targets work from any worktree. The sandbox name is
overridable:

```bash
make sbx WORKTREES_ROOT=/path/to/worktrees
make sbx-new SANDBOX_NAME=my-sandbox
```

If the worktrees root or sandbox name cannot be resolved, the targets stop and
ask you to set `WORKTREES_ROOT` or `SANDBOX_NAME`.

### Policy and volume check

Run once after the first `make sbx`:

```bash
make sbx-check-policy
sbx policy ls "opencode-worktrees" --wide --type network
```

The policy must contain exactly `openrouter.ai:443`, `opencode.ai:443`, and
`mcp.exa.ai:443`, with no wildcard or extra allow rule. Also confirm the volume
and the 30-second WAL flush hook:

```bash
df -h /home/agent/.local/share/opencode
ps aux | grep opencode-state-flush
```

### Session persistence

OpenCode state lives at `/home/agent/.local/share/opencode` (`opencode.db`,
WAL/SHM, logs, snapshots). The kit mounts that path as a private block
`volume@1` (`1g`, mode `0755`), and an install hook gives it to `agent`.

- The volume survives `sbx rm` and `make sbx-new` when the sandbox name, kit
  directory, and volume path stay the same.
- Requires sbx **0.50.0+**. `make sbx-new` and `make sbx-rm` fail fast on older
  versions; `SBX_MIN_VERSION=...` overrides at your own risk.
- Block storage keeps SQLite WAL locking and shared-memory semantics working. Do
  not replace it with a host bind mount, and never share `opencode.db` with host
  OpenCode or another sandbox.
- `make sbx-rm` keeps the volume. To start with fresh storage, use a new
  `SANDBOX_NAME`; `sbx reset` wipes all sandbox data.
- Do not change `size`, `mode`, or `tmpfs` against a retained volume; creation
  refuses. Use a new sandbox name instead.
- The first rebuild after adding the volume starts empty; sessions in the old
  sandbox root filesystem are not migrated.
- `~/.local/state/opencode` and `~/.cache/opencode` are not on the volume; they
  remain ephemeral runtime state/cache.

#### Why a volume alone is not enough

OpenCode opens SQLite with `journal_mode=WAL` and `synchronous=NORMAL`, so a
session commit lands in `opencode.db-wal` without an fsync. `sbx rm` destroys
the microVM and the guest never flushes its page cache, so everything since the
last checkpoint is lost even though the volume itself is retained. That is why
`make sbx-new` and `make sbx-rm` run `make sbx-flush` first:

- `PRAGMA wal_checkpoint(PASSIVE)` copies WAL frames into `opencode.db` without
  blocking a running OpenCode; an incomplete checkpoint is fine.
- `sync -f /home/agent/.local/share/opencode` flushes the state volume, and only
  that volume, to disk.

A background `startup` hook repeats the scoped flush every 30 s as crash
insurance, so an unexpected kill loses at most that window.

`SKIP_FLUSH=1` skips the flush when a sandbox is wedged; use it only when the
recent session history does not matter. Running `sbx rm` directly, outside the
Makefile, also bypasses the flush.

## Baked Toolchain

The sandbox ships a fixed dev toolchain, installed at image build time. Runtime
package installation stays disabled: the network policy only allows
`openrouter.ai`, `opencode.ai`, and `mcp.exa.ai`, so `pip install`, `uv add`,
`uv sync`, `uv tool install`, `uvx <tool>`, and `npm install` all fail closed.

Versions are pinned as `ARG`s at the top of
`development/sandbox/opencode-strict/opencode.dockerfile`.

| Tool | Version | Source | Path |
| --- | --- | --- | --- |
| opencode | 2.4.0 | npm `@opencode/cli` | on `PATH` |
| uv / uvx | 0.13.10 | `ghcr.io/astral-sh/uv` | `/usr/local/bin/uv`, `/usr/local/bin/uvx` |
| ruff | 0.17.6 | `uv tool` (PyPI) | `/usr/local/bin/ruff` |
| pyrefly | 1.5.0 | `uv tool` (PyPI) | `/usr/local/bin/pyrefly` |
| yamllint | 1.38.0 | `uv tool` (PyPI) | `/usr/local/bin/yamllint` |
| check-jsonschema | 0.39.0 | `uv tool` (PyPI) | `/usr/local/bin/check-jsonschema` |
| taplo | 0.10.0 | GitHub release, SHA256-verified per arch | `/usr/local/bin/taplo` |
| yamlfmt | 0.21.0 | `ghcr.io/google/yamlfmt` | `/usr/local/bin/yamlfmt` |
| jq | 1.8.2 | `ghcr.io/jqlang/jq` | `/usr/local/bin/jq` |
| yq | 4.54.3 | `mikefarah/yq` | `/usr/local/bin/yq` |
| actionlint | 1.7.12 | `rhysd/actionlint` | `/usr/local/bin/actionlint` |
| hadolint | 2.15.1 | `hadolint/hadolint` | `/usr/local/bin/hadolint` |
| shellcheck | 0.11.0 | `koalaman/shellcheck` | `/usr/local/bin/shellcheck` |
| betterleaks | 1.9.0 | `ghcr.io/betterleaks/betterleaks` | `/usr/local/bin/betterleaks` |

The four `uv tool` packages live in `/opt/uv-tools` (`UV_TOOL_DIR`), with their
entry points in `/usr/local/bin` (`UV_TOOL_BIN_DIR`); `uv tool list` reports them.

### Locked Python environment

`pyproject.toml` and `uv.lock` are copied into `/opt/project` and installed into
`/opt/venv` with `uv sync --locked --no-install-project --no-build`. The venv is
root-owned and read-only to `agent`; `UV_PROJECT_ENVIRONMENT=/opt/venv`,
`VIRTUAL_ENV=/opt/venv`, and `/opt/venv/bin` on `PATH` make pytest and pyrefly
resolve the locked packages. At runtime `UV_OFFLINE=1` and `UV_NO_SYNC=1` keep
the environment immutable, so `uv add`, `uv sync`, and `uv tool install` fail
closed.

### Adding or bumping a tool

1. Change the version `ARG` at the top of the Dockerfile (or add a new stage).
2. Add the binary to the build-time smoke test.
3. Run `make sbx-new` and the acceptance checks below.

Binary stages are `COPY --link`'d after the network layers, so a version bump
that only touches a static binary rebuilds in about a second.

### Caveats

- **Interpreter is fixed.** `UV_PYTHON_PREFERENCE=only-system` with
  `UV_PYTHON_DOWNLOADS=never` means the image's Python 3.14 is the only
  interpreter. `uv venv --python 3.12` fails fast. Bake another interpreter
  (`uv python install 3.13` in the image) rather than relaxing the runtime
  policy.
- **Project dependencies are baked from the lockfile.** `make lock` must run
  before `make sbx` after any `pyproject.toml` edit; `uv sync --locked` fails the
  image build when the lockfile is stale. There is no runtime dependency
  installation layer.
- **`/home/agent/.local/bin` precedes `/usr/local/bin` on `PATH`**, so anything
  the agent installs would shadow a baked binary. This is another reason runtime
  installs stay disabled.

### Acceptance checks

After `make sbx-new`, inside the sandbox:

```bash
uv tool list              # ruff, pyrefly, yamllint, check-jsonschema
jq --version              # jq-1.8.2
command -v jq             # /usr/local/bin/jq
ruff --version && taplo --version && yamlfmt -version && pyrefly --version
yamllint --version && check-jsonschema --version
actionlint -version && hadolint --version && shellcheck --version
betterleaks version && yq --version
/opt/venv/bin/python --version
/opt/venv/bin/python -c "import duckdb; assert duckdb.sql('SELECT 1').fetchone() == (1,)"
/opt/venv/bin/python -m pytest --version
test ! -w /opt/venv && echo "/opt/venv is read-only"
```

The image's build-time smoke test already runs every one of these as `agent`, so
a PATH, permission, or architecture regression fails the build instead of first
use. The same checks are available as `make sbx-accept`; it runs inside the
sandbox and delegates automatically when invoked from the host.

### Quality gate

`make verify` runs the pre-commit checks: stale-image guard, lint, typecheck, and
tests. Inside the sandbox it runs directly. On the host it delegates into the
sandbox, so the checks always use the baked toolchain and never run natively on
macOS. The guard compares the current content hash with
`/etc/opencode/sandbox.hash` and fails fast when the working tree no longer
matches the running image.

`make format` is the mutating counterpart (`ruff format` + `taplo fmt`). It also
delegates into the sandbox when invoked from the host.

`make typecheck` uses pyrefly with `/opt/venv/bin/python` so the locked DuckDB
install and its type information are visible. `make test` runs pytest from
`/opt/venv`.

- A **stopped** sandbox is started on demand by `sbx exec`. The commit proceeds
  once the sandbox is up; expect a short boot delay.
- A sandbox that **does not exist** fails closed. Create it with `make sbx` or
  `make sbx-new` and retry.
- The `.githooks/pre-commit` hook calls `make verify`; there is no skip-if-missing
  fallback. `git commit --no-verify` remains git's own escape hatch.

### Pinning the base image, Dockerfile frontend, and uv

The base image, BuildKit frontend, and uv images are pinned by digest:

```dockerfile
# syntax=docker/dockerfile:1@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
FROM docker/sandbox-templates:opencode@sha256:7feb9784bc882dbe014888becb65c23e7fb1d1b24169a68d33660fe44476a0b4
FROM ghcr.io/astral-sh/uv:0.13.10@sha256:a3ea1357342c1a4bf9a0c53a3deb1b55379aefa037338d8113d5771efa01774f
```

The lock container uses the Python-enabled variant, also digest-pinned:

```text
ghcr.io/astral-sh/uv:0.13.10-python3.14-trixie@sha256:65557d27bba9d043ce89a7f1ef82bfdaffb1ce45f5e81fce1efd085050673154
```

Re-resolve them on the host when bumping:

```bash
for ref in docker/dockerfile:1 docker/sandbox-templates:opencode ghcr.io/astral-sh/uv:0.13.10 ghcr.io/astral-sh/uv:0.13.10-python3.14-trixie; do
  digest=$(docker buildx imagetools inspect "$ref" | awk '/^Digest:/ {print $2; exit}')
  printf "%s@%s\n" "$ref" "$digest"
done
```

Use the top-level `Digest:` line (the multi-arch index), not a per-platform
digest. Update the Dockerfile/Makefile and this document together, then run
`make sbx-new` and the acceptance checks. `make uv-digest` and `make
uv-lock-digest` query the live registry for the upstream index digest of the
pinned tags; compare the output with the values in the Dockerfile/Makefile.

## Summary Notes

- **MicroVM Isolation:** Runs OpenCode inside an isolated microVM (own kernel, filesystem, and internal Docker daemon)—no host Docker daemon exposure.
- **Host-Proxy Secret Injection:** API keys live in the OS keychain (`sbx secret`); the sandbox only sees placeholders while an outbound host proxy injects real keys at the boundary.
- **Scoped Workspace:** Only explicitly passed directories are bind-mounted (at identical host paths). `~/.config/opencode` is **not** mounted—keep project configs in repo-level `opencode.json` / `.opencode/`.
- **Workspace `.env` Warning:** Any `.env` inside a mounted repo is readable by the agent. Keep real keys out of mounted `.env` files.

## Setup Guide

Install:

```bash
brew trust docker/tap
brew install docker/tap/sbx
```

Sign in:

```bash
sbx login
```

Initialize a strict network policy (one-time; skip if already initialized):

```bash
sbx policy init deny-all
```

Save a key to credential storage:

```bash
sbx secret set openrouter         # stores in OS keychain (use spend-capped key)
sbx secret set openrouter --sandbox <name>   # optional per-sandbox override
```

v3 kits need `sbx` 0.50.0 or later for persistent volumes (`sbx version`).

## Run

Mount the directory that contains all your git worktrees.

```bash
# First build (can take a few minutes):
make lock
make sbx-new

# Re-attach, or rebuild when the content hash changes:
make sbx
```

`make sbx-new` applies the kit, flushes the OpenCode WAL, removes the sandbox,
and rebuilds it with `SBX_KIT_BUILDER=sandbox`. The volume is retained, so
session history survives the rebuild.

If you need to change the configuration for everyone, edit the kit files in
`development/sandbox/opencode-strict/`; the hash changes and `make sbx` rebuilds.

## Manual commands (`sbx-shell`, `sbx-exec`)

Run dev commands inside the same sandbox as the agent, without starting the
agent TUI:

```bash
make sbx-shell                              # interactive shell
make sbx-exec CMD="ruff --version"          # one-shot from the worktrees root
make sbx-exec CMD="cd main && make verify"  # anything needing a worktree
make sbx-exec CMD='echo "$HOME" && pwd'     # quoting and $VAR pass through
make sbx-exec CMD="pwd" < /dev/null         # no TTY needed
```

Both targets ensure the sandbox first: a missing or stale sandbox is rebuilt
with `sbx-new` using `sbx create`, so no agent session is opened. The new
sandbox may stay `running` for tens of seconds and then idle-stops; the first
`sbx exec` starts it on demand. Commands run in the worktrees root as the
`agent` user (`-u agent`, matching `sbx-flush`) with the same `PATH` as
`make verify`, and `sbx exec` allocates a TTY only when stdin and stdout are
terminals.

The worktrees root is not a git repository. `cd` into the worktree you are
working in — for example `main`, or your own branch's worktree — before running
`git` or `make`, as in the `cd main` example above.

- **Exit codes:** the in-sandbox status is printed as `sbx-exec: command exited N`
  and the make target fails. GNU make itself exits `2` for any failed recipe;
  `125` means sbx could not run the command (for example, no sandbox), and `127`
  means the command was not found in the sandbox.
- **Cold-start/rebuild output** goes to stderr, so piping `sbx-exec` stdout is
  safe. Rebuild stdin is isolated: piped input is never consumed by `sbx rm`'s
  confirmation prompt.
- **Rebuild while the agent is attached:** `sbx-ensure` never passes `--force`
  to `sbx rm`, so a kit change with an active session — or without a terminal
  available to confirm the prompt — fails closed with a hint. Quit the agent
  (`make sbx`) first, or run `make sbx-new` yourself.
- **Concurrent writes:** running commands while the agent is active is
  supported, but keep one writer per resource. Concurrent `git add`/`commit`
  races on `.git/index.lock`, SQLite and other single-writer DB files cannot be
  shared, and two `make verify` runs can contend on tool caches. Lifecycle
  operations (`sbx-new`, `sbx-rm`) are serialized per sandbox and refuse to
  remove one with an attached session.

## Configure

```bash
sbx policy ls                                  # list policies
sbx policy ls --wide                           # list rules with IDs and resources
sbx policy inspect <policy-or-rule-id>         # inspect a policy or rule
sbx policy allow network openrouter.ai:443     # allow endpoint
sbx policy rm network --resource openrouter.ai:443   # remove rule by resource
sbx policy rm network --id <rule-id>           # remove rule by ID
sbx policy log                                 # inspect allowed/blocked requests

sbx                                            # open TUI dashboard
sbx stop <name>                                # suspend microVM
sbx rm <name>                                  # destroy VM state (keeps host files, volume; prompts)
```

Add a network capability on an existing sandbox:

```bash
sbx policy allow network --sandbox opencode-worktrees <host>:443
```

Remove a network capability on an existing sandbox:

```bash
sbx policy rm network --sandbox opencode-worktrees --resource <host>:443
```

Block network capability on an existing sandbox:

```bash
sbx policy deny network --sandbox opencode-worktrees <host>
```

Remove sandbox:

```bash
make sbx-rm                              # flush the WAL, then: sbx rm opencode-worktrees
make sbx-rm SBX_RM_FLAGS=--force         # unattended; no confirmation prompt
make sbx-rm SKIP_FLUSH=1                 # skip the WAL flush (may lose recent sessions)
```

Removing the sandbox keeps the OpenCode state volume. The Makefile flushes the
WAL first; a direct `sbx rm` does not. To start with fresh storage, use a new
sandbox name (`make sbx-new SANDBOX_NAME=opencode-worktrees-fresh`); to wipe
everything, run `sbx reset`.

Ensure your sandbox is running opencode v2.x.x:

```bash
make sbx-version       # or: sbx exec opencode-worktrees -- opencode --version
```

`sbx exec` needs `--` before a command that has flags, so `--version` reaches
opencode instead of sbx.
