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

#### 2-2: Gemini Code Assist Review

Run the bundled polling script via background Bash. The script handles the polling loop, distinguishes the "Summary" comment from the actual "Code Review", and returns structured JSON.

```bash
# run_in_background: true, timeout: 600000
bash ${CLAUDE_PLUGIN_ROOT}/scripts/poll_gemini_review.sh "${OWNER_REPO}" <PR_NUMBER> 10 60
```

If the script exits with code 2 (timeout), proceed without Gemini review.

#### 2-3: Codex CLI Review

Skip this step if `CODEX_AVAILABLE` is false from pre-flight checks.

```bash
# run_in_background: true, timeout: 300000
codex review --base ${BASE_BRANCH}
```

If the command fails, proceed without this review.

#### Collecting Results

After launching all sources in parallel, collect results. Allow these timeouts:

- **Claude Code review agent:** 600000ms (10 minutes)
- **Gemini polling script:** 600000ms (10 minutes)
- **Codex CLI:** 300000ms (5 minutes)

After all available reviews are collected, immediately proceed to Step 3.

### Step 3: Consolidate Reviews and Get User Approval

**IMPORTANT: All user-facing output in this step MUST be written in Korean.** Table headers, category names, recommendations, and explanations — everything presented to the user should be in Korean.

Analyze all collected reviews together:

1. **Deduplicate** — Merge identical issues flagged by multiple reviewers into a single entry, listing all sources (e.g., "Claude, Codex").
2. **Resolve conflicts** — When reviewers disagree, prefer the suggestion aligned with project conventions (CLAUDE.md / AGENTS.md). If conventions are silent, prefer the more conservative option and note the disagreement.
3. Consolidate remaining suggestions into a single prioritized list.
4. Categorize each suggestion: bug fix, performance, readability, style, architecture.
5. Discard suggestions that conflict with project conventions.
6. Present the consolidated list as a table with source attribution (Claude / Gemini / Codex).
7. Clearly note which suggestions are recommended to apply and which are recommended to skip (with reasons).

**STOP here and ask the user for confirmation.** The user may approve all, reject some, or request modifications. Proceed to Step 4 only after user approval.

If no actionable suggestions exist, report that reviews found no issues and skip directly to Step 6.

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
- **Gemini review not found (timeout):** Inform the user and proceed with available reviews.
- **Codex CLI not available or fails:** Inform the user and proceed with available reviews.
- **No actionable suggestions from reviews:** Report that reviews found no issues. Skip Steps 4–5 and proceed directly to Step 6 (CI wait and merge).
- **Push fails (Step 5):** Report the error and suggest the user resolve it manually.
- **CI fails 3 times (Step 6):** Stop the workflow and ask the user for guidance.
- **CI fix requires logic change (Step 6-2):** Re-run Steps 2–3 for review before pushing.
- **Merge fails (Step 6):** Report the error (e.g., merge conflicts, branch protection). Suggest the user resolve it manually.
- **Local branch delete fails (Step 6):** Report a warning but do not force-delete. The user can clean up later.
- **Worktree removal fails (Step 6):** Report a warning with the worktree path. The user can clean up manually.
