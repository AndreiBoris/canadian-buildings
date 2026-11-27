#!/usr/bin/env bash
#
# Fail unless the named sandbox uses the strict three-domain allow-list.
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

for host in openrouter.ai opencode.ai mcp.exa.ai; do
  if ! printf '%s\n' "${output}" | grep -q "${host}"; then
    echo "error: sandbox ${sandbox} is missing the ${host} allow rule" >&2
    exit 1
  fi
done

if printf '%s\n' "${output}" | grep -Eq '(^|[[:space:]])\*([[:space:]]|$)'; then
  echo "error: sandbox ${sandbox} has a wildcard egress rule" >&2
  exit 1
fi

echo "policy check: ${sandbox} is strict"
