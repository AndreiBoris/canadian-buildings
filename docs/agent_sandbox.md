# Agent Sandbox using Docker Sandboxes (sbx)

## Main Usage

Once setup, just run like so from the parent directory containing the `main` repo:

```bash
sbx run opencode .
```

### Changing config

If you change config, you just need to remove and re-build:

```bash
./development/sandbox/opencode-strict/apply-rules.sh
sbx rm opencode-worktrees
# From the parent directory "worktrees"
SBX_KIT_BUILDER=sandbox sbx run opencode .
```

Note: this assumes your sandbox is named `opencode-worktrees`, which is would be if your directory containing your repo and worktrees is called `worktrees`.

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

Initialize a strict network policy:

```bash
sbx policy init deny-all
```

Save a key to credential storage:

```bash
sbx secret set openrouter         # stores in OS keychain (use spend-capped key)
sbx secret set openrouter --sandbox <name>   # optional per-sandbox override
```

Configure the settings by running:

```bash
./development/sandbox/opencode-strict/apply-rules.sh
sbx settings set kit.shortcuts.opencode "$HOME/.config/sbx-kits/opencode"
```

## Run

To run this, setup your directory such you mount the directory that contains all your git worktrees.

```bash
# Git worktree (allowing autonomous creation: mount parent container dir)
# Run from the parent directory of the main git directory to allow the
# agent in the sandbox to create additional directories for worktrees.
# The first time you're building, use this command (can take a few minutes):
SBX_KIT_BUILDER=sandbox sbx run opencode .
# After the sandbox has been built, you can run it directly like so:
sbx run opencode .
```

If you need to change the configurations for everyone (instead of using specific rules for yourself), remove the sandbox and rerun the build command after changing the settings and ensuring the rules are stored in local settings.

## Configure

```bash
sbx policy ls                                  # view active rules
sbx policy inspect <policy-uuid>               # view current policy configuration
sbx policy allow network openrouter.ai:443     # allow endpoint
sbx policy rm network <domain>:<port>          # prune rule
sbx policy log                                 # inspect blocked requests

sbx                                            # open TUI dashboard
sbx stop <name>                                # suspend microVM
sbx rm <name>                                  # destroy VM state (keeps host files)
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
sbx rm opencode-worktrees
```

Ensure your sandbox is running opencode v2.x.x

```bash
sbx exec opencode-worktrees -- opencode --version
# opencode v2.4.0
```
