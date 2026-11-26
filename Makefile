# Docker Sandboxes (sbx) helpers.
#
# Run from any worktree or subdirectory. Recipes always cd to the directory that
# contains all the worktrees before calling sbx, so the sandbox mounts the whole
# worktrees tree.
#
# Quick start:
#   make sbx-new   # install kit, set shortcut, remove sandbox, rebuild
#   make sbx       # run/re-attach to the sandbox

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

# Versioned git hooks (branch-name validation).
HOOKS_PATH ?= .githooks

.DEFAULT_GOAL := help
.PHONY: help hooks hooks-off hooks-test check-root verify verify-raw lint typecheck test sbx-accept sbx-accept-raw sbx sbx-new sbx-apply sbx-settings sbx-rm sbx-where sbx-ls sbx-version

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
	  '  make sbx          Run/re-attach to the sandbox' \
	  '  make sbx-new      Apply kit, set shortcut, remove sandbox, rebuild' \
	  '  make sbx-apply    Copy kit files to ~/.config/sbx-kits/$(KIT_NAME)' \
	  '  make sbx-settings Set kit.shortcuts.$(KIT_NAME)' \
	  '  make sbx-rm       Stop and remove the sandbox VM (host files kept)' \
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

sbx-rm: check-root
	@if ! $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	  echo "sandbox $(SANDBOX_NAME) does not exist; nothing to remove"; \
	  exit 0; \
	fi; \
	$(SBX) stop "$(SANDBOX_NAME)" >/dev/null 2>&1 || true; \
	$(SBX) rm "$(SANDBOX_NAME)"

sbx-new: sbx-settings sbx-rm
	@echo "building sandbox $(SANDBOX_NAME) from $(WORKTREES_ROOT)"
	@cd "$(WORKTREES_ROOT)" && SBX_KIT_BUILDER=sandbox $(SBX) run --name "$(SANDBOX_NAME)" $(KIT_NAME) .

sbx: check-root
	@cd "$(WORKTREES_ROOT)" && $(SBX) run --name "$(SANDBOX_NAME)" $(KIT_NAME) .

sbx-ls:
	@$(SBX) ls

sbx-version: check-root
	@$(SBX) exec "$(SANDBOX_NAME)" -- $(KIT_NAME) --version
