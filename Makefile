# Docker Sandboxes (sbx) helpers.
#
# Run from any worktree or subdirectory. Recipes always cd to the directory that
# contains all the worktrees before calling sbx, so the sandbox mounts the whole
# worktrees tree.
#
# Quick start:
#   make sbx       # run/re-attach; rebuilds when kit sources change
#   make sbx-new   # install kit, set shortcut, remove sandbox, rebuild

SHELL       := /bin/bash
SBX         ?= sbx
KIT_NAME    ?= opencode
KIT_DIR     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))development/sandbox/opencode-strict)
APPLY_RULES := $(KIT_DIR)/apply-rules.sh
KIT_SHORTCUT_DIR ?= $(HOME)/.config/sbx-kits/$(KIT_NAME)

# Resolve the directory that contains all worktrees from git's common dir
# (e.g. <root>/main/.git -> <root>). Override with WORKTREES_ROOT=... when the
# primary repo does not live inside the worktrees directory.
GIT_COMMON_DIR := $(shell git -C "$(KIT_DIR)" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
ifeq ($(strip $(GIT_COMMON_DIR)),)
WORKTREES_ROOT ?=
else
WORKTREES_ROOT ?= $(abspath $(GIT_COMMON_DIR)/../..)
endif

# Sandbox name. sbx defaults to <agent>-<workspace dir>, but we always pass it
# explicitly. Override with SANDBOX_NAME=... when reusing a sandbox built under
# another name.
SANDBOX_NAME ?= $(if $(WORKTREES_ROOT),$(KIT_NAME)-$(notdir $(WORKTREES_ROOT)),)

# Persistent volumes need sbx 0.50+; older versions drop the volume on rm.
SBX_MIN_VERSION ?= 0.50.0
SBX_RM_FLAGS    ?=
SKIP_FLUSH      ?= 0
CACHE_DIR       ?= $(if $(XDG_CACHE_HOME),$(XDG_CACHE_HOME),$(HOME)/.cache)
KIT_STAMP       := $(CACHE_DIR)/opencode-sbx/$(SANDBOX_NAME).kit.hash
STATE_FLUSH_SCRIPT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))development/sandbox/opencode-state-flush.sh)

# Hash only what affects the kit image/config, not unrelated Makefile edits.
# Paths are relative to the kit dir so switching worktrees does not force a
# rebuild when the kit content is identical. Expanded inside recipes so
# `make help` and `make verify` do not shell out.
define compute_kit_hash
( cd "$(KIT_DIR)" && \
  printf 'sandbox=%s\nkit=%s\nshortcut=%s\n' "$(SANDBOX_NAME)" "$(KIT_NAME)" "$(KIT_SHORTCUT_DIR)"; \
  LC_ALL=C find . -type f ! -name '.DS_Store' | LC_ALL=C sort | \
  while IFS= read -r f; do printf 'file=%s\n' "$$f"; cat "$$f"; done ) | \
  git hash-object --stdin
endef

# Versioned git hooks (branch-name validation).
HOOKS_PATH ?= .githooks

.DEFAULT_GOAL := help
.PHONY: help hooks hooks-off hooks-test check-root verify verify-raw lint typecheck test sbx-accept sbx-accept-raw sbx sbx-new sbx-apply sbx-settings sbx-flush sbx-rm sbx-check-version sbx-where sbx-ls sbx-version

