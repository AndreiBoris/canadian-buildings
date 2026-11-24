#!/usr/bin/env bash
# Branch-name rule, derived from docs/branches.md.
#
# Sourced by:
#   .githooks/pre-commit
#   .githooks/pre-push
#   development/githooks/test-branch-names.sh
#
# Keeping the rule in one place means the hooks and the tests cannot disagree.

# Long-lived branches exempt from the pattern.
BRANCH_ALLOWLIST='main'

# <type>/<ticket>-<description> or <type>/<description>
BRANCH_TYPES='feat|fix|hotfix|refactor|docs|test|ci|chore|ai'
BRANCH_TICKET='([a-z]+-)?[0-9]+'
BRANCH_WORD='[a-z0-9]+'
BRANCH_PATTERN="^($BRANCH_TYPES)/(($BRANCH_TICKET-)?$BRANCH_WORD(-$BRANCH_WORD){0,4})$"
BRANCH_TICKET_ONLY="^($BRANCH_TICKET)$"

branch_is_allowed() {
  local name
  for name in $BRANCH_ALLOWLIST; do
    [[ "$1" == "$name" ]] && return 0
  done
  return 1
}

branch_usage() {
  cat <<'EOF'

Expected:
  <type>/<ticket>-<short-kebab-description>
  <type>/<short-kebab-description>

  <type>         feat|fix|hotfix|refactor|docs|test|ci|chore|ai
  <ticket>       optional, lowercase: 42 or eng-412
  <description>  1-5 lowercase kebab-case words

Examples:
  feat/42-add-soda-contracts
  feat/eng-412-permit-geocoding-buffer
  chore/upgrade-sqlmesh-deps

See docs/branches.md. Rename with:
  git branch -m <new-name>
EOF
}

validate_branch() {
  local branch="$1" rest

  branch_is_allowed "$branch" && return 0

  if [[ ! "$branch" =~ $BRANCH_PATTERN ]]; then
    {
      echo "Invalid branch name: '$branch'"
      branch_usage
    } >&2
    return 1
  fi

  rest="${branch#*/}"

  if [[ "$rest" =~ $BRANCH_TICKET_ONLY ]]; then
    {
      echo "Invalid branch name: '$branch'"
      echo
      echo "A ticket is optional, but a description is not."
      echo "Add a short description: <type>/<ticket>-<description>"
      branch_usage
    } >&2
    return 1
  fi

  if [[ ! "$rest" =~ [a-z] ]]; then
    {
      echo "Invalid branch name: '$branch'"
      echo
      echo "The branch needs a description word, not just numbers."
      branch_usage
    } >&2
    return 1
  fi

  return 0
}
