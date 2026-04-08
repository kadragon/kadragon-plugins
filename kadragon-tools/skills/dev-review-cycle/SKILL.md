---
name: dev-review-cycle
description: Post-development workflow that creates a PR, collects reviews from multiple sources (Claude Code, Gemini, Codex), consolidates feedback, applies improvements, waits for CI, and merges — all in one continuous flow. Use when the user wants to review and merge completed work, run a full PR cycle, or says "review cycle". Supports --no-hub flag to skip all GitHub operations (push, PR, CI, merge) for local-only review.
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

**When `--no-hub` is set:**

Use the Skill tool to invoke `commit-commands:commit` to commit changes locally. No push, no PR.

```
Skill tool parameters:
  skill: "commit-commands:commit"
```

Immediately proceed to Step 2 after committing.

**When `--no-hub` is NOT set:**

Use the Skill tool directly to invoke `commit-commands:commit-push-pr`. Extract the PR number and URL from the skill's output.

```
Skill tool parameters:
  skill: "commit-commands:commit-push-pr"
```

If the skill reports failure, stop the workflow and report the error.

**Do NOT pause or ask the user after PR creation.** The PR number and URL are available in the skill output — extract them and immediately proceed to Step 2. There is no confirmation needed here; the PR is a draft artifact that will be reviewed in subsequent steps.

### Step 2: Collect Reviews

Collect reviews from up to three sources. Launch all available sources in parallel using background tasks.

#### 2-1: Claude Code Review

Launch a subagent via the Agent tool. The diff target depends on mode:
- `--no-hub`: `git diff ${BASE_BRANCH}...HEAD`
- otherwise: `git diff` against the PR's base branch

```
Agent tool parameters:
  subagent_type: "pr-review-toolkit:code-reviewer"
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

Analyze all collected reviews together. All three reviewers use the same P0–P3 priority scheme, so deduplication is straightforward.

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

#### 3-1: Record Out-of-Scope Items in tasks.md

After user confirmation, if any suggestions were classified as out-of-scope (either by the initial classification or by user decision):

1. Read the existing `tasks.md` in the project root. If it does not exist, create one.
2. Append items under a `## Review Backlog` section with the following format. Classify each item using harness tags (`[doc]`, `[constraint]`, `[debt]`, `[harness]`) based on its nature:

**When a PR exists:**
```markdown
## Review Backlog

### PR #<PR_NUMBER> — <PR title> (<date>)

- [ ] [debt] <suggestion summary> (source: <reviewer>) — <file:line if applicable>
- [ ] [doc] <suggestion summary> (source: <reviewer>) — <file:line if applicable>
```

**When `--no-hub` (no PR):**
```markdown
## Review Backlog

### <FEATURE_BRANCH> — <commit summary> (<date>)

- [ ] [debt] <suggestion summary> (source: <reviewer>) — <file:line if applicable>
```

Tag guide: `[debt]` for code quality / refactoring, `[doc]` for documentation gaps, `[constraint]` for missing tests or architectural rules, `[harness]` for tooling or CI improvements.

3. Each out-of-scope suggestion becomes a `- [ ]` item so it can be tracked and addressed in a future cycle.
4. If a `## Review Backlog` section already exists, append the new PR's items under it — do not overwrite previous entries.

If no actionable in-scope suggestions exist, report that reviews found no in-scope issues and skip directly to Step 6.

### Step 4: Apply Improvements

Apply accepted improvements to the codebase. Run tests after changes to verify nothing is broken.

If tests fail after applying improvements, revert the broken change (`git checkout -- <files>`), report which suggestion caused the failure, and ask the user whether to skip it or attempt a different approach. Do not proceed to Step 5 with failing tests.

After improvements are applied and tests pass, immediately proceed to Step 5.

### Step 5: Commit (and Push unless `--no-hub`)

After all improvements are applied:

1. Stage only the modified files.
2. Create a commit following the project's commit conventions (check CLAUDE.md / AGENTS.md for the expected format). Reference the PR number in the message (if a PR exists).

**When `--no-hub` is NOT set:**

3. Push to the same branch as the PR. The existing PR from Step 1 receives the pushed improvements. Do not create a new PR.
4. After pushing, immediately proceed to Step 6.

**When `--no-hub` is set:**

3. Do NOT push. The commit stays local.
4. Skip Step 6 entirely. Report the review summary and applied improvements to the user. The workflow ends here.

### Step 6: Wait for CI and Merge (skip when `--no-hub`)

#### 6-1: Wait for CI

Poll the CI status for the PR using `--watch`:

```bash
# timeout: 900000
gh pr checks <PR_NUMBER> --watch --fail-fast
```

**Timeout:** Allow up to 15 minutes (900000ms).

#### 6-2: Handle CI Failure

If CI fails:

1. Fetch failure logs using the bundled script:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-review-cycle/scripts/ci-failure-logs.sh <PR_NUMBER>
   ```
   The script identifies failed checks, extracts run IDs, and returns JSON with logs for each failure.

2. Analyze the failure cause and classify the fix:
   - **Trivial fix** (lint, type error, formatting, flaky test retry): Apply the fix directly.
   - **Logic change** (behavioral modification, new/changed code paths): Apply the fix, then re-run Step 2–3 (collect reviews and get user approval) before pushing.
3. Run tests locally to verify the fix.
4. Stage, commit (referencing the PR number), and push.
5. Return to **6-1** to wait for CI again.

**Hard stop:** If CI fails 3 consecutive times, stop the workflow and ask the user for guidance.

#### 6-3: Merge PR and Clean Up

After CI passes, merge the PR and clean up the local branch in one step:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-review-cycle/scripts/merge-and-cleanup.sh \
  <PR_NUMBER> ${BASE_BRANCH} ${FEATURE_BRANCH} '${MERGE_STRATEGY_JSON}' [worktree_path]
```

The script selects the best merge strategy (squash > merge > rebase) from pre-flight data, merges with `--delete-branch`, then checks out the base branch, pulls, and safely deletes the local feature branch (`-d`, not `-D`). If a worktree path is provided, it removes that too.

If `merge_ok` is false in the output, report the error (e.g., merge conflicts, branch protection) and suggest the user resolve manually. If cleanup warnings appear, report them but don't block.

## Re-running the Cycle

To run a subsequent review cycle on the same PR (e.g., after applying changes and wanting fresh reviews):

1. Skip Step 1 — the PR already exists.
2. Push the latest changes to the PR branch.
3. Start from Step 2 with the existing PR number.
4. Continue through Steps 3–6 as normal.

When `--no-hub` is set, re-running simply means committing new changes locally and collecting fresh reviews from Step 2 onward.

## Error Handling

- **Pre-flight fails (`has_errors: true`):** Stop the workflow. Report the errors from the preflight script output (e.g., suggest running `gh auth login` if `gh` is not authenticated).
- **Step 1 fails:** Stop the workflow and report the error.
- **Gemini CLI not available or fails:** Inform the user and proceed with available reviews.
- **Codex plugin not available or fails:** Inform the user and proceed with available reviews.
- **No actionable suggestions from reviews:** Report that reviews found no issues. Skip Steps 4–5 and proceed directly to Step 6 (CI wait and merge).
- **Push fails (Step 5):** Report the error and suggest the user resolve it manually.
- **CI fails 3 times (Step 6):** Stop the workflow and ask the user for guidance.
- **CI fix requires logic change (Step 6-2):** Re-run Steps 2–3 for review before pushing.
- **Merge or cleanup fails (Step 6):** The merge-and-cleanup script returns JSON with `merge_ok` and warning messages. Report errors/warnings to the user. Do not force-delete branches.
