# CI Failure Handling Guide

Detailed procedure for handling CI failures (Step 6 of dev-review-cycle).

## Wait for CI

Poll the CI status for the PR using `--watch`:

```bash
# timeout: 900000
gh pr checks <PR_NUMBER> --watch --fail-fast
```

Allow up to 15 minutes (900000ms).

## Handle CI Failure

### 1. Fetch Failure Logs

Use the bundled script:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-review-cycle/scripts/ci-failure-logs.sh <PR_NUMBER>
```

The script identifies failed checks, extracts run IDs, and returns JSON with logs for each failure (last 200 lines per job).

### 2. Classify the Fix

- **Trivial fix** (lint, type error, formatting, flaky test retry): Apply the fix directly.
- **Logic change** (behavioral modification, new/changed code paths): Apply the fix, then re-run Step 2-3 (collect reviews and get user approval) before pushing.

### 3. Verify Locally

Run tests locally to confirm the fix works.

### 4. Push

Stage, commit (referencing the PR number), and push.

### 5. Re-check CI

Return to the CI wait step. If CI fails **3 consecutive times**, stop the workflow and ask the user for guidance.

## Merge and Clean Up

After CI passes, merge the PR and clean up:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-review-cycle/scripts/merge-and-cleanup.sh \
  <PR_NUMBER> ${BASE_BRANCH} ${FEATURE_BRANCH} '${MERGE_STRATEGY_JSON}' [worktree_path]
```

The script selects the best merge strategy (squash > merge > rebase) from pre-flight data, merges with `--delete-branch`, then checks out the base branch, pulls, and safely deletes the local feature branch (`-d`, not `-D`). If a worktree path is provided, it removes that too.

If `merge_ok` is false in the output, report the error (e.g., merge conflicts, branch protection) and suggest the user resolve manually. If cleanup warnings appear, report them but do not block.
