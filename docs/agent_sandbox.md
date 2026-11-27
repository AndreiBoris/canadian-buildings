# Agent Sandbox using Docker Sandboxes (sbx)

## Main Usage

Once set up, run the sandbox from anywhere in the repo — any worktree or subdirectory:

```bash
make lock   # host only: resolve pyproject.toml into uv.lock
make sbx
```

`make sbx` computes a content hash over `opencode.dockerfile`, `opencode.yaml`,
`opencode.json`, `pyproject.toml`, `uv.lock`, and `.dockerignore`. It uses that
hash for both the image tag (`opencode-sandbox:<hash12>`) and the sandbox name
(`opencode-wt-<hash12>`), then runs from the directory that contains all the
worktrees. The sandbox mounts the whole worktrees tree, so linked-worktree
`.git` pointers keep working and the agent can create or switch worktrees.

Worktrees with identical inputs share one sandbox and one OpenCode session
history. A change to `pyproject.toml`, `uv.lock`, the Dockerfile, or the kit
policy produces a new hash and a new sandbox without stopping the old one.

### Dependency workflow

1. Edit `pyproject.toml`.
2. Run `make lock` on the host. It resolves in a throwaway, unprivileged,
   digest-pinned Python-enabled `uv` container; lock resolution never runs on
   the host.
3. Review the `uv.lock` diff.
4. Run `make sbx`. The new hash builds and loads a new image, then starts a new
   sandbox.

`[tool.uv] exclude-newer = "7 days"` in `pyproject.toml` limits resolution to
packages published at least seven days ago.

`make lock` is host-only in practice: the sandbox network allow-list blocks
PyPI and the sandbox does not expose a Docker daemon to the agent. `make
uv-digest` and `make uv-lock-digest` print the expected build and lock image
digests for review.

### Changing the sandbox image

`make sbx` builds and loads `opencode-sandbox:<hash12>` only when
`sbx template inspect` cannot find it. `make sbx-new` flushes the OpenCode WAL,
removes the current hash sandbox, rebuilds the image, and runs it.

The old `make sbx-apply` / `make sbx-settings` targets are kept as a legacy
manual kit path. The hash-tagged image path does not mutate
`~/.config/sbx-kits/`.

### Make targets

| Target | What it runs |
| --- | --- |
| `make lock` | `uv lock --no-build --no-python-downloads` in a throwaway digest-pinned Python-enabled `uv` container (host only) |
| `make uv-digest` | prints the build-stage `ghcr.io/astral-sh/uv` index digest for review |
| `make uv-lock-digest` | prints the lock-stage Python-enabled `uv` index digest for review |
| `make sbx` | ensures `opencode-sandbox:<hash12>` exists, then `sbx run --template … --name opencode-wt-<hash12> opencode "$(WORKTREES_ROOT)"` |
| `make sbx-new` | `sbx-flush` → `sbx rm` → rebuild/load image → run |
| `make sbx-image` | builds and loads `opencode-sandbox:<hash12>` from an ephemeral build context |
| `make sbx-ensure` | builds the image only if the template tag is missing |
| `make sbx-check-policy` | asserts the sandbox has exactly the three strict allow-list domains |
| `make sbx-prune` | reports templates and sandboxes; `PRUNE=1` removes only templates whose hash sandbox does not exist |
| `make sbx-kit` | fallback: run from a hash-keyed kit descriptor so `opencode.yaml` capabilities are applied |
| `make sbx-apply` | legacy: copy kit and locked project files to `~/.config/sbx-kits/opencode` |
| `make sbx-settings` | legacy: set the `kit.shortcuts.opencode` shortcut |
| `make sbx-flush` | checkpoints the OpenCode WAL and `sync -f`s the state volume |
| `make sbx-rm` | `make sbx-flush` → `sbx rm …` (prompts; keeps the volume) |
| `make sbx-where` | prints the worktrees root, sandbox name, image tag, and hash |
| `make sbx-ls` | `sbx ls` |
| `make sbx-version` | `sbx exec … -- opencode --version` |

The worktrees root is derived from `git rev-parse --git-common-dir` (two levels
up from `main/.git`), so the targets work from any worktree. The sandbox name is
always passed explicitly and defaults to `opencode-wt-<hash12>`. Override either
when needed:

```bash
make sbx WORKTREES_ROOT=/path/to/worktrees
make sbx-new SANDBOX_NAME=my-sandbox
```

If the worktrees root or sandbox name cannot be resolved, the targets stop and
ask you to set `WORKTREES_ROOT` or `SANDBOX_NAME`.

When a rebuild forces removal, `sbx rm` asks for confirmation and refuses while a
session is attached. For an unattended rebuild, run
`make sbx-new SBX_RM_FLAGS=--force`.

### Policy and volume check

Run once after the first `make sbx`:

```bash
make sbx-check-policy
sbx policy ls --sandbox "opencode-wt-<hash12>" --wide
```

The policy must contain exactly `openrouter.ai:443`, `opencode.ai:443`, and
`mcp.exa.ai:443`, with no wildcard. Also confirm that the
`/home/agent/.local/share/opencode` volume and the 30-second WAL flush startup
hook are attached. The kit-descriptor fallback exists for hosts where
`sbx run --template` does not inherit those kit capabilities:

```bash
make sbx SBX_RUNTIME=kit
make sbx-new SBX_RUNTIME=kit
```

It stages a hash-keyed kit, builds it with `SBX_KIT_BUILDER=sandbox`, and
always passes the absolute `$(WORKTREES_ROOT)`.

### Pruning

