# Phase 3: Actions

Present all applicable actions at once. One confirmation per action class, then execute the full pipeline autonomously — see Autonomy Rules in SKILL.md.

## 3a. Batch Merge Ready PRs

Offer to merge all ready PRs in one shot:

```bash
gh pr merge {number} -R {owner}/{repo} --squash
```

## 3b. Handle Multiple Major PRs

Detect major PRs by title (major version number differs). Merging one makes others go behind, creating a serial bottleneck.

- **2 or fewer major PRs** — sequential merge + `@dependabot rebase` on remaining
- **3+ major PRs** — offer consolidated branch (`chore/major-dependency-updates`): apply all bumps together, create single PR, close originals with `gh pr close --comment "Included in #{consolidated_pr}"`

## 3c. Handle Rebase-Needed PRs (non-major)

Comment `@dependabot rebase` on each:

```bash
gh pr comment {number} --repo {owner}/{repo} --body "@dependabot rebase"
```

## 3d. CI Failure Analysis + Fix Pipeline

### Step 1: Analyze

Get failed job logs:

```bash
gh run list --repo {owner}/{repo} --branch {head-branch} --limit 3 --json databaseId,name,conclusion
gh run view {run-id} --repo {owner}/{repo} --log-failed 2>&1 | head -100
```

Spawn parallel `sonnet` subagents for repos with different failure patterns. For repos with the same root cause, analyze one and apply the pattern to the rest.

Common failure patterns:

| Pattern | Likely cause |
|---------|-------------|
| Runtime version mismatch | Tool upgraded its minimum engine requirement (e.g., wrangler requires Node 22) |
| Type errors | Breaking API change in dependency |
| Test failures | Behavioral change in dependency |
| Build failures | Peer dependency mismatch |
| Lint failures | New rules introduced by dependency |

### Step 2: Fix Pipeline (once user approves fix approach)

After the user confirms the fix strategy, execute this pipeline autonomously without re-asking:

1. **Create fix PRs** — spawn `sonnet` subagents in parallel, one per repo needing the fix
2. **Poll CI on fix PRs**:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/dependabot-manager/scripts/poll-ci.sh \
     --timeout 600 "owner/repo1:{fix-pr}" "owner/repo2:{fix-pr}" ...
   ```
3. **Merge fix PRs** — once all show `ready`:
   ```bash
   gh pr merge {fix-pr} --repo {owner}/{repo} --squash
   ```
4. **Trigger rebase on blocked dependabot PRs** — always do this explicitly; Dependabot does not auto-rebase after an infra fix:
   ```bash
   gh pr comment {dep-pr} --repo {owner}/{repo} --body "@dependabot rebase"
   ```
5. **Re-list open dependabot PRs** — Dependabot may close the original and open a new PR with a different number:
   ```bash
   gh pr list --repo {owner}/{repo} --author app/dependabot --state open --json number,title,url
   ```
6. **Poll CI on rebased dependabot PRs**:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/dependabot-manager/scripts/poll-ci.sh \
     --timeout 600 "owner/repo1:{new-dep-pr}" ...
   ```
7. **Merge dependabot PRs** — once all show `ready`
8. **Report completion**

## 3e. Handle No-CI PRs

Warn that merging without CI is risky. If user proceeds, confirm per PR (not batch).

## 3f. Configure Grouped Updates

For repos missing grouped updates or `github-actions` ecosystem, offer to configure. Create branch `chore/configure-dependabot-grouped-updates`, add config:

```yaml
groups:
  dependencies:
    patterns: ["*"]
    update-types: ["minor", "patch"]
```

If repo uses Actions but lacks `github-actions` ecosystem, also add:

```yaml
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      actions:
        patterns: ["*"]
        update-types: ["minor", "patch"]
```

## 3g. Consolidate Ungrouped PRs (Fallback)

For repos with 3+ individual PRs and no grouped updates, offer consolidation using bundled scripts:

- **npm**: `${CLAUDE_PLUGIN_ROOT}/skills/dependabot-manager/scripts/consolidate-deps.cjs`
- **Python**: `${CLAUDE_PLUGIN_ROOT}/skills/dependabot-manager/scripts/consolidate-deps.py`
- **Other ecosystems**: Manual workflow via Edit tool. Requires local clone.

Both scripts: fetch dependabot PRs → parse versions → create branch → apply bumps → test → commit → push → create consolidated PR → close originals.
