#!/usr/bin/env bash
#
# Build a content-addressed sandbox template and load it into sbx.
#
# Usage: build-sandbox-image.sh REPO_ROOT FULL_HASH HASH12
#
# The build context is a temporary directory so concurrent worktrees never
# share or overwrite kit files. The image is tagged opencode-sandbox:<hash12>
# and imported with `sbx template load`.
set -euo pipefail

repo_root="${1:?usage: build-sandbox-image.sh REPO_ROOT FULL_HASH HASH12}"
full_hash="${2:?usage: build-sandbox-image.sh REPO_ROOT FULL_HASH HASH12}"
hash12="${3:?usage: build-sandbox-image.sh REPO_ROOT FULL_HASH HASH12}"

tag="opencode-sandbox:${hash12}"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/opencode-sandbox.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

files=(
  "development/sandbox/opencode-strict/opencode.dockerfile"
  "development/sandbox/opencode-strict/opencode.yaml"
  "development/sandbox/opencode-strict/opencode.json"
  "pyproject.toml"
  "uv.lock"
  ".dockerignore"
)

for file in "${files[@]}"; do
  if [[ ! -f "${repo_root}/${file}" ]]; then
    echo "error: missing ${file}; run 'make lock' first" >&2
    exit 1
  fi
  cp "${repo_root}/${file}" "${tmp}/$(basename "${file}")"
done

build_args=(
  --file "${tmp}/opencode.dockerfile"
  --tag "${tag}"
  --build-arg "SANDBOX_IMAGE_HASH=${full_hash}"
)

image_tar="${tmp}/image.tar"
if ! docker buildx build "${build_args[@]}" --output "type=oci,dest=${image_tar}" "${tmp}"; then
  echo "warning: OCI exporter unavailable; retrying with --load" >&2
  docker buildx build "${build_args[@]}" --load "${tmp}"
  docker image save --output "${image_tar}" "${tag}"
fi

if ! sbx template load "${image_tar}"; then
  echo "warning: sbx could not load the OCI archive; retrying with --load" >&2
  docker buildx build "${build_args[@]}" --load "${tmp}"
  docker image save --output "${image_tar}" "${tag}"
  sbx template load "${image_tar}"
fi

echo "loaded ${tag}"
