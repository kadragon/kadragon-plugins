---
name: dependabot-manager
description: Comprehensive dependabot PR management across all repos. Discovers open dependabot PRs, audits grouped-updates config, triages by CI status and mergeability, batch-merges passing PRs, analyzes failures, and consolidates ungrouped PRs. Use this skill whenever the user mentions dependabot PRs, dependency updates, consolidating PRs, merging bot PRs, cleaning up dependabot, "too many dependabot PRs", bumping dependencies, managing dependencies across repos, or wants to batch-update packages from automated PRs — even if they don't say "dependabot" explicitly but describe multiple open dependency-update PRs.
---

# Dependabot Manager

Manages dependabot PRs across all repos owned by the authenticated GitHub user in three phases: Discovery → Triage → Action.

If PRs exist in multiple repos, process each repo **in parallel using subagents**.

## Subagent Model Selection

Most tasks here are structured CLI execution + simple classification — expensive models are overkill. Use the `model` parameter when spawning subagents:

| Task | Model | Rationale |
|------|-------|-----------|
| Phase 2 triage (config audit + PR status) | `haiku` | Pattern matching on gh CLI output |
| Batch merge (gh pr merge) | `haiku` | Repetitive command execution |
| `@dependabot rebase` comments | `haiku` | Single-command execution |
| CI wait + merge (polling loop) | `haiku` | Simple polling + conditional merge |
| CI failure analysis (log reading) | `sonnet` | Requires reading logs and reasoning about root cause |
| Config fix PR creation (clone + edit + push) | `sonnet` | File editing + multi-step git workflow |
| PR consolidation / major bump handling | `sonnet` | Multi-step workflow with judgment calls |

Reserve `opus` (default, no model param) only for tasks requiring complex architectural reasoning — most dependabot tasks don't.

## Phase 1: Discovery

```bash
gh search prs --author app/dependabot --state open --owner @me --json repository,number,title,url --limit 200
```

Group by repo, present count summary. If none found, exit early.

## Phase 2: Per-Repo Triage

All checks use `gh` CLI remotely — no local clone needed.

### 2a. Config Audit

```bash
gh api repos/{owner}/{repo}/contents/.github/dependabot.yml --jq '.content' | base64 -d
```

Check for: `groups:` block with `update-types: [minor, patch]`. Report status (configured / partial / missing / no file).

**GitHub Actions check:** If `.github/workflows/` exists, verify `package-ecosystem: "github-actions"` is in dependabot config. Actions without version tracking miss security patches — flag as ⚠️ if missing.

### 2b. PR Status Check

```bash
gh pr view {number} -R {owner}/{repo} --json number,title,mergeable,mergeStateStatus,statusCheckRollup,headRefName
```

| Emoji | Category | Condition |
|---|---|---|
| ✅ | Ready to merge | CI passed + `mergeable: MERGEABLE` |
| 🔄 | Needs rebase | CI passed + `CONFLICTING` or `BEHIND` |
| ❌ | CI failed | Any check failed |
| ⏳ | CI pending | Checks still running |
| ⚪ | No CI | No status checks configured |

### 2c. Triage Report

Present categorized results per repo with emoji prefix. For ❌/🔄/⚪, include a detail line explaining the issue.

## Phase 3: Action

Offer actions in order of safety. Confirm before all destructive actions.

### 3a. Batch Merge ✅ PRs

Offer: merge all / select / skip. Merge with `gh pr merge --squash --delete-branch`.

### 3b. Handle Multiple Major PRs

Detect major PRs by title (major version number differs). Merging one makes others go behind, creating a serial bottleneck.

- **≤2 major PRs** → sequential merge + `@dependabot rebase` on remaining
- **≥3 major PRs** → offer consolidated branch (`chore/major-dependency-updates`): apply all bumps together, create single PR, close originals with `gh pr close --comment "Included in #{consolidated_pr}"`

### 3c. Handle 🔄 Rebase-Needed PRs (non-major)

Offer to comment `@dependabot rebase` on each.

### 3d. Analyze ❌ Failed PRs

```bash
gh pr checks {number} -R {owner}/{repo} --json name,state,detailsUrl --jq '.[] | select(.state == "FAILURE")'
```

Analyze and suggest fix. Common: type errors (breaking API), test failures (behavioral change), build failures (peer deps), lint failures (new rules).

### 3e. Handle ⚪ No-CI PRs

Warn that merging without CI is risky. If user proceeds, confirm per PR (not batch).

### 3f. Configure Grouped Updates

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

### 3g. Consolidate Ungrouped PRs (Fallback)

For repos with 3+ individual PRs and no grouped updates, offer consolidation using:
- **npm**: `${CLAUDE_PLUGIN_ROOT}/skills/dependabot-manager/consolidate-deps.cjs`
- **Python**: `${CLAUDE_PLUGIN_ROOT}/skills/dependabot-manager/consolidate-deps.py`
- **Other**: Manual workflow via Edit tool. Requires local clone.

## Interaction Rules

- Respond in the user's language; keep technical artifacts (commits, PRs, branches) in English
- Confirm before destructive actions; default to report-only
- Errors: unauthenticated → suggest `gh auth login`; rate-limited → reduce scope; permission denied → report which repos
