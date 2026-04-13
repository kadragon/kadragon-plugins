#!/usr/bin/env bash
# Launch Gemini CLI code review against a base branch.
#
# Usage: gemini-review.sh <base_branch>
# Output: Gemini's review text to stdout.

set -euo pipefail

BASE_BRANCH="${1:?Usage: gemini-review.sh <base_branch>}"

# --yolo: skip interactive confirmation prompts in Gemini CLI
NO_COLOR=1 TERM=dumb gemini -m auto-gemini-3 -o text -p "$(cat <<REVIEW_PROMPT
You are reviewing a proposed code change. Examine the diff of the current branch against ${BASE_BRANCH}.

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
- **Overall verdict**: "LGTM" if no P0/P1 issues, or "Changes Requested" with a 1-sentence explanation.
- If no issues worth flagging exist, say so plainly — do not invent findings.
REVIEW_PROMPT
)" --yolo
