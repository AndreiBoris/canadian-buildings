#!/usr/bin/env bash
#
# Report sandbox templates and sandboxes, optionally removing unused templates.
#
# Usage: prune-sbx.sh CURRENT_TAG [PRUNE] [REPORT_SANDBOXES]
#
# A template is removed only when its matching opencode-wt-<hash12> sandbox does
# not exist. Running or stopped sandboxes therefore keep their templates.
set -euo pipefail

current_tag="${1:?usage: prune-sbx.sh CURRENT_TAG [PRUNE] [REPORT_SANDBOXES]}"
prune="${2:-0}"
report_sandboxes="${3:-0}"

echo "current image: ${current_tag}"
echo "--- templates ---"
templates="$(sbx template ls 2>&1 || true)"
printf '%s\n' "${templates}"

echo "--- sandboxes ---"
sandboxes="$(sbx ls 2>&1 || true)"
printf '%s\n' "${sandboxes}"

if [[ "${prune}" == "1" ]]; then
  echo "--- stale templates ---"
  tags="$(printf '%s\n' "${templates}" | grep -oE 'opencode-sandbox:[0-9a-f]{12}' | sort -u || true)"
  while IFS= read -r tag; do
    [[ -n "${tag}" ]] || continue
    [[ "${tag}" == "${current_tag}" ]] && continue

    hash="${tag#opencode-sandbox:}"
    name="opencode-wt-${hash}"
    if sbx ls -q 2>/dev/null | grep -qx "${name}"; then
      echo "keeping ${tag} (sandbox ${name} exists)"
    else
      echo "removing ${tag}"
      sbx template rm "${tag}"
    fi
  done <<< "${tags}"
else
  echo "templates are reported only; re-run with PRUNE=1 to remove unused tags"
fi

if [[ "${report_sandboxes}" == "1" ]]; then
  echo "--- hash sandboxes ---"
  printf '%s\n' "${sandboxes}" | grep -E 'opencode-wt-[0-9a-f]{12}' || true
  echo "Remove a stopped sandbox with: make sbx-rm SANDBOX_NAME=opencode-wt-<hash12>"
  echo "The make target preserves the WAL flush before sbx rm."
else
  echo "sandboxes are reported only; re-run with PRUNE_SANDBOXES=1 to list removal commands"
fi
