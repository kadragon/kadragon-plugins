---
name: dependabot-manager
description: Comprehensive dependabot PR management across all repos. Discovers open dependabot PRs, audits grouped-updates config, triages by CI status and mergeability, batch-merges passing PRs, analyzes failures, and consolidates ungrouped PRs. Use this skill whenever the user mentions dependabot PRs, dependency updates, consolidating PRs, merging bot PRs, cleaning up dependabot, "too many dependabot PRs", bumping dependencies, managing dependencies across repos, or wants to batch-update packages from automated PRs — even if they don't say "dependabot" explicitly but describe multiple open dependency-update PRs.
---

# Dependabot Manager

Manages dependabot PRs across all repos owned by the authenticated GitHub user. Discovers, triages, and processes PRs in three phases.

## Phase 1: Discovery

Find all open dependabot PRs across the user's repos in a single query:

```bash
gh search prs --author app/dependabot --state open --owner @me --json repository,number,title,url --limit 200
```

Group results by repository. Present a summary:

```
## Dependabot PR 현황
- **repo-a**: 3개 PR
- **repo-b**: 1개 PR
- **repo-c**: 5개 PR
총 9개의 dependabot PR이 3개의 repo에서 발견되었습니다.
```

If no PRs found, exit: "열린 dependabot PR이 없습니다."

If PRs exist in multiple repos, process each repo **in parallel using subagents**. If only one repo, process inline.

## Phase 2: Per-Repo Triage

For each repo, perform three checks. All of these use the `gh` CLI remotely — no local clone needed.

### 2a. Config Audit

Check if grouped updates are configured:

```bash
gh api repos/{owner}/{repo}/contents/.github/dependabot.yml --jq '.content' | base64 -d
```

Evaluate the config:
- **Has `groups:` with `update-types` containing `minor` and `patch`** → configured properly
- **Has `groups:` but missing `update-types` filter** → partially configured (major updates may be grouped too)
- **No `groups:` block** → not configured
- **No dependabot.yml at all** → not configured

Report the status per repo. Do NOT auto-configure — just report and offer later.

### 2b. PR Status Check

For each open dependabot PR, check CI status and mergeability:

```bash
gh pr view {number} -R {owner}/{repo} --json number,title,mergeable,mergeStateStatus,statusCheckRollup,headRefName
```

Categorize each PR:

| Category | Condition | Emoji |
|---|---|---|
| Ready to merge | CI passed + `mergeable: MERGEABLE` | ✅ |
| Needs rebase | CI passed + `mergeable: CONFLICTING` or `mergeStateStatus: BEHIND` | 🔄 |
| CI failed | Any check failed | ❌ |
| CI pending | Checks still running | ⏳ |
| No CI | No status checks configured | ⚪ |

### 2c. Triage Report

Present categorized results per repo:

```
## repo-a
✅ PR #12: bump lodash from 4.17.20 to 4.17.21
✅ PR #13: bump axios from 1.6.0 to 1.7.2
❌ PR #14: bump typescript from 5.3.0 to 5.5.0
   └─ 실패: "test" check — type errors in src/utils.ts

## repo-b
🔄 PR #7: bump flask from 3.0.0 to 3.1.0
   └─ base 브랜치와 충돌 발생 — rebase 필요
⚪ PR #8: bump requests from 2.31.0 to 2.32.0
   └─ CI 체크가 설정되어 있지 않습니다
```

## Phase 3: Action

After presenting the triage report, offer actions in order of safety:

### 3a. Batch Merge ✅ PRs

If any PRs are in the ✅ category:

```
✅ 병합 가능한 PR이 N개 있습니다. 일괄 병합하시겠습니까?
- "병합 (권장)": 모든 ✅ PR을 squash merge
- "선택 병합": PR별로 선택
- "스킵": 병합하지 않음
```

Merge using:

```bash
gh pr merge {number} -R {owner}/{repo} --squash --delete-branch
```

### 3b. Handle 🔄 Rebase-Needed PRs

For PRs with conflicts or behind base:

