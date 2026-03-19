#!/usr/bin/env bash
# Poll a GitHub PR for Gemini Code Assist's Code Review (PR review, not issue comment).
# Usage: poll_gemini_review.sh <OWNER/REPO> <PR_NUMBER> [MAX_ATTEMPTS] [INTERVAL_SEC]
#
# Gemini posts two things in sequence:
#   1. An issue comment with "## Summary of Changes" — ignored.
#   2. A PR review with "## Code Review" + inline comments — this is collected.
#
# Outputs JSON with two keys: "review_body" and "inline_comments".
# Exit codes: 0 = review found, 1 = error, 2 = timeout (not found after polling).

set -euo pipefail

OWNER_REPO="${1:?Usage: poll_gemini_review.sh <OWNER/REPO> <PR_NUMBER> [MAX_ATTEMPTS] [INTERVAL_SEC]}"
PR_NUMBER="${2:?Usage: poll_gemini_review.sh <OWNER/REPO> <PR_NUMBER> [MAX_ATTEMPTS] [INTERVAL_SEC]}"
MAX_ATTEMPTS="${3:-10}"
INTERVAL="${4:-60}"

BOT_LOGIN="gemini-code-assist[bot]"

for ((i = 1; i <= MAX_ATTEMPTS; i++)); do
  # Fetch PR reviews (not issue comments)
  REVIEW_BODY=$(gh api "repos/${OWNER_REPO}/pulls/${PR_NUMBER}/reviews" \
    --jq ".[] | select(.user.login == \"${BOT_LOGIN}\") | .body" 2>/dev/null || echo "")

  if [[ -n "$REVIEW_BODY" ]] && echo "$REVIEW_BODY" | grep -q "## Code Review"; then
    # Fetch inline review comments
    INLINE_COMMENTS=$(gh api "repos/${OWNER_REPO}/pulls/${PR_NUMBER}/comments" \
      --jq "[.[] | select(.user.login == \"${BOT_LOGIN}\") | {path: .path, line: .line, body: .body}]" 2>/dev/null || echo "[]")

    # Output structured JSON
    jq -n \
      --arg body "$REVIEW_BODY" \
      --argjson inline "$INLINE_COMMENTS" \
      '{ review_body: $body, inline_comments: $inline }'
    exit 0
  fi

  if ((i < MAX_ATTEMPTS)); then
    sleep "$INTERVAL"
  fi
done

echo '{"review_body": null, "inline_comments": [], "status": "timeout"}' >&2
exit 2
