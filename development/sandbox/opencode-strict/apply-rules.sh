#!/usr/bin/env bash
#
# Install the opencode-strict sandbox kit into the local sbx kit directory.
#
# Copies config files (located next to this script) into ~/.config/sbx-kits/opencode/ on macOS.
#
# Usage: ./apply-rules.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}/.config/sbx-kits/opencode"

FILES=(
  "opencode.dockerfile"
  "opencode.yaml"
  "opencode.json"
)

for file in "${FILES[@]}"; do
  if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
    echo "error: missing ${SCRIPT_DIR}/${file}" >&2
    exit 1
  fi
done

mkdir -p "${TARGET_DIR}"

for file in "${FILES[@]}"; do
  cp -f "${SCRIPT_DIR}/${file}" "${TARGET_DIR}/${file}"
  echo "copied ${file} -> ${TARGET_DIR}/"
done

echo "opencode kit installed at ${TARGET_DIR}"
