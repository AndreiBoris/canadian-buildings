# Agent Sandbox using Docker Sandboxes (sbx)

## Main Usage

Once set up, run the sandbox from anywhere in the repo — any worktree or subdirectory:

```bash
make sbx
```

`make sbx` runs `sbx run opencode .` from the directory that contains all the worktrees (the parent of `main`), so the sandbox mounts the whole worktrees tree and can create new worktrees itself. It re-attaches to the existing sandbox if there is one.

### Changing config

Kit changes need a rebuild:

```bash
make sbx-new
```

`make sbx-new` copies the kit files into `~/.config/sbx-kits/opencode`, sets the `kit.shortcuts.opencode` shortcut, removes the sandbox, and rebuilds it with `SBX_KIT_BUILDER=sandbox`.

### Make targets

| Target | What it runs |
| --- | --- |
| `make sbx` | `sbx run --name opencode-worktrees opencode .` |
| `make sbx-new` | `make sbx-apply` → `make sbx-settings` → `make sbx-rm` → `SBX_KIT_BUILDER=sandbox sbx run --name opencode-worktrees opencode .` |
| `make sbx-apply` | `./development/sandbox/opencode-strict/apply-rules.sh` |
| `make sbx-settings` | `sbx settings set kit.shortcuts.opencode "$HOME/.config/sbx-kits/opencode"` |
| `make sbx-rm` | `sbx stop …` + `sbx rm …` (prompts for confirmation) |
| `make sbx-where` | prints the resolved worktrees root and sandbox name |
| `make sbx-ls` | `sbx ls` |
| `make sbx-version` | `sbx exec … -- opencode --version` |

The worktrees root is derived from `git rev-parse --git-common-dir` (two levels up from `main/.git`), so the targets work from any worktree. The sandbox name is always passed explicitly and defaults to `<agent>-<workspace directory>` → `opencode-worktrees`. Override either when needed:

```bash
make sbx WORKTREES_ROOT=/path/to/worktrees
make sbx-new SANDBOX_NAME=my-sandbox
```

If the worktrees root or sandbox name cannot be resolved, the targets stop and ask you to set `WORKTREES_ROOT` or `SANDBOX_NAME`.

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
| jq | 1.8.2 | `ghcr.io/jqlang/jq` | `/usr/local/bin/jq` |
| yq | 4.54.3 | `mikefarah/yq` | `/usr/local/bin/yq` |
| actionlint | 1.7.12 | `rhysd/actionlint` | `/usr/local/bin/actionlint` |
| hadolint | 2.15.1 | `hadolint/hadolint` | `/usr/local/bin/hadolint` |
| shellcheck | 0.11.0 | `koalaman/shellcheck` | `/usr/local/bin/shellcheck` |
| betterleaks | 1.9.0 | `ghcr.io/betterleaks/betterleaks` | `/usr/local/bin/betterleaks` |

The four `uv tool` packages live in `/opt/uv-tools` (`UV_TOOL_DIR`), with their
entry points in `/usr/local/bin` (`UV_TOOL_BIN_DIR`); `uv tool list` reports them.
A test runner is not baked yet — it lands with the first `pyproject.toml`.

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
- **Project dependencies need a build layer.** With no PyPI reachability, the
  project's own dependencies cannot be installed at runtime. Once `pyproject.toml`
  and `uv.lock` exist, add a `COPY pyproject.toml uv.lock` + `uv sync --frozen`
  layer to the Dockerfile before the smoke test.
- **`/home/agent/.local/bin` precedes `/usr/local/bin` on `PATH`**, so anything the
  agent installs would shadow a baked binary. This is another reason runtime
  installs stay disabled.

### Acceptance checks

After `make sbx-new`, inside the sandbox:

```bash
uv tool list              # ruff, pyrefly, yamllint, check-jsonschema
jq --version              # jq-1.8.2
command -v jq             # /usr/local/bin/jq
ruff --version && taplo --version && pyrefly --version
yamllint --version && check-jsonschema --version
actionlint -version && hadolint --version && shellcheck --version
betterleaks version && yq --version
```

The image's build-time smoke test already runs every one of these as `agent`, so a
PATH, permission, or architecture regression fails the build instead of first use.
The same checks are available as `make sbx-accept`; it runs inside the sandbox and
delegates automatically when invoked from the host.

### Pinning the base image and Dockerfile frontend

The base image and the BuildKit frontend are pinned by digest:

```dockerfile
# syntax=docker/dockerfile:1@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
FROM docker/sandbox-templates:opencode@sha256:7feb9784bc882dbe014888becb65c23e7fb1d1b24169a68d33660fe44476a0b4
```

Re-resolve both on the host when bumping:

```bash
for ref in docker/dockerfile:1 docker/sandbox-templates:opencode; do
  digest=$(docker buildx imagetools inspect "$ref" | awk '/^Digest:/ {print $2; exit}')
  printf "%s@%s\n" "$ref" "$digest"
done
```

Use the top-level `Digest:` line (the multi-arch index), not a per-platform
digest. Update the Dockerfile and this document together, then run `make sbx-new`
and the acceptance checks.

### Not done yet

- A test runner is not baked yet; it lands with the first `pyproject.toml`
  (tracked as a separate ticket).

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
make sbx-apply      # copy kit files into ~/.config/sbx-kits/opencode
make sbx-settings   # point kit.shortcuts.opencode at that directory
```

v3 kits need `sbx` 0.45 or later (`sbx --version`).

## Run

Mount the directory that contains all your git worktrees.

```bash
# First build (can take a few minutes):
make sbx-new

# After the sandbox exists, run/re-attach:
make sbx
```

The first build uses `SBX_KIT_BUILDER=sandbox` so the kit builds in a builder sandbox rather than the host Docker engine. This avoids the `OCI exporter is not supported for the docker driver` error.

If you need to change the configurations for everyone (instead of using specific rules for yourself), edit the kit files in `development/sandbox/opencode-strict/`, then run `make sbx-new`.

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
sbx rm <name>                                  # destroy VM state (keeps host files; prompts)
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
make sbx-rm            # or: sbx rm opencode-worktrees
```

Ensure your sandbox is running opencode v2.x.x:

```bash
make sbx-version       # or: sbx exec opencode-worktrees -- opencode --version
```

`sbx exec` needs `--` before a command that has flags, so `--version` reaches opencode instead of sbx.
