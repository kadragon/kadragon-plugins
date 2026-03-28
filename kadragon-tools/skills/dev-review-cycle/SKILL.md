---
name: dev-review-cycle
description: Post-development workflow that creates a PR, collects reviews from multiple sources (Claude Code, Gemini, Codex), consolidates feedback, applies improvements, waits for CI, and merges — all in one continuous flow. Use when the user wants to review and merge completed work, run a full PR cycle, or says "review cycle".
---

# Dev Review Cycle

Post-development workflow that creates a PR, collects reviews from multiple sources, consolidates feedback, and applies improvements — all in one continuous flow.

## Prerequisites

- Initial development must be complete with all changes ready to commit.

## Setup: Pre-flight Checks and Repository Metadata

Before starting, verify tool availability and detect dynamic values needed throughout the workflow.

### Pre-flight Checks

```bash
# Verify gh CLI is authenticated (required)
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh CLI not authenticated. Run 'gh auth login' first."; exit 1; }

# Detect optional tools
GEMINI_AVAILABLE=false
command -v gemini >/dev/null 2>&1 && GEMINI_AVAILABLE=true

CODEX_AVAILABLE=false
command -v codex >/dev/null 2>&1 && CODEX_AVAILABLE=true
```

If `gh auth status` fails, stop the workflow and report the error.

### Repository Metadata

```bash
OWNER_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
BASE_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
FEATURE_BRANCH=$(git branch --show-current)
```

Use these values in all subsequent steps instead of hardcoding.

### Merge Strategy Detection

Detect the repository's allowed merge strategies before they are needed in Step 6:

```bash
gh api repos/${OWNER_REPO} --jq '{squash: .allow_squash_merge, merge: .allow_merge_commit, rebase: .allow_rebase_merge}'
```

Store the result. Prefer squash > merge > rebase, in that order of availability.

## CRITICAL: Execution Model

This workflow MUST execute as a single continuous flow. Transitions between steps are automatic — **except Step 3**, where user confirmation is required before applying changes.

After Step 5 (or directly after Step 3 if no changes are needed), proceed through CI wait, merge, and local cleanup without pausing.

## Workflow

### Step 0: Ensure Feature Branch

Before creating a PR, check if you are on the base branch (e.g., `main`). If so, create a new feature branch automatically — do NOT ask the user for a branch name.

Generate the branch name autonomously based on the staged/unstaged changes:

1. Inspect `git diff` and `git status` to understand what changed.
2. Derive a short, descriptive branch name (e.g., `feat/add-login-validation`, `fix/null-pointer-handler`, `refactor/cleanup-utils`).
3. Create and switch to the branch immediately:
   ```bash
   git checkout -b <generated-branch-name>
   ```

If already on a non-base branch, skip this step.

### Step 1: Create PR

Use the Skill tool directly to invoke `commit-commands:commit-push-pr`. Extract the PR number and URL from the result.

```
Skill tool parameters:
  skill: "commit-commands:commit-push-pr"
```

If the skill reports failure, stop the workflow and report the error.

After PR creation, immediately proceed to Step 2.

### Step 2: Collect Reviews

Collect reviews from up to three sources. Launch all available sources in parallel using background tasks.

#### 2-1: Claude Code PR Review

Launch a subagent via the Agent tool to perform the PR review.

```
Agent tool parameters:
  subagent_type: "pr-review-toolkit:code-reviewer"
  description: "PR review for #<PR_NUMBER>"
  prompt: "Review PR #<PR_NUMBER> in this repository. Run git diff against the base branch to identify all changed files. Review for bugs, logic errors, security vulnerabilities, code quality issues, and adherence to project conventions (check CLAUDE.md / AGENTS.md). Return a structured report with: Critical Issues, Important Issues, Suggestions, and Strengths. Include file:line references for each finding."
  run_in_background: true
```

**Timeout:** When collecting the result, allow up to 10 minutes (600000ms).

#### 2-2: Gemini CLI Review

Skip this step if `GEMINI_AVAILABLE` is false from pre-flight checks.

```bash
# run_in_background: true, timeout: 600000
gemini -p "$(cat <<REVIEW_PROMPT
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
```

If the command fails, proceed without this review.

#### 2-3: Codex CLI Review

Skip this step if `CODEX_AVAILABLE` is false from pre-flight checks.

```bash
# run_in_background: true, timeout: 600000
codex review --base ${BASE_BRANCH}
```

If the command fails, proceed without this review.

#### Collecting Results

After launching all sources in parallel, collect results. Allow these timeouts:

- **Claude Code review agent:** 600000ms (10 minutes)
- **Gemini CLI:** 600000ms (10 minutes)
- **Codex CLI:** 600000ms (10 minutes)

After all available reviews are collected, immediately proceed to Step 3.

### Step 3: Consolidate Reviews and Get User Approval

**IMPORTANT: All user-facing output in this step MUST be written in Korean.** Table headers, category names, recommendations, and explanations — everything presented to the user should be in Korean.

Analyze all collected reviews together:

1. **Deduplicate** — Merge identical issues flagged by multiple reviewers into a single entry, listing all sources (e.g., "Claude, Codex").
2. **Resolve conflicts** — When reviewers disagree, prefer the suggestion aligned with project conventions (CLAUDE.md / AGENTS.md). If conventions are silent, prefer the more conservative option and note the disagreement.
3. Consolidate remaining suggestions into a single prioritized list.
4. Categorize each suggestion: bug fix, performance, readability, style, architecture.
5. Discard suggestions that conflict with project conventions.
6. **Scope classification** — For each remaining suggestion, determine whether it falls within the current PR's scope:
   - **In-scope:** Directly related to the files and logic changed in this PR.
   - **Out-of-scope:** Valid improvement but touches unrelated code, requires a separate feature branch, or is an architectural concern beyond this PR's purpose.
