---
name: dev-review-cycle
description: Post-development workflow that creates a PR, collects reviews from multiple sources (Claude Code, Gemini, Codex), consolidates feedback, applies improvements, waits for CI, and merges — all in one continuous flow. This skill should be used when the user asks to "review cycle", "run review", "review and merge", "PR review", "dev review", "리뷰 돌려줘", "리뷰 사이클", "리뷰 머지", or wants to review and merge completed work. Supports --no-hub flag to skip all GitHub operations for local-only review.
---

# Dev Review Cycle

Post-development workflow that creates a PR, collects reviews from multiple sources, consolidates feedback, and applies improvements — all in one continuous flow.

## Arguments

- `--no-hub` — Skip all GitHub operations: no push, no PR creation, no CI wait, no merge. The workflow commits locally and collects reviews based on the local diff against the base branch. Useful when you want code review feedback without publishing to GitHub.

## Prerequisites

- Initial development must be complete with all changes ready to commit.
- When using `--no-hub`, `gh` CLI authentication is not required.

## Setup: Pre-flight Checks and Repository Metadata

Run the bundled preflight script to detect available tools and repository metadata in one step. The script outputs JSON with all values needed throughout the workflow.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-review-cycle/scripts/preflight.sh [--no-hub]
```

The script detects: `gh` auth status, Gemini CLI, Codex (plugin or CLI mode), current branch, base branch, owner/repo, and merge strategy. In `--no-hub` mode it skips all remote/GitHub checks and detects the base branch purely from local state.

If `has_errors` is `true` in the output, stop the workflow and report the errors to the user.

Use the returned JSON values (`no_hub`, `feature_branch`, `base_branch`, `owner_repo`, `gemini_available`, `codex_available`, `codex_mode`, `codex_companion_path`, `merge_strategy`) in all subsequent steps instead of hardcoding. Prefer squash > merge > rebase for merge strategy, in that order of availability.

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

### Step 1: Commit (and Create PR unless `--no-hub`)

Delegate commit (and push/PR) to a **subagent** to keep the main workflow context clean.

**When `--no-hub` is set:**

```
Agent tool parameters:
  description: "Commit changes locally"
  model: "sonnet"
  prompt: |
    Commit all staged and unstaged changes in the current repository.
    1. Run `git status` and `git diff HEAD` to understand the changes.
    2. Run `git log --oneline -10` to match existing commit style.
    3. Stage relevant files with `git add` and create a single commit.
    Report the commit hash and message when done.
```

Immediately proceed to Step 2 after the subagent returns.

**When `--no-hub` is NOT set:**

```
Agent tool parameters:
  description: "Commit, push, and create PR"
  model: "sonnet"
  prompt: |
    Commit, push, and create a PR for the current changes.
    1. Run `git status`, `git diff HEAD`, and `git branch --show-current`.
    2. If on the base branch (main/master), create a new feature branch.
    3. Stage relevant files and create a single commit.
    4. Push the branch to origin.
    5. Create a pull request using `gh pr create`.
    Report the PR number and URL when done.
```

Extract the PR number and URL from the subagent's result. If the subagent reports failure, stop the workflow and report the error.

**Do NOT pause or ask the user after PR creation.** Extract the PR number and URL from the subagent result and immediately proceed to Step 2.

### Step 2: Collect Reviews

Collect reviews from up to three sources. Launch all available sources in parallel using background tasks.

#### 2-1: Claude Code Review

Launch a subagent via the Agent tool. The diff target depends on mode:
- `--no-hub`: `git diff ${BASE_BRANCH}...HEAD`
- otherwise: `git diff` against the PR's base branch

```
Agent tool parameters:
  subagent_type: "pr-review-toolkit:code-reviewer"
  model: "opus"
  description: "Code review against ${BASE_BRANCH}"
  prompt: |
    Review the changes on branch ${FEATURE_BRANCH} against ${BASE_BRANCH}.
    Run git diff ${BASE_BRANCH}...HEAD to identify all changed files.
    Check CLAUDE.md / AGENTS.md for project conventions.

    Only flag issues introduced by this change. Tag each finding:
    - [P0] Blocking — data loss, security hole, crash
    - [P1] Urgent — incorrect behavior under normal conditions
    - [P2] Normal — edge case bugs, performance, maintainability
    - [P3] Low — minor improvements

    For each finding: priority tag + title, file:line, why, when it manifests, suggested fix.
    End with overall verdict: "LGTM" or "Changes Requested".
  run_in_background: true
