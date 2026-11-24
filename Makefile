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

.DEFAULT_GOAL := help
.PHONY: help check-root sbx sbx-new sbx-apply sbx-settings sbx-rm sbx-where sbx-ls sbx-version

help:
	@printf '%s\n' \
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

check-root:
	@command -v "$(SBX)" >/dev/null 2>&1 || { echo "error: '$(SBX)' not found on PATH" >&2; exit 1; }
	@test -n "$(WORKTREES_ROOT)" || { echo "error: cannot resolve the worktrees root; set WORKTREES_ROOT=..." >&2; exit 1; }
	@test -n "$(SANDBOX_NAME)" || { echo "error: cannot resolve the sandbox name; set SANDBOX_NAME=..." >&2; exit 1; }

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