7. Present the consolidated list as a table with source attribution (Claude / Gemini / Codex). Include a "Scope" column (In / Out) so the user can see the classification at a glance.
8. Clearly note which suggestions are recommended to apply and which are recommended to skip (with reasons).

**STOP here and ask the user for confirmation.** The user may approve all, reject some, change scope classifications, or request modifications. Proceed to Step 4 only after user approval.

#### 3-1: Record Out-of-Scope Items in plan.md

After user confirmation, if any suggestions were classified as out-of-scope (either by the initial classification or by user decision):

1. Read the existing `plan.md` in the project root. If it does not exist, create one.
2. Append a new section under `## Review Backlog` with the following format:

```markdown
## Review Backlog

### PR #<PR_NUMBER> — <PR title> (<date>)

- [ ] <suggestion summary> (source: <reviewer>) — <file:line if applicable>
```

3. Each out-of-scope suggestion becomes a `- [ ]` item so it can be tracked and addressed in a future cycle.
4. If a `## Review Backlog` section already exists, append the new PR's items under it — do not overwrite previous entries.

If no actionable in-scope suggestions exist, report that reviews found no in-scope issues and skip directly to Step 6.

### Step 4: Apply Improvements

Apply accepted improvements to the codebase. Run tests after changes to verify nothing is broken.

After improvements are applied, immediately proceed to Step 5.

### Step 5: Commit and Push

After all improvements are applied:

1. Stage only the modified files.
2. Create a commit following the project's commit conventions (check CLAUDE.md / AGENTS.md for the expected format). Reference the PR number in the message.
3. Push to the same branch as the PR.

The existing PR from Step 1 receives the pushed improvements. Do not create a new PR.

After pushing, immediately proceed to Step 6.

### Step 6: Wait for CI and Merge

#### 6-1: Wait for CI

Poll the CI status for the PR using `--watch`:

```bash
# timeout: 900000
gh pr checks <PR_NUMBER> --watch --fail-fast
```

**Timeout:** Allow up to 15 minutes (900000ms).

#### 6-2: Handle CI Failure

If CI fails:

1. Identify the failed workflow run ID from `gh pr checks`:
   ```bash
   gh pr checks <PR_NUMBER> --json name,state,link --jq '.[] | select(.state == "FAILURE")'
   ```
2. Fetch the CI logs for the failed job(s). Extract the run ID from the check link URL (the numeric segment after `/runs/`):
   ```bash
   gh run view <RUN_ID> --log-failed
   ```
3. Analyze the failure cause and classify the fix:
   - **Trivial fix** (lint, type error, formatting, flaky test retry): Apply the fix directly.
   - **Logic change** (behavioral modification, new/changed code paths): Apply the fix, then re-run Step 2–3 (collect reviews and get user approval) before pushing.
4. Run tests locally to verify the fix.
5. Stage, commit (referencing the PR number), and push.
6. Return to **6-1** to wait for CI again.

**Hard stop:** If CI fails 3 consecutive times, stop the workflow and ask the user for guidance.

#### 6-3: Merge PR

After CI passes, merge the PR using the preferred strategy detected in Setup:

```bash
# Use the first available strategy: squash > merge > rebase
gh pr merge <PR_NUMBER> --squash --delete-branch
```

If squash is not allowed, use `--merge`. If neither squash nor merge is allowed, use `--rebase`. The `--delete-branch` flag deletes the remote branch; if the repo is already configured to auto-delete branches on merge, this is harmless.

#### 6-4: Clean Local Branch

After merge, switch to the base branch and clean up:

```bash
git checkout ${BASE_BRANCH}
git pull origin ${BASE_BRANCH}
git branch -d ${FEATURE_BRANCH}
```

Use `-d` (not `-D`) to ensure the branch is fully merged before deletion. If `-d` fails, report the warning but do not force-delete.

If the workflow was executed from a git worktree, remove the worktree as well:

```bash
git worktree remove <WORKTREE_PATH>
```

If the worktree removal fails (e.g., untracked files), report the warning and suggest the user clean up manually.

## Re-running the Cycle

To run a subsequent review cycle on the same PR (e.g., after applying changes and wanting fresh reviews):

1. Skip Step 1 — the PR already exists.
2. Push the latest changes to the PR branch.
3. Start from Step 2 with the existing PR number.
4. Continue through Steps 3–6 as normal.

## Error Handling

- **Pre-flight fails (gh not authenticated):** Stop the workflow. Report the error and suggest running `gh auth login`.
- **Step 1 fails:** Stop the workflow and report the error.
- **Gemini CLI not available or fails:** Inform the user and proceed with available reviews.
- **Codex CLI not available or fails:** Inform the user and proceed with available reviews.
- **No actionable suggestions from reviews:** Report that reviews found no issues. Skip Steps 4–5 and proceed directly to Step 6 (CI wait and merge).
- **Push fails (Step 5):** Report the error and suggest the user resolve it manually.
- **CI fails 3 times (Step 6):** Stop the workflow and ask the user for guidance.
- **CI fix requires logic change (Step 6-2):** Re-run Steps 2–3 for review before pushing.
- **Merge fails (Step 6):** Report the error (e.g., merge conflicts, branch protection). Suggest the user resolve it manually.
- **Local branch delete fails (Step 6):** Report a warning but do not force-delete. The user can clean up later.
- **Worktree removal fails (Step 6):** Report a warning with the worktree path. The user can clean up manually.
