---
name: security-overview
description: Scan all GitHub security alerts (Dependabot, Code Scanning, Secret Scanning) across every repo owned by the authenticated user, ensure each repo is cloned locally, and generate a per-repo plan.md with prioritized fix tasks. Use when the user mentions security alerts, vulnerability scanning, dependabot overview, code scanning, secret scanning, "check my repos for vulnerabilities", or "security overview". Trigger even if only one alert type is mentioned — the skill covers all three.
---

# Security Overview

Scan all GitHub security alerts across the authenticated user's repos, ensure affected repos are cloned locally, and produce a `plan.md` with prioritized fix tasks.

## Execution Model

This workflow runs as a single continuous flow: Discover → Collect → Ensure Local → Plan.

Respond in the user's language; keep technical artifacts (commits, branches, file paths) in English.

## Phase 1: Discovery

### 1-1. Identify the authenticated user and all owned repos

```bash
GH_USER=$(gh api user --jq '.login')
```

```bash
gh repo list ${GH_USER} --json name,url --limit 300 -q '.[] | "\(.name) \(.url)"'
```

### 1-2. Collect all security alerts via GraphQL

Use a single GraphQL query to fetch Dependabot vulnerability alerts for all repos at once. This is the most efficient approach since REST endpoints require per-repo calls.

Note: `repositories(first: 100)` covers up to 100 repos per page. The `--paginate` flag handles cursor-based pagination automatically via `gh`, so accounts with >100 repos are fully covered.

```bash
gh api graphql --paginate -f query='
{
  viewer {
    repositories(first: 100, ownerAffiliations: OWNER) {
      nodes {
        name
        url
        vulnerabilityAlerts(first: 100, states: OPEN) {
          totalCount
          nodes {
            securityVulnerability {
              package { name ecosystem }
              severity
              advisory { summary ghsaId }
              firstPatchedVersion { identifier }
            }
          }
        }
      }
    }
  }
}'
```

### 1-3. Collect Code Scanning and Secret Scanning alerts

For each repo returned from 1-2, fetch code scanning and secret scanning alerts via REST. Run these in parallel where possible.

```bash
# Code Scanning (may return 403 if not enabled — skip gracefully)
gh api "repos/${GH_USER}/${REPO}/code-scanning/alerts?state=open" 2>/dev/null

# Secret Scanning (may return 404 if disabled — skip gracefully)
# Exclude the 'secret' field to avoid leaking values into context
gh api "repos/${GH_USER}/${REPO}/secret-scanning/alerts?state=open" --jq '[.[] | del(.secret)]' 2>/dev/null
```

Handle expected errors:
- **403** (not enabled): Record as "not enabled" — do not treat as a failure.
- **404** (disabled/no analysis): Record as "not enabled."

### 1-4. Present Summary

Present a consolidated summary table showing all repos with at least one alert:

| Repo | Dependabot | Code Scanning | Secret Scanning | Total |
|------|-----------|--------------|----------------|-------|
| repo-name | 3 (1 HIGH, 2 LOW) | 1 (1 ERROR) | 0 | 4 |

Sort by total alert count descending. Include severity breakdown. Skip repos with zero alerts.

After the table, show the overall stats:
- Total repos scanned
- Repos with alerts / repos clean
- Alert breakdown by type and severity

## Phase 2: Ensure Local Repos

For each repo that has security alerts, ensure a local clone exists.

### 2-1. Determine the workspace directory

The workspace is the **parent directory** of the current working directory. For example, if the skill runs from `~/dev/cc-plugins`, the workspace is `~/dev/`.

```bash
WORKSPACE_DIR=$(dirname "$(pwd)")
```

### 2-2. Check and clone

For each affected repo:

1. Check if `${WORKSPACE_DIR}/${REPO_NAME}` exists.
2. If it exists, report as "already cloned."
3. If not, clone it:
   ```bash
   gh repo clone ${GH_USER}/${REPO_NAME} "${WORKSPACE_DIR}/${REPO_NAME}"
   ```

Present the status:
- Already local: repo-a, repo-b
- Newly cloned: repo-c, repo-d

## Phase 3: Generate plan.md

Write a **separate** `plan.md` into **each affected repo's local directory**. The target path is always `${WORKSPACE_DIR}/${REPO_NAME}/plan.md` — one file per repo, written directly into that repo's root. Do NOT create a single consolidated plan.md in the current working directory. Every repo that has alerts gets its own plan.md.

### 3-1. Read existing code context

Before writing fix plans, read the relevant files in each repo to understand the actual fix needed:

- **Dependabot alerts**: Read only the dependency manifest (package.json, requirements.txt, pyproject.toml, go.mod, etc.) to check the current version. Do NOT read lock files or transitive dependency trees — the patched version comes from the API response.
- **Code Scanning alerts**: Read only the flagged file at the reported line range (±5 lines for context). Verify the file still exists — if deleted, the alert is stale.
- **Secret Scanning alerts**: Note the alert type and location (do NOT read or display the secret value).

### 3-2. Write plan.md per repo

For each affected repo, write (or append to) `${WORKSPACE_DIR}/${REPO_NAME}/plan.md`. If the file already exists, append the security section — do not overwrite.

Structure each repo's plan.md following this format:

```markdown
## Security Fixes — <repo-name>

> Fix all open GitHub security alerts for this repository.

### Dependabot Alerts

- [ ] Upgrade <package> from <current> to <patched> (<severity>) — <advisory summary>
- [ ] Monitor <package> for patch release (<severity>) — <advisory summary> (no patched version available yet)

### Code Scanning Alerts

- [ ] Fix <rule-id>: <description> — <file>:<line>
- [ ] Dismiss stale alert <rule-id>: <description> — file no longer exists

### Secret Scanning Alerts

- [ ] Revoke and rotate <secret-type> — <location hint>
```

Rules for plan items:
- Each `- [ ]` is one atomic, actionable fix.
- Order by severity: CRITICAL > HIGH > MODERATE > LOW within each section.
- Include the specific version to upgrade to (from `firstPatchedVersion`). If `firstPatchedVersion` is null, use the "Monitor" template instead.
- For code scanning: include the file path and line number. If the file no longer exists, use the "Dismiss stale alert" template.
- Omit empty sections (e.g., skip "Secret Scanning Alerts" if there are none).
- If a `plan.md` already exists and contains a `## Security Fixes` section, **replace** that section with the fresh scan results. Preserve all other content in the file. This prevents duplicate entries from repeated runs.

### 3-3. Present the result

After generating all plan.md files, present a summary:
- List each repo with its plan.md path (e.g., `~/dev/overtime-checker/plan.md — 3 items`)
- Total fix items across all repos
- Suggested next step: "Run `go` in each repo directory to start fixing, or pick a specific repo to begin."

**Reminder:** The output is per-repo plan.md files written into each repo's directory. Do NOT produce a single consolidated plan file.

## Error Handling

- **gh not authenticated**: Stop and suggest `gh auth login`.
- **Rate limited**: Reduce batch size or suggest waiting.
- **Permission denied on specific repos**: Report which repos were skipped and why.
- **Clone fails**: Report the error and continue with other repos.
