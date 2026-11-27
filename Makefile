# Docker Sandboxes (sbx) helpers.
#
# Run from any worktree or subdirectory. Recipes always cd to the directory that
# contains all the worktrees before calling sbx, so the sandbox mounts the whole
# worktrees tree.
#
# Quick start:
#   make lock      # host-only: resolve pyproject.toml into uv.lock in a container
#   make sbx       # build/load the hash-tagged image, then run/re-attach
#   make sbx-new   # flush the WAL, remove the sandbox, rebuild the image, run

SHELL       := /bin/bash
SBX         ?= sbx
KIT_NAME    ?= opencode
REPO_ROOT   := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
KIT_DIR     := $(REPO_ROOT)/development/sandbox/opencode-strict
APPLY_RULES := $(KIT_DIR)/apply-rules.sh
BUILD_IMAGE := $(REPO_ROOT)/development/sandbox/build-sandbox-image.sh
IMAGE_HASH  := $(REPO_ROOT)/development/sandbox/image-hash.sh
CHECK_POLICY := $(REPO_ROOT)/development/sandbox/check-sbx-policy.sh
PRUNE_SCRIPT := $(REPO_ROOT)/development/sandbox/prune-sbx.sh
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

# Content-addressed image and sandbox names. The hash covers the Dockerfile,
# kit policy, pyproject.toml, uv.lock, and .dockerignore.
SANDBOX_HASH := $(shell "$(IMAGE_HASH)" "$(REPO_ROOT)" 2>/dev/null)
HASH12       := $(shell printf '%s' "$(SANDBOX_HASH)" | cut -c1-12)
SANDBOX_NAME := opencode-wt-$(HASH12)
IMAGE_TAG    := opencode-sandbox:$(HASH12)

# The uv image is pinned once in the Dockerfile; reuse it for make lock.
UV_VERSION ?= $(shell sed -n 's/^ARG UV_VERSION=//p' "$(KIT_DIR)/opencode.dockerfile")
UV_DIGEST  ?= $(shell sed -n 's/^ARG UV_DIGEST=//p' "$(KIT_DIR)/opencode.dockerfile")
UV_IMAGE   := ghcr.io/astral-sh/uv:$(UV_VERSION)@sha256:$(UV_DIGEST)

# The scratch uv image is fine for copying /uv into the final image, but
# `uv lock` needs a Python interpreter. Use the Python-enabled variant for lock.
UV_LOCK_TAG    ?= $(UV_VERSION)-python3.14-trixie
UV_LOCK_DIGEST ?= 65557d27bba9d043ce89a7f1ef82bfdaffb1ce45f5e81fce1efd085050673154
UV_LOCK_IMAGE  := ghcr.io/astral-sh/uv:$(UV_LOCK_TAG)@sha256:$(UV_LOCK_DIGEST)

# Persistent volumes need sbx 0.50+; older versions drop the volume on rm.
SBX_MIN_VERSION ?= 0.50.0
SBX_RM_FLAGS    ?=
SKIP_FLUSH      ?= 0
PRUNE           ?= 0
PRUNE_SANDBOXES ?= 0
SBX_RUNTIME     ?= template
CACHE_DIR       ?= $(if $(XDG_CACHE_HOME),$(XDG_CACHE_HOME),$(HOME)/.cache)
STATE_FLUSH_SCRIPT := $(REPO_ROOT)/development/sandbox/opencode-state-flush.sh
VENV_PYTHON      ?= /opt/venv/bin/python

# Versioned git hooks (branch-name validation).
HOOKS_PATH ?= .githooks