```
🔄 PR #{number}은 base 브랜치와 충돌이 있습니다.
Dependabot에게 rebase를 요청할까요?
```

Trigger dependabot rebase by commenting:

```bash
gh pr comment {number} -R {owner}/{repo} --body "@dependabot rebase"
```

### 3c. Analyze ❌ Failed PRs

For each failed PR, fetch the failed check's log:

```bash
# Get the failed check run ID
gh pr checks {number} -R {owner}/{repo} --json name,state,detailsUrl --jq '.[] | select(.state == "FAILURE")'
```

Analyze the failure and suggest a fix. Common patterns:
- **Type errors**: Breaking API change in the dependency — suggest version constraint or code fix
- **Test failures**: Behavioral change — suggest test update or pinning
- **Build failures**: Incompatible peer dependencies — suggest resolution
- **Lint failures**: New rules from updated tooling — suggest config update

### 3d. Handle ⚪ No-CI PRs

Warn the user:

```
⚪ {repo}에 CI가 설정되어 있지 않습니다.
CI 없이 dependabot PR을 병합하면 문제를 조기에 발견하기 어렵습니다.
CI를 설정한 후 다시 시도하시는 것을 권장합니다.
그래도 병합을 진행할까요?
```

If user wants to proceed anyway, merge with confirmation per PR (not batch).

### 3e. Configure Grouped Updates

For repos without grouped updates configured, offer at the end:

```
다음 repo에 Grouped Updates가 설정되어 있지 않습니다:
- repo-a
- repo-c

설정하면 minor/patch 업데이트가 하나의 PR로 묶여서 생성됩니다.
설정하시겠습니까?
```

If yes, for each repo:

1. Clone the repo (or use existing checkout if current directory matches)
2. Create branch `chore/configure-dependabot-grouped-updates`
3. Add or update `.github/dependabot.yml` with grouped updates config:

```yaml
groups:
  dependencies:
    patterns:
      - "*"
    update-types:
      - "minor"
      - "patch"
```

4. Commit and create PR:

```bash
gh pr create -R {owner}/{repo} \
  --title "chore: configure dependabot grouped updates" \
  --body "Configure dependabot to group minor and patch updates into a single PR.

Major updates remain as individual PRs for careful review."
```

### 3f. Consolidate Ungrouped PRs (Fallback)

If a repo has many individual dependabot PRs (3+) and no grouped updates, offer consolidation as an alternative to merging them individually. This uses the existing automation scripts:

- **npm**: `${CLAUDE_PLUGIN_ROOT}/skills/dependabot-manager/consolidate-deps.cjs`
- **Python**: `${CLAUDE_PLUGIN_ROOT}/skills/dependabot-manager/consolidate-deps.py`
- **Other** (yarn, cargo, etc.): Manual workflow — update deps via Edit tool, install, test, create consolidated PR

The consolidation workflow requires a local clone of the repo.

## Subagent Instructions

When processing multiple repos in parallel, spawn one subagent per repo with this prompt pattern:

```
Process dependabot PRs for repo {owner}/{repo}:
1. Check grouped updates config: gh api repos/{owner}/{repo}/contents/.github/dependabot.yml
2. For each PR, check status: gh pr view {number} -R {owner}/{repo} --json number,title,mergeable,mergeStateStatus,statusCheckRollup
3. Categorize each PR as: ✅ ready, 🔄 needs-rebase, ❌ failed, ⏳ pending, ⚪ no-ci
4. For ❌ PRs, fetch failure details
5. Return structured results
```

## User Interaction

- **Ask in Korean** for all decisions
- **Keep technical artifacts in English**: commits, PRs, branch names, CLI commands
- **Confirm before destructive actions**: merging, closing PRs, pushing config changes
- **Default to safe options**: report rather than auto-act

## Error Handling

- **gh CLI not authenticated**: Exit with "gh auth login을 먼저 실행해주세요."
- **No repos found**: Exit with "접근 가능한 repo가 없습니다."
- **API rate limiting**: Warn and suggest reducing scope to specific repos
- **Permission denied on merge**: Report which repos lack push access
