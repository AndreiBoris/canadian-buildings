#!/usr/bin/env bash
#
# Fail unless the named sandbox allows exactly the strict three-domain set.
#
# Usage: check-sbx-policy.sh SANDBOX_NAME
set -euo pipefail

sandbox="${1:?usage: check-sbx-policy.sh SANDBOX_NAME}"

if ! output="$(sbx policy ls --sandbox "${sandbox}" --wide 2>&1)"; then
  printf '%s\n' "${output}" >&2
  echo "error: cannot read the policy for sandbox ${sandbox}" >&2
  exit 1
fi

printf '%s\n' "${output}"

expected="$(printf '%s\n' "mcp.exa.ai:443" "opencode.ai:443" "openrouter.ai:443" | sort)"
actual="$(printf '%s\n' "${output}" \
  | grep -oE '([a-z0-9-]+\.)+[a-z]{2,}(:[0-9]+)?' \
  | sed -E 's/^([^:]+)$/\1:443/' \
  | sort -u || true)"

if [[ "${actual}" != "${expected}" ]]; then
  echo "error: sandbox ${sandbox} does not have the exact strict allow-list" >&2
  echo "expected:" >&2
  printf '%s\n' "${expected}" | sed 's/^/  /' >&2
  echo "actual:" >&2
  printf '%s\n' "${actual}" | sed 's/^/  /' >&2
  exit 1
fi

if printf '%s\n' "${output}" | grep -Eq '(^|[[:space:]])[*]([[:space:]]|$)|0\.0\.0\.0/0|::/0'; then
  echo "error: sandbox ${sandbox} has a wildcard egress rule" >&2
  exit 1
fi

echo "policy check: ${sandbox} is strict"