.DEFAULT_GOAL := help
.PHONY: help hooks hooks-off hooks-test check-root check-docker check-uv-image check-uv-lock-image uv-digest uv-lock-digest verify verify-raw stale-guard lint format format-raw typecheck test lock sbx-accept sbx-accept-raw sbx sbx-new sbx-image sbx-ensure sbx-kit sbx-apply sbx-settings sbx-check-policy sbx-prune sbx-flush sbx-rm sbx-check-version sbx-where sbx-ls sbx-version

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
	  '  make verify       Run stale check, lint, typecheck and tests (sandbox-aware)' \
	  '  make verify-raw   Run the checks without sandbox delegation' \
	  '  make format       Format Python and TOML (sandbox-aware, mutating)' \
	  '  make lint         Run static checks' \
	  '  make typecheck    Run pyrefly' \
	  '  make test         Run pytest from /opt/venv' \
	  '  make sbx-accept   Run the baked-toolchain acceptance checks' \
	  '' \
	  'Dependency lock:' \
	  '' \
	  '  make lock         Run uv lock in a throwaway container (host only)' \
	  '  make uv-digest    Print the pinned uv build image index digest' \
	  '  make uv-lock-digest  Print the pinned uv lock image index digest' \
	  '' \
	  'Docker Sandboxes (sbx) targets:' \
	  '' \
	  '  make sbx          Build/load the hash image; run/re-attach the sandbox' \
	  '  make sbx-new      Flush the WAL, remove the sandbox, rebuild and run' \
	  '  make sbx-ensure   Build the hash-tagged image only if it is missing' \
	  '  make sbx-image    Build and load opencode-sandbox:<hash12>' \
	  '  make sbx-check-policy  Assert the strict three-domain allow-list' \
	  '  make sbx-prune    Report stale hash images and stopped sandboxes' \
	  '  make sbx-kit      Fallback: run directly from the hash-keyed kit descriptor' \
	  '  make sbx-apply    Legacy: copy kit files to ~/.config/sbx-kits/$(KIT_NAME)' \
	  '  make sbx-settings Legacy: set the kit shortcut' \
	  '  make sbx-flush    Checkpoint the OpenCode WAL and flush the state volume' \
	  '  make sbx-rm       Remove the sandbox VM (volume and host files kept)' \
	  '  make sbx-where    Show resolved paths and the content hash' \
	  '  make sbx-ls       List sandboxes' \
	  '  make sbx-version  Print opencode version inside the sandbox' \
	  '' \
	  'worktrees root: $(if $(WORKTREES_ROOT),$(WORKTREES_ROOT),<unresolved>)' \
	  'sandbox name:   $(if $(SANDBOX_NAME),$(SANDBOX_NAME),<unresolved>)' \
	  'image tag:      $(if $(HASH12),$(IMAGE_TAG),<unresolved — run make lock>)' \
	  'sbx runtime:    $(SBX_RUNTIME) (set SBX_RUNTIME=kit to use the kit descriptor)'

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
	@test -n "$(SANDBOX_HASH)" || { echo "error: cannot compute the sandbox hash; uv.lock is missing — run 'make lock' first" >&2; exit 1; }
	@test -n "$(SANDBOX_NAME)" || { echo "error: cannot resolve the sandbox name; set SANDBOX_NAME=..." >&2; exit 1; }

check-docker:
	@command -v docker >/dev/null 2>&1 || { echo "error: 'docker' not found on PATH" >&2; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "error: Docker daemon unavailable; run 'make lock' on the host" >&2; exit 1; }

check-uv-image:
	@printf '%s' "$(UV_VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "error: cannot parse UV_VERSION from $(KIT_DIR)/opencode.dockerfile" >&2; exit 1; }
	@printf '%s' "$(UV_DIGEST)" | grep -Eq '^[0-9a-f]{64}$$' || { echo "error: UV_DIGEST must be the bare 64-character sha256 digest" >&2; exit 1; }

check-uv-lock-image:
	@printf '%s' "$(UV_LOCK_TAG)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-python3\.14-trixie$$' || { echo "error: unexpected UV_LOCK_TAG: $(UV_LOCK_TAG)" >&2; exit 1; }
	@printf '%s' "$(UV_LOCK_DIGEST)" | grep -Eq '^[0-9a-f]{64}$$' || { echo "error: UV_LOCK_DIGEST must be the bare 64-character sha256 digest" >&2; exit 1; }

uv-digest:
	@docker buildx imagetools inspect "ghcr.io/astral-sh/uv:$(UV_VERSION)" --format '{{json .Manifest.Digest}}' | tr -d '"'

uv-lock-digest:
	@docker buildx imagetools inspect "ghcr.io/astral-sh/uv:$(UV_LOCK_TAG)" --format '{{json .Manifest.Digest}}' | tr -d '"'

# Quality gate. Inside the sandbox this runs directly; on the host it delegates
# into the sandbox so the toolchain lives in one place. A stopped sandbox is
# started on demand; a sandbox that does not exist fails closed.
verify:
	@if [ -f /etc/opencode/sandbox ]; then \
	  $(MAKE) --no-print-directory verify-raw; \
	elif command -v "$(SBX)" >/dev/null 2>&1; then \
	  $(MAKE) --no-print-directory check-root || exit 1; \
	  if ! $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	    echo "error: no sandbox for the current hash ($(SANDBOX_NAME)); the image is stale or missing — run 'make sbx'" >&2; \
	    exit 1; \
	  fi; \
	  $(SBX) exec "$(SANDBOX_NAME)" -- bash -lc 'cd "$(CURDIR)" && make --no-print-directory verify'; \
	else \
	  echo "error: not inside the sandbox and '$(SBX)' is not on PATH" >&2; \
	  echo "       start the sandbox with 'make sbx' and retry" >&2; \
	  exit 1; \
	fi

verify-raw: stale-guard lint typecheck test