```bash
make sbx-prune                    # report templates and sandboxes
make sbx-prune PRUNE=1            # remove templates whose hash sandbox is gone
make sbx-prune PRUNE_SANDBOXES=1  # list stopped hash sandboxes and removal commands
```

`PRUNE=1` keeps the current tag and every template whose matching
`opencode-wt-<hash12>` sandbox still exists, including stopped sandboxes.
`PRUNE_SANDBOXES=1` does not run a global `sbx prune`; it prints the safe
`make sbx-rm SANDBOX_NAME=...` commands so the WAL flush is preserved.

### Session persistence

OpenCode state lives at `/home/agent/.local/share/opencode` (`opencode.db`, WAL/SHM, logs, snapshots). The kit mounts that path as a private block `volume@1` (`1g`, mode `0755`), and an install hook gives it to `agent`.

Each hash-named sandbox is expected to own its own volume. Confirm with the host
spike whether two concurrent `opencode-wt-*` sandboxes isolate or share the
volume; do not assume sharing is safe.


- The volume survives `sbx rm` and `make sbx-new` when the sandbox name, kit source directory, and volume path stay the same.
- Requires sbx **0.50.0+**. `make sbx-new` and `make sbx-rm` fail fast on older versions; `SBX_MIN_VERSION=...` overrides at your own risk.
- Block storage keeps SQLite WAL locking and shared-memory semantics working. Do not replace it with a host bind mount, and never share `opencode.db` with host OpenCode or another sandbox.
- `make sbx-rm` keeps the volume. To start with fresh storage, use a new `SANDBOX_NAME`; `sbx reset` wipes all sandbox data. `sbx volume` is cloud-only, and there is no supported selective local volume delete.
- Do not change `size`, `mode`, or `tmpfs` against a retained volume; creation refuses. Use a new sandbox name instead.
- The first rebuild after adding the volume starts empty; sessions in the old sandbox root filesystem are not migrated.
- `~/.local/state/opencode` and `~/.cache/opencode` are not on the volume; they remain ephemeral runtime state/cache.

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

- **Interpreter is fixed.** `UV_PYTHON_PREFERENCE=only-system` with `UV_PYTHON_DOWNLOADS=never`
  means the image's Python 3.14 is the only interpreter. `uv venv --python 3.12`
  fails fast. Bake another interpreter (`uv python install 3.13` in the image)
  rather than relaxing the runtime policy.
- **Project dependencies are baked from the lockfile.** `make lock` must run
  before `make sbx` after any `pyproject.toml` edit; `uv sync --locked` fails the
  image build when the lockfile is stale. There is no runtime dependency
  installation layer.
- **`/home/agent/.local/bin` precedes `/usr/local/bin` on `PATH`**, so anything the
  agent installs would shadow a baked binary. This is another reason runtime
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

The image's build-time smoke test already runs every one of these as `agent`, so a
PATH, permission, or architecture regression fails the build instead of first use.
The same checks are available as `make sbx-accept`; it runs inside the sandbox and
delegates automatically when invoked from the host.

### Quality gate

`make verify` runs the pre-commit checks: stale-image guard, lint, typecheck, and
tests. Inside the sandbox it runs directly. On the host it delegates into the
sandbox, so the checks always use the baked toolchain and never run natively on
macOS. The guard compares the current content hash with
`/etc/opencode/sandbox.hash` and fails fast when the working tree no longer
matches the running image.

`make format` is the mutating counterpart (`ruff format` + `taplo fmt`). It also
delegates into the sandbox when invoked from the host.

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
uv-lock-digest` print the currently pinned digests for review.

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

Configure the settings:

```bash
# The hash-tagged path does not need a persistent kit shortcut.
# Legacy manual kit path only:
make sbx-apply
make sbx-settings
```

v3 kits need `sbx` 0.50.0 or later for persistent volumes (`sbx version`).

## Run

Mount the directory that contains all your git worktrees.

```bash
# First build (can take a few minutes):
make lock
make sbx-new

# Run/re-attach; rebuilds only when the content hash changes:
make sbx
```

The first build resolves `uv.lock` on the host, then `build-sandbox-image.sh`
builds `opencode-sandbox:<hash12>` with BuildKit and loads it via
`sbx template load`. If the host BuildKit driver rejects the OCI exporter, the
script falls back to `--load` plus `docker image save`.

If you need to change the configuration for everyone, edit the kit files in
`development/sandbox/opencode-strict/`; the content hash changes and `make sbx`
builds a new image and sandbox.

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
sbx policy allow network --sandbox "opencode-wt-<hash12>" <host>:443
```

Remove a network capability on an existing sandbox:

```bash
sbx policy rm network --sandbox "opencode-wt-<hash12>" --resource <host>:443
```

Block network capability on an existing sandbox:

```bash
sbx policy deny network --sandbox "opencode-wt-<hash12>" <host>
```

Remove sandbox:

```bash
make sbx-rm                              # flush the WAL, then: sbx rm opencode-wt-<hash12>
make sbx-rm SBX_RM_FLAGS=--force         # unattended; no confirmation prompt
make sbx-rm SKIP_FLUSH=1                 # skip the WAL flush (may lose recent sessions)
```

Removing the sandbox keeps the OpenCode state volume. The Makefile flushes the
WAL first; a direct `sbx rm` does not. To start with fresh storage, use a new
sandbox name (`make sbx-new SANDBOX_NAME=opencode-wt-fresh`); to wipe
everything, run `sbx reset`.

Ensure your sandbox is running opencode v2.x.x:

```bash
make sbx-version       # or: sbx exec "opencode-wt-<hash12>" -- opencode --version
```

`sbx exec` needs `--` before a command that has flags, so `--version` reaches opencode instead of sbx.