help:
	@printf '%s\n' \
	  'Git hooks:' \
	  '' \
	  '  make hooks        Install branch-name hooks (all worktrees)' \
	  '  make hooks-off    Disable the branch-name hooks' \
	  '  make hooks-test   Run the branch-name rule tests' \
	  '' \
	  'Quality gate:' \
	  '' \
	  '  make verify       Run lint, typecheck and tests (sandbox-aware)' \
	  '  make verify-raw   Run the checks without sandbox delegation' \
	  '  make lint         Run static checks' \
	  '  make typecheck    Run pyrefly when Python files exist' \
	  '  make test         Run pytest when pyproject.toml exists' \
	  '  make sbx-accept   Run the baked-toolchain acceptance checks' \
	  '' \
	  'Docker Sandboxes (sbx) targets:' \
	  '' \
	  '  make sbx          Run/re-attach; rebuild when kit sources change' \
	  '  make sbx-new      Apply kit, set shortcut, remove sandbox, rebuild' \
	  '  make sbx-apply    Copy kit files to ~/.config/sbx-kits/$(KIT_NAME)' \
	  '  make sbx-settings Set kit.shortcuts.$(KIT_NAME)' \
	  '  make sbx-flush    Checkpoint the OpenCode WAL and flush the state volume' \
	  '  make sbx-rm       Remove the sandbox VM (volume and host files kept)' \
	  '  make sbx-where    Show resolved worktrees root and sandbox name' \
	  '  make sbx-ls       List sandboxes' \
	  '  make sbx-version  Print opencode version inside the sandbox' \
	  '' \
	  'worktrees root: $(if $(WORKTREES_ROOT),$(WORKTREES_ROOT),<unresolved>)' \
	  'sandbox name:   $(if $(SANDBOX_NAME),$(SANDBOX_NAME),<unresolved>)'

# Install the versioned hooks once per clone. core.hooksPath lives in the shared
# .git/config, so this covers every worktree; the relative path resolves to each
# worktree's own checked-out copy of .githooks.
hooks:
	@chmod +x "$(HOOKS_PATH)"/pre-commit "$(HOOKS_PATH)"/pre-push
	@git config core.hooksPath "$(HOOKS_PATH)"
	@echo "core.hooksPath -> $(HOOKS_PATH) (applies to all worktrees)"

hooks-off:
	@git config --unset core.hooksPath 2>/dev/null || true
	@echo "core.hooksPath unset; branch-name hooks disabled"

hooks-test:
	@./development/githooks/test-branch-names.sh

check-root:
	@command -v "$(SBX)" >/dev/null 2>&1 || { echo "error: '$(SBX)' not found on PATH" >&2; exit 1; }
	@test -n "$(WORKTREES_ROOT)" || { echo "error: cannot resolve the worktrees root; set WORKTREES_ROOT=..." >&2; exit 1; }
	@test -n "$(SANDBOX_NAME)" || { echo "error: cannot resolve the sandbox name; set SANDBOX_NAME=..." >&2; exit 1; }

# Quality gate. Inside the sandbox this runs directly; on the host it delegates
# into the sandbox so the toolchain lives in one place. A stopped sandbox is
# started on demand; a sandbox that does not exist fails closed.
verify:
	@if [ -f /etc/opencode/sandbox ]; then \
	  $(MAKE) --no-print-directory verify-raw; \
	elif command -v "$(SBX)" >/dev/null 2>&1; then \
	  $(MAKE) --no-print-directory check-root || exit 1; \
	  if ! $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	    echo "error: sandbox $(SANDBOX_NAME) does not exist; run 'make sbx-new' and retry" >&2; \
	    exit 1; \
	  fi; \
	  $(SBX) exec "$(SANDBOX_NAME)" -- bash -lc 'cd "$(CURDIR)" && make --no-print-directory verify'; \
	else \
	  echo "error: not inside the sandbox and '$(SBX)' is not on PATH" >&2; \
	  echo "       start the sandbox with 'make sbx' and retry" >&2; \
	  exit 1; \
	fi

verify-raw: lint typecheck test

