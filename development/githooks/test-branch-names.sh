#!/usr/bin/env bash
# Tests for the branch-name rule enforced by .githooks/.
#
# Run with: make hooks-test
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
# shellcheck source=/dev/null
source "$repo_root/.githooks/lib/branch-name.sh"

pass=0
fail=0

report() { # report <ok|FAIL> <message>
  if [[ "$1" == ok ]]; then
    pass=$((pass + 1))
    printf 'ok    %s\n' "$2"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$2"
  fi
}

expect_branch() { # expect_branch <allow|reject> <branch>
  local want="$1" branch="$2" got=reject
  validate_branch "$branch" >/dev/null 2>&1 && got=allow
  if [[ "$got" == "$want" ]]; then
    report ok "$want  $branch"
  else
    report FAIL "expected $want, got $got: $branch"
  fi
}

# --- documented examples -----------------------------------------------------

expect_branch allow feat/eng-412-permit-geocoding-buffer
expect_branch allow fix/auth-token-refresh-race
expect_branch allow refactor/duckdb-parquet-partitioning
expect_branch allow chore/upgrade-sqlmesh-deps

# --- valid variants ----------------------------------------------------------

expect_branch allow main
expect_branch allow chore/3-branch-protection
expect_branch allow chore/2-sandbox
expect_branch allow feat/42-add-soda-contracts
expect_branch allow ai/auto-bump-deps
expect_branch allow ci/42-fix-lint
expect_branch allow chore/one
expect_branch allow chore/2fa-support
expect_branch allow feat/412-eng

# --- a ticket alone is not a branch name -------------------------------------

expect_branch reject chore/412
expect_branch reject feat/42
expect_branch reject feat/eng-412

# --- degenerate names --------------------------------------------------------

expect_branch reject chore/12-34

# --- wrong shape -------------------------------------------------------------

expect_branch reject c/2-sandbox
expect_branch reject feat/Foo-Bar
expect_branch reject chore/upgrade_sqlmesh_deps
expect_branch reject feat/-leading
expect_branch reject chore/trailing-
expect_branch reject chore/a-b-c-d-e-f
expect_branch reject unknown/some-branch
expect_branch reject "chore/space name"
expect_branch reject ""

# --- pre-push reads refs from stdin ------------------------------------------

push_refs() { # push_refs <ref> [<local sha>]
  printf '%s %s %s %s\n' "$1" "${2:-1111111}" "$1" "0000000" |
    "$repo_root/.githooks/pre-push" >/dev/null 2>&1
}

if push_refs refs/heads/bad_name; then
  report FAIL "pre-push allowed refs/heads/bad_name"
else
  report ok "pre-push rejects refs/heads/bad_name"
fi

if push_refs refs/heads/chore/7-good-name; then
  report ok "pre-push allows refs/heads/chore/7-good-name"
else
  report FAIL "pre-push rejected refs/heads/chore/7-good-name"
fi

if push_refs refs/heads/bad_name 0000000; then
  report ok "pre-push skips branch deletions"
else
  report FAIL "pre-push rejected a branch deletion"
fi

if push_refs refs/tags/bad_name; then
  report ok "pre-push skips tags"
else
  report FAIL "pre-push rejected a tag"
fi

# --- end-to-end through git commit -------------------------------------------

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q -b main
git -C "$tmp" config user.email hooks@example.com
git -C "$tmp" config user.name hooks
git -C "$tmp" config core.hooksPath "$repo_root/.githooks"

echo one >"$tmp/file"
git -C "$tmp" add file
if git -C "$tmp" commit -qm init >/dev/null 2>&1; then
  report ok "commit on main is allowed"
else
  report FAIL "commit on main was blocked"
fi

git -C "$tmp" checkout -q -b bad_name
echo two >>"$tmp/file"
git -C "$tmp" add file
if git -C "$tmp" commit -qm bad >/dev/null 2>&1; then
  report FAIL "commit on bad_name was allowed"
else
  report ok "commit on bad_name is blocked"
fi

git -C "$tmp" checkout -q -b chore/7-good-name
echo three >>"$tmp/file"
git -C "$tmp" add file
if git -C "$tmp" commit -qm good >/dev/null 2>&1; then
  report ok "commit on chore/7-good-name is allowed"
else
  report FAIL "commit on chore/7-good-name was blocked"
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
