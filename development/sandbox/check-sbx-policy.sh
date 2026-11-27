#!/usr/bin/env bash
#
# Fail unless the named sandbox's active network policy allows exactly the
# strict three-domain set and denies everything else by default.
#
# Usage: check-sbx-policy.sh SANDBOX_NAME
set -euo pipefail

sandbox="${1:?usage: check-sbx-policy.sh SANDBOX_NAME}"

if ! output="$(sbx policy ls "${sandbox}" --wide --type network 2>&1)"; then
  printf '%s\n' "${output}" >&2
  echo "error: cannot read the policy for sandbox ${sandbox}" >&2
  exit 1
fi

printf '%s\n' "${output}"

# Parse the table by header offsets. First rows use the DECISION and RESOURCES
# columns. Continuation rows collapse to "-  -  <resource>" and belong to the
# current rule. Wrapped STATUS prose does not match that shape and is ignored.
parsed="$(printf '%s\n' "${output}" | awk '
  BEGIN { decision_col = 0; proto_col = 0; resources_col = 0; current = "" }
  {
    if (decision_col == 0 && index($0, "DECISION") && index($0, "PROTOCOLS") && index($0, "RESOURCES")) {
      decision_col = index($0, "DECISION")
      proto_col = index($0, "PROTOCOLS")
      resources_col = index($0, "RESOURCES")
      next
    }
    if (decision_col == 0) next

    if ($0 ~ /^[[:space:]]+-[[:space:]]+-[[:space:]]+/) {
      resource = $0
      sub(/^[[:space:]]+-[[:space:]]+-[[:space:]]+/, "", resource)
      gsub(/[[:space:]]+$/, "", resource)
      if (resource != "" && resource != "-" && current != "") print current "\t" resource
      next
    }

    decision = substr($0, decision_col, proto_col - decision_col)
    gsub(/^[[:space:]]+/, "", decision)
    gsub(/[[:space:]]+$/, "", decision)
    resource = substr($0, resources_col)
    gsub(/^[[:space:]]+/, "", resource)
    gsub(/[[:space:]]+$/, "", resource)

    if (decision != "" && decision != "-") {
      current = decision
      if (resource != "" && resource != "-") print current "\t" resource
    }
  }
')"

allow_resources="$(printf '%s\n' "${parsed}" \
  | awk -F '\t' '$1 == "allow" { print $2 }' \
  | sed '/^$/d' \
  | sort -u)"
deny_resources="$(printf '%s\n' "${parsed}" \
  | awk -F '\t' '$1 == "deny" { print $2 }' \
  | sed '/^$/d' \
  | sort -u)"

expected="$(printf '%s\n' "mcp.exa.ai:443" "opencode.ai:443" "openrouter.ai:443" | sort)"

if [[ "${allow_resources}" != "${expected}" ]]; then
  echo "error: sandbox ${sandbox} does not have the exact strict allow-list" >&2
  echo "expected allow resources:" >&2
  printf '%s\n' "${expected}" | sed 's/^/  /' >&2
  echo "actual allow resources:" >&2
  printf '%s\n' "${allow_resources:-<none>}" | sed 's/^/  /' >&2
  echo "deny resources:" >&2
  printf '%s\n' "${deny_resources:-<none>}" | sed 's/^/  /' >&2
  exit 1
fi

if ! printf '%s\n' "${deny_resources}" | grep -Fqx '**'; then
  echo "error: sandbox ${sandbox} is missing the ** deny fallback" >&2
  exit 1
fi

if ! printf '%s\n' "${output}" | grep -q 'default-deny-all'; then
  echo "error: sandbox ${sandbox} is missing the default-deny-all fallback" >&2
  exit 1
fi

echo "policy check: ${sandbox} is strict"