lint:
	ruff check .
	ruff format --check .
	yamllint . .yamllint .yamlfmt
	yamlfmt -lint . .yamlfmt
	check-jsonschema --builtin-schema vendor.github-workflows .github/workflows/branch-name.yml
	check-jsonschema --builtin-schema custom.github-workflows-require-timeout .github/workflows/branch-name.yml
	check-jsonschema --builtin-schema vendor.github-issue-forms .github/ISSUE_TEMPLATE/work-item.yml
	taplo fmt --check .
	actionlint
	hadolint --failure-threshold warning development/sandbox/opencode-strict/opencode.dockerfile
	shellcheck $$(git ls-files '*.sh') .githooks/pre-commit .githooks/pre-push .githooks/lib/branch-name.sh
	betterleaks dir .

typecheck:
	@files="$$(git ls-files '*.py')"; \
	if [ -n "$$files" ]; then \
	  pyrefly check $$files; \
	else \
	  echo "pyrefly: no Python files"; \
	fi

test:
	@if [ -f pyproject.toml ]; then \
	  uv run pytest; \
	else \
	  echo "pytest: no pyproject.toml yet"; \
	fi

# Baked-toolchain acceptance. Same sandbox-aware delegation as verify.
sbx-accept:
	@if [ -f /etc/opencode/sandbox ]; then \
	  $(MAKE) --no-print-directory sbx-accept-raw; \
	elif command -v "$(SBX)" >/dev/null 2>&1; then \
	  $(MAKE) --no-print-directory check-root || exit 1; \
	  if ! $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	    echo "error: sandbox $(SANDBOX_NAME) does not exist; run 'make sbx-new' and retry" >&2; \
	    exit 1; \
	  fi; \
	  $(SBX) exec "$(SANDBOX_NAME)" -- bash -lc 'cd "$(CURDIR)" && make --no-print-directory sbx-accept-raw'; \
	else \
	  echo "error: not inside the sandbox and '$(SBX)' is not on PATH" >&2; \
	  exit 1; \
	fi

sbx-accept-raw:
	@set -euo pipefail; \
	echo "== toolchain =="; \
	uv tool list; \
	ruff --version; \
	pyrefly --version; \
	yamllint --version; \
	check-jsonschema --version; \
	yamlfmt -version; \
	taplo --version; \
	jq --version; \
	yq --version; \
	actionlint -version; \
	hadolint --version; \
	shellcheck --version; \
	betterleaks version; \
	echo "== network =="; \
	for url in https://pypi.org/simple/ https://github.com https://registry.npmjs.org/; do \
	  code="$$(curl -sS -o /dev/null -w '%{http_code}' "$$url" || true)"; \
	  if [ "$$code" != "403" ]; then echo "network: $$url expected 403, got $$code" >&2; exit 1; fi; \
	done; \
	echo "sbx-accept: ok"

sbx-where:
	@echo "worktrees root: $(if $(WORKTREES_ROOT),$(WORKTREES_ROOT),<unresolved>)"
	@echo "sandbox name:   $(if $(SANDBOX_NAME),$(SANDBOX_NAME),<unresolved>)"
	@echo "kit dir:        $(KIT_DIR)"

sbx-apply:
	@"$(APPLY_RULES)"

sbx-settings: sbx-apply
	@$(SBX) settings set kit.shortcuts.$(KIT_NAME) "$(KIT_SHORTCUT_DIR)"

sbx-check-version: check-root
	@v="$$($(SBX) version 2>/dev/null | sed -E -n 's/.*sbx version:?[[:space:]]+v?([0-9][0-9.]*).*/\1/p' | head -n1)"; \
	if [ -z "$$v" ]; then echo "error: cannot determine sbx version" >&2; exit 1; fi; \
	if ! awk -v have="$$v" -v need="$(SBX_MIN_VERSION)" 'BEGIN { \
	  split(have,h,"."); split(need,n,"."); \
	  h[1]+=0; h[2]+=0; h[3]+=0; n[1]+=0; n[2]+=0; n[3]+=0; \
	  exit !((h[1] > n[1]) || (h[1] == n[1] && (h[2] > n[2] || (h[2] == n[2] && h[3] >= n[3])))) \
	}'; then \
	  echo "error: sbx $$v is too old; $(SBX_MIN_VERSION)+ required for persistent volumes" >&2; \
	  exit 1; \
	fi

