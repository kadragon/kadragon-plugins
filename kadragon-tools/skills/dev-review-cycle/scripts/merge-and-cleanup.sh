#!/usr/bin/env bash
# Merge a PR using the best available strategy, then clean up local branch.
#
# Usage: merge-and-cleanup.sh <pr_number> <base_branch> <feature_branch> <merge_strategy_json> [worktree_path]
#   merge_strategy_json: e.g. '{"squash":true,"merge":true,"rebase":true}'
#   worktree_path: optional, removes the worktree after cleanup
#
# Output: JSON with merge result and cleanup status.

set -euo pipefail

PR_NUMBER="${1:?Usage: merge-and-cleanup.sh <pr_number> <base_branch> <feature_branch> <merge_strategy_json> [worktree_path]}"
BASE_BRANCH="${2:?}"
FEATURE_BRANCH="${3:?}"
MERGE_STRATEGY_JSON="${4:?}"
WORKTREE_PATH="${5:-}"

# --- Determine merge method (squash > merge > rebase) ---
MERGE_FLAG=""
if echo "$MERGE_STRATEGY_JSON" | jq -e '.squash == true' >/dev/null 2>&1; then
  MERGE_FLAG="--squash"
elif echo "$MERGE_STRATEGY_JSON" | jq -e '.merge == true' >/dev/null 2>&1; then
  MERGE_FLAG="--merge"
elif echo "$MERGE_STRATEGY_JSON" | jq -e '.rebase == true' >/dev/null 2>&1; then
  MERGE_FLAG="--rebase"
else
  MERGE_FLAG="--squash"
fi

# --- Merge PR ---
MERGE_OK=true
MERGE_OUTPUT=""
if MERGE_OUTPUT=$(gh pr merge "$PR_NUMBER" $MERGE_FLAG --delete-branch 2>&1); then
  MERGE_MSG="PR #${PR_NUMBER} merged with ${MERGE_FLAG#--}"
else
  MERGE_OK=false
  MERGE_MSG="Merge failed for PR #${PR_NUMBER}"
fi

# --- Local cleanup (only if merge succeeded) ---
CLEANUP_MSG=""
WORKTREE_MSG=""

if [ "$MERGE_OK" = "true" ]; then
  git checkout "$BASE_BRANCH" >/dev/null 2>&1
  git pull origin "$BASE_BRANCH" >/dev/null 2>&1

  # Use -d (safe delete) — only deletes if fully merged
  if git branch -d "$FEATURE_BRANCH" >/dev/null 2>&1; then
    CLEANUP_MSG="Local branch '${FEATURE_BRANCH}' deleted"
  else
    CLEANUP_MSG="WARNING: Could not delete local branch '${FEATURE_BRANCH}' (may not be fully merged)"
  fi

  # Worktree cleanup if path provided
  if [ -n "$WORKTREE_PATH" ]; then
    if git worktree remove "$WORKTREE_PATH" 2>/dev/null; then
      WORKTREE_MSG="Worktree '${WORKTREE_PATH}' removed"
    else
      WORKTREE_MSG="WARNING: Could not remove worktree '${WORKTREE_PATH}'. Clean up manually."
    fi
  fi
else
  CLEANUP_MSG="Skipped — merge did not succeed"
fi

# --- Output JSON safely with jq ---
jq -n \
  --argjson merge_ok "$MERGE_OK" \
  --arg merge_method "${MERGE_FLAG#--}" \
  --arg merge_message "$MERGE_MSG" \
  --arg merge_output "$MERGE_OUTPUT" \
  --arg cleanup_message "$CLEANUP_MSG" \
  --arg worktree_message "$WORKTREE_MSG" \
  '{
    merge_ok: $merge_ok,
    merge_method: $merge_method,
    merge_message: $merge_message,
    merge_output: $merge_output,
    cleanup_message: $cleanup_message,
    worktree_message: $worktree_message
  }'