```

#### 2-2: Gemini CLI Review

Skip if `gemini_available` is false from pre-flight. Launch in background:

```bash
# run_in_background: true, timeout: 600000
bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-review-cycle/scripts/gemini-review.sh ${BASE_BRANCH}
```

If the command fails, proceed without this review.

#### 2-3: Codex Review

Skip if `codex_available` is false from pre-flight. Launch in background:

```bash
# run_in_background: true, timeout: 600000
bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-review-cycle/scripts/codex-review.sh ${CODEX_MODE} ${BASE_BRANCH} ${CODEX_COMPANION_PATH}
```

If the command fails, proceed without this review.

#### Collecting Results

Launch all available sources in parallel. Allow up to 10 minutes (600000ms) per source. After all reviews are collected, immediately proceed to Step 3.

### Step 3: Consolidate Reviews and Get User Approval

Deduplicate, resolve conflicts, classify scope (in/out), and present a consolidated table to the user. Follow the detailed procedure in **`references/consolidation-guide.md`**.

**STOP here and ask the user for confirmation.** Proceed to Step 4 only after user approval.

After confirmation, record any out-of-scope items in `tasks.md` per the format in `references/consolidation-guide.md`.

If no actionable in-scope suggestions exist, report that reviews found no in-scope issues and skip directly to Step 6.

### Step 4: Apply Improvements

Apply accepted improvements to the codebase. Run tests after changes to verify nothing is broken.

If tests fail after applying improvements, revert the broken change (`git checkout -- <files>`), report which suggestion caused the failure, and ask the user whether to skip it or attempt a different approach. Do not proceed to Step 5 with failing tests.

After improvements are applied and tests pass, immediately proceed to Step 5.

### Step 5: Commit (and Push unless `--no-hub`)

Delegate commit (and push) to a **subagent** to keep the main workflow context clean.

**When `--no-hub` is NOT set:**

```
Agent tool parameters:
  description: "Commit and push review improvements"
  model: "sonnet"
  prompt: |
    Commit and push the review improvements applied to this branch.
    1. Run `git status` and `git diff HEAD` to see the changes.
    2. Check CLAUDE.md / AGENTS.md for project commit conventions.
    3. Stage only the modified files.
    4. Create a single commit. Reference PR #${PR_NUMBER} in the message.
    5. Push to origin (same branch). Do NOT create a new PR.
    Report the commit hash when done.
```

After the subagent returns, immediately proceed to Step 6.

**When `--no-hub` is set:**

```
Agent tool parameters:
  description: "Commit review improvements locally"
  model: "sonnet"
  prompt: |
    Commit the review improvements locally (do NOT push).
    1. Run `git status` and `git diff HEAD` to see the changes.
    2. Check CLAUDE.md / AGENTS.md for project commit conventions.
    3. Stage only the modified files.
    4. Create a single commit.
    Do NOT push. Report the commit hash when done.
```

After the subagent returns, skip Step 6 entirely. Report the review summary and applied improvements to the user. The workflow ends here.

### Step 6: Wait for CI and Merge (skip when `--no-hub`)

Follow the detailed procedure in **`references/ci-failure-handling.md`** for CI wait, failure triage, and merge/cleanup.

Summary:

1. **Wait for CI** — `gh pr checks <PR_NUMBER> --watch --fail-fast` (timeout 15 min).
2. **On failure** — Fetch logs via `scripts/ci-failure-logs.sh`, classify fix (trivial → apply directly; logic change → re-run Steps 2-3). Hard stop after 3 consecutive failures.
3. **Merge and clean up** — Run the merge script with all 4 required positional args (5th is optional):
   ```
   bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-review-cycle/scripts/merge-and-cleanup.sh \
     <PR_NUMBER> <BASE_BRANCH> <FEATURE_BRANCH> '<MERGE_STRATEGY_JSON>' [worktree_path]
   ```
   All values come from pre-flight output: `pr_number`, `base_branch`, `feature_branch`, `merge_strategy` (JSON object, not a bare word like "squash"). Report errors if `merge_ok` is false.

## Re-running the Cycle

To run a subsequent review cycle on the same PR (e.g., after applying changes and wanting fresh reviews):

1. Skip Step 1 — the PR already exists.
2. Push the latest changes to the PR branch.
3. Start from Step 2 with the existing PR number.
4. Continue through Steps 3–6 as normal.

When `--no-hub` is set, re-running simply means committing new changes locally and collecting fresh reviews from Step 2 onward.

## Error Handling

| Failure | Action |
|---------|--------|
| Pre-flight `has_errors: true` | Stop. Report errors (e.g., suggest `gh auth login`). |
| Step 1 (commit/PR) fails | Stop. Report the error. |
| Gemini/Codex unavailable or fails | Inform user, proceed with available reviews. |
| No actionable suggestions | Report no issues. Skip Steps 4-5, proceed to Step 6. |
| Push fails (Step 5) | Report error. Suggest manual resolution. |
| CI fails 3 times | Stop. Ask user for guidance. |
| CI fix requires logic change | Re-run Steps 2-3 before pushing. |
| Merge/cleanup fails | Report `merge_ok` / warnings. Do not force-delete. |

## Additional Resources

### Reference Files

For detailed procedures, consult:
- **`references/consolidation-guide.md`** — Review deduplication, conflict resolution, scope classification, and tasks.md recording format
- **`references/ci-failure-handling.md`** — CI wait, failure triage, merge, and cleanup procedure

### Scripts

- **`scripts/preflight.sh`** — Pre-flight checks, outputs JSON with tool availability and repo metadata
- **`scripts/gemini-review.sh`** — Gemini CLI review launcher
- **`scripts/codex-review.sh`** — Codex review launcher (plugin or CLI mode)
- **`scripts/ci-failure-logs.sh`** — Fetches failed CI check logs as JSON
- **`scripts/merge-and-cleanup.sh`** `<pr_number> <base_branch> <feature_branch> '<merge_strategy_json>'` — Merges PR and cleans up local/remote branches. All 4 args required; merge_strategy is a JSON object (e.g. `'{"squash":true}'`), not a bare word.