stale-guard:
	@expected="$(SANDBOX_HASH)"; \
	if [ -f /etc/opencode/sandbox.hash ]; then actual="$$(cat /etc/opencode/sandbox.hash)"; else actual=""; fi; \
	if [ -z "$$expected" ]; then \
	  echo "error: cannot compute the sandbox hash; uv.lock is missing — run 'make lock'" >&2; \
	  exit 1; \
	fi; \
	if [ "$$actual" != "$$expected" ]; then \
	  echo "error: sandbox image is stale (expected $$expected, image $$actual)" >&2; \
	  echo "       run 'make sbx' on the host to build and attach the hash-matched sandbox" >&2; \
	  exit 1; \
	fi

lint:
	ruff check .
	ruff format --check .
	yamllint . .yamllint .yamlfmt
	yamlfmt -lint . .yamlfmt
	check-jsonschema --builtin-schema vendor.github-workflows .github/workflows/branch-name.yml
	check-jsonschema --builtin-schema custom.github-workflows-require-timeout .github/workflows/branch-name.yml
	check-jsonschema --builtin-schema vendor.github-issue-forms .github/ISSUE_TEMPLATE/work-item.yml
	taplo fmt --check pyproject.toml
	actionlint
	hadolint --failure-threshold warning development/sandbox/opencode-strict/opencode.dockerfile
	shellcheck $$(git ls-files '*.sh') .githooks/pre-commit .githooks/pre-push .githooks/lib/branch-name.sh
	betterleaks dir .

# Mutating formatter. Delegates into the sandbox because ruff and taplo are not
# assumed to exist on the host.
format:
	@if [ -f /etc/opencode/sandbox ]; then \
	  $(MAKE) --no-print-directory format-raw; \
	elif command -v "$(SBX)" >/dev/null 2>&1; then \
	  $(MAKE) --no-print-directory check-root || exit 1; \
	  if ! $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	    echo "error: no sandbox for the current hash ($(SANDBOX_NAME)); the image is stale or missing — run 'make sbx'" >&2; \
	    exit 1; \
	  fi; \
	  $(SBX) exec "$(SANDBOX_NAME)" -- bash -lc 'cd "$(CURDIR)" && make --no-print-directory format-raw'; \
	else \
	  echo "error: not inside the sandbox and '$(SBX)' is not on PATH" >&2; \
	  exit 1; \
	fi

format-raw:
	ruff format .
	taplo fmt pyproject.toml

typecheck:
	@if [ -f pyproject.toml ]; then \
	  if [ -x "$(VENV_PYTHON)" ]; then \
	    pyrefly check --python-interpreter-path "$(VENV_PYTHON)"; \
	  else \
	    pyrefly check; \
	  fi; \
	else \
	  echo "pyrefly: no pyproject.toml"; \
	fi

test:
	@if [ -x "$(VENV_PYTHON)" ]; then \
	  "$(VENV_PYTHON)" -m pytest; \
	else \
	  echo "error: $(VENV_PYTHON) is missing; run 'make sbx-new' to build the locked environment" >&2; \
	  exit 1; \
	fi

# Lock resolution never runs on the host. The Python-enabled uv image supplies
# the interpreter that `uv lock` needs; the tmpfs keeps /tmp writable.
lock: check-docker check-uv-lock-image
	@test -f pyproject.toml || { echo "error: pyproject.toml is missing" >&2; exit 1; }
	docker run --rm \
	  --user "$$(id -u):$$(id -g)" \
	  --cap-drop ALL \
	  --security-opt no-new-privileges \
	  --tmpfs /tmp:rw,noexec,nosuid,size=256m \
	  -e HOME=/tmp \
	  -e UV_CACHE_DIR=/tmp/uv-cache \
	  -v "$(REPO_ROOT)":/workspace \
	  -w /workspace \
	  --entrypoint /usr/local/bin/uv \
	  "$(UV_LOCK_IMAGE)" \
	  lock --no-build --no-python-downloads

# Baked-toolchain acceptance. Same sandbox-aware delegation as verify.
sbx-accept:
	@if [ -f /etc/opencode/sandbox ]; then \
	  $(MAKE) --no-print-directory sbx-accept-raw; \
	elif command -v "$(SBX)" >/dev/null 2>&1; then \
	  $(MAKE) --no-print-directory check-root || exit 1; \
	  if ! $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	    echo "error: no sandbox for the current hash ($(SANDBOX_NAME)); the image is stale or missing — run 'make sbx'" >&2; \
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
	echo "== locked environment =="; \
	"$(VENV_PYTHON)" --version; \
	"$(VENV_PYTHON)" -c "import duckdb; assert duckdb.sql('SELECT 1').fetchone() == (1,)"; \
	"$(VENV_PYTHON)" -m pytest --version; \
	echo "== network =="; \
	for url in https://pypi.org/simple/ https://github.com https://registry.npmjs.org/; do \
	  code="$$(curl -sS -o /dev/null -w '%{http_code}' "$$url" || true)"; \
	  if [ "$$code" != "403" ]; then echo "network: $$url expected 403, got $$code" >&2; exit 1; fi; \
	done; \
	echo "sbx-accept: ok"

