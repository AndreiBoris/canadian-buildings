#!/usr/bin/env bash
#
# Compute the content hash that identifies the sandbox content and drives
# rebuild and stale-image checks.
#
# Usage: image-hash.sh [REPO_ROOT]
#
# The hash covers every input that changes the built image or its runtime
# policy. Keep the order stable so hosts and sandboxes agree.
set -euo pipefail

repo_root="${1:-$(pwd)}"
cd "${repo_root}"

files=(
  "development/sandbox/opencode-strict/opencode.dockerfile"
  "development/sandbox/opencode-strict/opencode.yaml"
  "development/sandbox/opencode-strict/opencode.json"
  "pyproject.toml"
  "uv.lock"
  ".dockerignore"
)

for file in "${files[@]}"; do
  if [[ ! -f "${file}" ]]; then
    echo "error: missing ${file}; run 'make lock' first" >&2
    exit 1
  fi
done

if command -v sha256sum >/dev/null 2>&1; then
  hash_cmd=(sha256sum)
else
  hash_cmd=(shasum -a 256)
fi

{
  for file in "${files[@]}"; do
    printf 'file=%s\n' "${file}"
    cat "${file}"
    printf '\0'
  done
} | "${hash_cmd[@]}" | awk '{print $1}'
