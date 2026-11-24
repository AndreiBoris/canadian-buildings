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