sbx-flush: check-root
	@if ! $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	  echo "sandbox $(SANDBOX_NAME) does not exist; nothing to flush"; \
	  exit 0; \
	fi; \
	if [ "$(SKIP_FLUSH)" = "1" ]; then \
	  echo "warning: SKIP_FLUSH=1; not flushing $(SANDBOX_NAME); recent work may be lost" >&2; \
	  exit 0; \
	fi; \
	status=""; \
	if command -v jq >/dev/null 2>&1; then \
	  status="$$($(SBX) ls --format json 2>/dev/null | jq -r --arg name "$(SANDBOX_NAME)" '.[] | select(.name == $$name) | .status')" || status=""; \
	fi; \
	if [ -n "$$status" ] && [ "$$status" != "running" ]; then \
	  echo "sandbox $(SANDBOX_NAME) is $$status; skipping flush"; \
	  exit 0; \
	fi; \
	if [ ! -f "$(STATE_FLUSH_SCRIPT)" ]; then \
	  echo "error: flush script $(STATE_FLUSH_SCRIPT) is missing" >&2; \
	  exit 1; \
	fi; \
	if ! $(SBX) exec -u agent "$(SANDBOX_NAME)" -- bash "$(STATE_FLUSH_SCRIPT)"; then \
	  echo "error: could not flush $(SANDBOX_NAME); refusing to remove it" >&2; \
	  echo "       if the sandbox is wedged, re-run with SKIP_FLUSH=1 (may lose recent work)" >&2; \
	  exit 1; \
	fi

sbx-rm: sbx-check-version sbx-flush
	@if $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	  $(SBX) rm $(SBX_RM_FLAGS) "$(SANDBOX_NAME)"; \
	else \
	  echo "sandbox $(SANDBOX_NAME) does not exist; nothing to remove"; \
	fi
	@if $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	  echo "error: sandbox $(SANDBOX_NAME) still exists; aborting" >&2; \
	  exit 1; \
	fi
	@rm -f "$(KIT_STAMP)"

sbx-new: sbx-check-version sbx-settings sbx-rm
	@echo "building sandbox $(SANDBOX_NAME) from $(WORKTREES_ROOT)"
	@[ -d "$(KIT_DIR)" ] || { echo "error: kit dir $(KIT_DIR) is missing" >&2; exit 1; }; \
	hash="$$( $(compute_kit_hash) )"; \
	[ -n "$$hash" ] || { echo "error: cannot compute kit hash" >&2; exit 1; }; \
	mkdir -p "$$(dirname "$(KIT_STAMP)")"; \
	printf '%s\n' "$$hash" > "$(KIT_STAMP)"
	@cd "$(WORKTREES_ROOT)" && SBX_KIT_BUILDER=sandbox $(SBX) run --name "$(SANDBOX_NAME)" $(KIT_NAME) .

sbx: check-root
	@[ -d "$(KIT_DIR)" ] || { echo "error: kit dir $(KIT_DIR) is missing" >&2; exit 1; }; \
	hash="$$( $(compute_kit_hash) )"; \
	[ -n "$$hash" ] || { echo "error: cannot compute kit hash" >&2; exit 1; }; \
	if $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)" \
	   && [ -f "$(KIT_STAMP)" ] && [ "$$(cat "$(KIT_STAMP)")" = "$$hash" ]; then \
	  cd "$(WORKTREES_ROOT)" && $(SBX) run --name "$(SANDBOX_NAME)" $(KIT_NAME) .; \
	else \
	  echo "kit sources changed or sandbox missing; rebuilding $(SANDBOX_NAME)"; \
	  $(MAKE) --no-print-directory sbx-new; \
	fi

sbx-ls:
	@$(SBX) ls

sbx-version: check-root
	@$(SBX) exec "$(SANDBOX_NAME)" -- $(KIT_NAME) --version