sbx-where:
	@echo "worktrees root: $(if $(WORKTREES_ROOT),$(WORKTREES_ROOT),<unresolved>)"
	@echo "sandbox name:   $(if $(SANDBOX_NAME),$(SANDBOX_NAME),<unresolved>)"
	@echo "image tag:      $(if $(HASH12),$(IMAGE_TAG),<unresolved — run make lock>)"
	@echo "sandbox hash:   $(if $(SANDBOX_HASH),$(SANDBOX_HASH),<unresolved — run make lock>)"
	@echo "kit dir:        $(KIT_DIR)"

# Legacy kit staging. The hash-tagged image path above does not use this.
sbx-apply:
	@KIT_TARGET_DIR="$(KIT_SHORTCUT_DIR)" "$(APPLY_RULES)"

sbx-settings: sbx-apply
	@$(SBX) settings set kit.shortcuts.$(KIT_NAME) "$(KIT_SHORTCUT_DIR)"

sbx-check-version:
	@command -v "$(SBX)" >/dev/null 2>&1 || { echo "error: '$(SBX)' not found on PATH" >&2; exit 1; }
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

sbx-image: check-root check-uv-image
	@test -f uv.lock || { echo "error: uv.lock is missing — run 'make lock' first" >&2; exit 1; }
	@"$(BUILD_IMAGE)" "$(REPO_ROOT)" "$(SANDBOX_HASH)" "$(HASH12)"

sbx-ensure: check-root
	@if ! $(SBX) template inspect "$(IMAGE_TAG)" >/dev/null 2>&1; then \
	  echo "sandbox template $(IMAGE_TAG) is missing; building"; \
	  $(MAKE) --no-print-directory sbx-image; \
	fi

sbx-new: sbx-check-version sbx-rm
	@if [ "$(SBX_RUNTIME)" = "kit" ]; then \
	  $(MAKE) --no-print-directory sbx-kit; \
	else \
	  $(MAKE) --no-print-directory sbx-image; \
	  echo "starting sandbox $(SANDBOX_NAME) from $(IMAGE_TAG)"; \
	  cd "$(WORKTREES_ROOT)" && $(SBX) run --pull never --template "$(IMAGE_TAG)" --name "$(SANDBOX_NAME)" opencode "$(WORKTREES_ROOT)"; \
	fi

sbx: check-root
	@if [ "$(SBX_RUNTIME)" = "kit" ]; then \
	  $(MAKE) --no-print-directory sbx-kit; \
	else \
	  $(MAKE) --no-print-directory sbx-ensure; \
	  cd "$(WORKTREES_ROOT)" && $(SBX) run --pull never --template "$(IMAGE_TAG)" --name "$(SANDBOX_NAME)" opencode "$(WORKTREES_ROOT)"; \
	fi

# Fallback path if a -t template does not carry the kit's runtime capabilities.
# It stages a hash-keyed kit and passes the absolute worktrees root, never ".".
sbx-kit: check-root
	@stage="$(CACHE_DIR)/opencode-sbx/kits/$(HASH12)"; \
	mkdir -p "$$stage"; \
	cp "$(KIT_DIR)/opencode.yaml" "$(KIT_DIR)/opencode.dockerfile" "$(KIT_DIR)/opencode.json" \
	  "$(REPO_ROOT)/pyproject.toml" "$(REPO_ROOT)/uv.lock" "$(REPO_ROOT)/.dockerignore" "$$stage/"; \
	printf '%s\n' "$(SANDBOX_HASH)" > "$$stage/sandbox.hash"; \
	cd "$(WORKTREES_ROOT)" && SBX_KIT_BUILDER=sandbox \
	  $(SBX) run --name "$(SANDBOX_NAME)" "$$stage" "$(WORKTREES_ROOT)"

sbx-check-policy: check-root
	@if ! $(SBX) ls -q 2>/dev/null | grep -qx "$(SANDBOX_NAME)"; then \
	  echo "error: sandbox $(SANDBOX_NAME) is not running; run 'make sbx' first" >&2; \
	  exit 1; \
	fi
	@"$(CHECK_POLICY)" "$(SANDBOX_NAME)"

sbx-prune: check-root
	@"$(PRUNE_SCRIPT)" "$(IMAGE_TAG)" "$(PRUNE)" "$(PRUNE_SANDBOXES)"

sbx-ls:
	@$(SBX) ls

sbx-version: check-root
	@$(SBX) exec "$(SANDBOX_NAME)" -- $(KIT_NAME) --version
