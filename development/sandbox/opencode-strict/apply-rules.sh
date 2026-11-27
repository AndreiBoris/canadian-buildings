#!/usr/bin/env bash
#
# Install the opencode-strict sandbox kit into the local sbx kit directory.
#
# Copies config files (located next to this script) plus the locked Python
# project files into ~/.config/sbx-kits/opencode/ on macOS.
#
# This is the main kit staging path for `make sbx` and `make sbx-new`.
#
# Usage: ./apply-rules.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TARGET_DIR="${KIT_TARGET_DIR:-${HOME}/.config/sbx-kits/opencode}"

KIT_FILES=(
  "opencode.dockerfile"
  "opencode.yaml"
  "opencode.json"
)

PROJECT_FILES=(
  "pyproject.toml"
  "uv.lock"
  ".dockerignore"
)

for file in "${KIT_FILES[@]}"; do
  if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
    echo "error: missing ${SCRIPT_DIR}/${file}" >&2
    exit 1
  fi
done

for file in "${PROJECT_FILES[@]}"; do
  if [[ ! -f "${PROJECT_ROOT}/${file}" ]]; then
    echo "error: missing ${PROJECT_ROOT}/${file}; run 'make lock' first" >&2
    exit 1
  fi
done

mkdir -p "${TARGET_DIR}"

for file in "${KIT_FILES[@]}"; do
  cp -f "${SCRIPT_DIR}/${file}" "${TARGET_DIR}/${file}"
  echo "copied ${file} -> ${TARGET_DIR}/"
done

for file in "${PROJECT_FILES[@]}"; do
  cp -f "${PROJECT_ROOT}/${file}" "${TARGET_DIR}/${file}"
  echo "copied ${file} -> ${TARGET_DIR}/"
done

sandbox_hash="$("${PROJECT_ROOT}/development/sandbox/image-hash.sh" "${PROJECT_ROOT}")"
printf '%s\n' "${sandbox_hash}" > "${TARGET_DIR}/sandbox.hash"
echo "wrote sandbox.hash -> ${TARGET_DIR}/"

echo "opencode kit installed at ${TARGET_DIR}"
