#!/usr/bin/env bash
# Launch Gemini CLI code review against a base branch.
#
# Usage: gemini-review.sh <base_branch>
# Output: Gemini's review text to stdout.
#
# Falls back to gemini-2.5-flash automatically on capacity errors (429 / RESOURCE_EXHAUSTED).

set -euo pipefail

BASE_BRANCH="${1:?Usage: gemini-review.sh <base_branch>}"

# Embed the diff directly in the prompt so Gemini doesn't need to call tools.
# This avoids tool-call latency and hanging in headless mode.
GIT_DIFF=$(git diff "${BASE_BRANCH}...HEAD" 2>/dev/null || git diff "${BASE_BRANCH}" 2>/dev/null || true)

if [ -z "$GIT_DIFF" ]; then
  echo "No changes detected against ${BASE_BRANCH} — skipping Gemini review." >&2
  exit 0
fi

REVIEW_PROMPT="You are reviewing a proposed code change against branch ${BASE_BRANCH}.

Here is the full diff:

\`\`\`diff
${GIT_DIFF}
\`\`\`

## What to flag

Only flag issues introduced by this change — not pre-existing problems. Each finding must be:
- A concrete bug, security vulnerability, or performance regression with a clear reproduction scenario
- Discrete and actionable (one issue per finding, not vague observations)
- Something the author would fix if made aware of it

Prefer no finding over a weak finding. Do not pad the review with style nits, praise, or generic advice.

## Priority levels

Tag each finding:
- [P0] Blocking — data loss, security hole, crash in production
- [P1] Urgent — incorrect behavior under normal conditions
- [P2] Normal — edge case bugs, performance issues, maintainability risks
- [P3] Low — minor improvements worth noting

## Comment format

For each finding, provide:
1. **Priority tag and title** (one line, imperative mood)
2. **file:line** reference
3. **Why** it is a problem (1 paragraph max, matter-of-fact tone)
4. **When** it manifests (specific inputs, environments, or conditions)
5. **Suggested fix** (concrete code snippet if applicable, 3 lines max)

## Output structure

List findings ordered by priority (P0 first). After all findings, add:
- **Overall verdict**: \"LGTM\" if no P0/P1 issues, or \"Changes Requested\" with a 1-sentence explanation.
- If no issues worth flagging exist, say so plainly — do not invent findings."

run_gemini() {
  local model="$1"
  # The orchestrator already enforces a 600s timeout via run_in_background.
  # macOS ships without `timeout`, so omit it here to avoid command-not-found errors.
  NO_COLOR=1 TERM=dumb gemini -m "$model" -o text -p "$REVIEW_PROMPT" --yolo
}

STDERR_FILE=$(mktemp)
trap 'rm -f "$STDERR_FILE"' EXIT

# Try with auto-gemini-3 first (matches user's ~/.gemini/settings.json default).
if run_gemini "auto-gemini-3" 2>"$STDERR_FILE"; then
  exit 0
fi

# Fall back to gemini-2.5-flash only on capacity/rate-limit errors.
if grep -qE "429|RESOURCE_EXHAUSTED|MODEL_CAPACITY_EXHAUSTED|rateLimitExceeded" "$STDERR_FILE"; then
  echo "auto-gemini-3 capacity exhausted — retrying with gemini-2.5-flash" >&2
  run_gemini "gemini-2.5-flash"
else
  # Non-capacity failure (auth, network, etc.) — surface the error.
  cat "$STDERR_FILE" >&2
  exit 1
fi
