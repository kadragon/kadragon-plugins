---
name: hook-optimizer
description: Analyze the current repository and set up optimal Claude Code hooks tailored to its tech stack, framework, and workflow. Discovers installed tools, package managers, linters, formatters, test frameworks, and existing configuration dynamically, then presents categorized hook recommendations (safety, code quality, workflow) for the user to select. Generates `.claude/settings.json` (merging with existing config) and hook scripts, then stages them in git. Use this skill whenever the user mentions "set up hooks", "configure hooks", "optimize hooks", "add Claude Code hooks", "project hooks", wants to improve their Claude Code workflow, mentions hook setup for a new project, or asks what hooks they should use — even if they just say "hook" or "hooks 설정해줘".
---

# Hook Optimizer

Analyze the current repository and configure optimal Claude Code hooks for it.

## Overview

This skill follows a strict sequence: **Analyze → Recommend → Confirm → Apply**. Never skip the confirmation step — the user decides which hooks to install.

The approach is **discovery-based**: rather than matching against a fixed list of known tools, you inspect what's actually installed in the project and build hooks accordingly. The catalog in `references/hook-catalog.md` provides example patterns — adapt them to whatever you find.

## Step 1: Analyze Repository

Run these checks in parallel to build a project profile. Gather facts only — no recommendations yet.

### 1a. Language & Manifest Detection

Look for manifest files that reveal language, framework, and tooling:

```bash
# Common manifest files (use for loop to avoid zsh NOMATCH errors)
for f in package.json tsconfig.json pyproject.toml setup.py setup.cfg Cargo.toml go.mod go.sum Gemfile build.gradle pom.xml Makefile CMakeLists.txt deno.json; do [ -f "$f" ] && echo "$f"; done
```

Then read the relevant manifests to extract dependencies and tool configurations:
- **JS/TS**: Read `package.json` — `dependencies`, `devDependencies`, `packageManager`, `scripts`, `lint-staged`
- **Python**: Read full `pyproject.toml` — `[project.dependencies]`, `[dependency-groups]`, `[tool.*]` sections reveal installed tools
- **Rust**: Read `Cargo.toml` for dependencies
- **Go**: Read `go.mod` for module info
- Read any other manifest that exists

### 1b. Tooling Discovery

The goal is to answer: **what formatter, linter, type checker, test runner, and package manager does this project use?**

Don't just look for known config files — check what's actually declared in dependencies and config:

```bash
# Lock files (any ecosystem)
for f in package-lock.json yarn.lock pnpm-lock.yaml bun.lockb uv.lock poetry.lock Pipfile.lock Gemfile.lock; do [ -f "$f" ] && echo "$f"; done

# Package manager field (JS)
cat package.json 2>/dev/null | jq -r '.packageManager // empty' 2>/dev/null

# Config files for linters/formatters/tools (non-exhaustive — check what's in deps too)
for f in biome.json biome.jsonc .flake8 .pylintrc .rubocop.yml .golangci.yml rustfmt.toml .clang-format .editorconfig; do [ -f "$f" ] && echo "$f"; done
ls .eslintrc* eslint.config.* .prettierrc* prettier.config.* .stylelintrc* .ruff.toml ruff.toml 2>/dev/null || true

# Test configs
ls jest.config.* vitest.config.* playwright.config.* cypress.config.* .mocharc.* karma.conf.* 2>/dev/null || true
for f in pytest.ini conftest.py setup.cfg tox.ini; do [ -f "$f" ] && echo "$f"; done

# Pre-commit systems (detect overlap)
for f in .husky/pre-commit .git/hooks/pre-commit .pre-commit-config.yaml; do [ -f "$f" ] && echo "$f"; done
cat .husky/pre-commit 2>/dev/null
cat .pre-commit-config.yaml 2>/dev/null
cat package.json 2>/dev/null | jq -r '."lint-staged" // empty' 2>/dev/null
```

**Key principle**: If a tool appears in `devDependencies`, `[dependency-groups.dev]`, or a `[tool.X]` section in `pyproject.toml`, treat it as installed — even if there's no separate config file for it.

### 1c. Existing Claude Code Configuration

```bash
cat .claude/settings.json 2>/dev/null
cat .claude/settings.local.json 2>/dev/null
ls -la .claude/hooks/ 2>/dev/null
head -100 CLAUDE.md 2>/dev/null
```

### 1d. Git & CI Configuration

```bash
git branch --show-current 2>/dev/null
ls .github/workflows/*.yml .gitlab-ci.yml Jenkinsfile .circleci/config.yml 2>/dev/null || true
grep -n '\.claude' .gitignore 2>/dev/null
```

### 1e. Project Scale

```bash
find . -type f \
  -not -path './.git/*' -not -path '*/node_modules/*' \
  -not -path '*/.venv/*' -not -path '*/venv/*' -not -path '*/env/*' \
  -not -path '*/__pycache__/*' -not -path '*/target/*' \
  -not -path '*/dist/*' -not -path '*/build/*' \
  | wc -l
```

### Profile Output

Compile findings into a profile table. Use the user's language:

```
## Project Profile

| Item | Value |
|------|-------|
| Language | ... |
| Framework | ... |
| Package Manager | ... |
| Formatter | ... |
| Linter | ... |
| Type Checker | ... (if any) |
| Test Runner | ... |
| CI | ... |
| Pre-commit | ... (or None) |
| Existing hooks | ... |
| .claude/ gitignored | Yes / No |
```

---

## Step 2: Build Recommendations

Based on the profile, build hook recommendations dynamically. Don't just pattern-match against the catalog — think about what would genuinely help this project.

### Hook Categories

For each category, determine what applies based on what you discovered:

#### Safety (almost always applicable)

- **Block Dangerous Commands** — Always recommend. Blocks `rm -rf /`, `git push --force`, `DROP TABLE`, fork bombs, etc.
- **Protect Main Branch** — Recommend if git repo detected. Block edits on main/master.
- **Protect Sensitive Files** — Recommend always. Customize the deny list based on what sensitive files the project actually has (`.env*`, lock files, credential files, etc.).

#### Code Quality (based on discovered tools)

- **Auto-Format** — If a formatter was detected (any formatter — Prettier, Biome, Ruff, Black, gofmt, rustfmt, dart format, clang-format, or anything else), recommend a PostToolUse hook that runs it on edited files. Match the file extensions the formatter handles. Use the correct runner prefix (e.g., `uv run ruff` not bare `ruff` if uv is the package manager).
- **Enforce Package Manager** — If a non-default package manager was detected, recommend blocking the default. Examples: block `npm` if pnpm/bun/yarn; block `pip install` if uv/poetry. Adapt to whatever you find.
- **Type Check** — If a type checker was detected (tsc, pyright, mypy, etc.), optionally recommend running it on file edits. Warn that this can be slow on large projects.

#### Workflow (based on project setup)

- **Auto-Run Related Tests** — If a test runner was detected, recommend running related tests on test file edits. Adapt the file pattern and command to the actual test runner and naming convention.
- **Auto-Install Dependencies** — Recommend running install when the manifest file changes. Adapt trigger file and install command to the detected package manager.
- **Git Context Injection** — Recommend injecting branch/commit info on session start and after compaction.

### Adaptation Principles

When building hook commands:

1. **Use the right runner**: If the project uses `uv`, prefix Python tools with `uv run`. If it uses `bun`, use `bunx` instead of `npx`. If it uses `poetry`, use `poetry run`. Don't assume bare commands will work.

2. **Match actual file patterns**: If the project's tests are named `test_*.py`, match that — not `*.test.ts`. Look at what files actually exist.

3. **Note overlaps**: If `pre-commit`, Husky, or CI already runs a tool, mention this. The Claude Code hook adds per-edit feedback, which is still valuable, but the user should know.

4. **Don't force tools that aren't installed**: If the project doesn't have a linter, don't recommend an auto-lint hook. Only recommend hooks for tools that are actually present.

5. **Adapt, don't copy**: The catalog in `references/hook-catalog.md` has example patterns. Use them as starting points, but modify the commands, file patterns, and timeouts to fit the actual project.

### Present Recommendations

Group by category. Use the user's language. Template:

```
## Recommended Hooks

### Safety

1. **[Block Dangerous Commands]** — ...
2. **[Protect Main Branch]** — ...
3. **[Protect Sensitive Files]** — ...

### Code Quality

4. **[Auto-Format ({tool name})]** — Run {tool} after file edits
   - Note: {overlap info if applicable}

5. **[Enforce {PM name}]** — Block {blocked PM} in favor of {detected PM}

### Workflow

6. **[Auto-Run Tests ({runner})]** — ...
7. **[Auto-Install Dependencies]** — ...
8. **[Git Context Injection]** — ...
```

After listing, ask the user to select by number (e.g., `1,2,4,8` or `"all"`).

---

## Step 3: Confirm Selection

Show a summary of what will be created:

```
## Installation Summary

### Files to create/modify:
- `.claude/settings.json` — hook configuration (merged with existing)
- `.claude/hooks/block-dangerous-commands.sh` — (if selected)
- `.claude/hooks/protect-sensitive-files.sh` — (if selected)

### Merge with existing settings:
- PreToolUse: existing N + new N
- PostToolUse: new N

Proceed? (y/n)
```

---

## Step 4: Apply Configuration

### 4a. Create Hook Scripts

Store complex hooks (multi-line logic, multiple patterns) as executable scripts in `.claude/hooks/`. Keep inline commands for simple one-liners.

Script conventions:
- Shebang: `#!/usr/bin/env bash`
- `set -euo pipefail`
- Parse input: `INPUT=$(cat); VALUE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')`
- Portable paths: `$CLAUDE_PROJECT_DIR`
- Block: `echo "reason" >&2; exit 2`
- Allow: `exit 0`
- Make executable: `chmod +x`

### 4b. Merge settings.json

If `.claude/settings.json` exists:
1. Read existing content
2. For each hook event: **append** new entries (don't overwrite existing)
3. Preserve all non-hook settings

If it doesn't exist, create it with hooks only.

### 4c. Handle .gitignore Conflict

Check if `.claude/` is gitignored:

```bash
grep -n '\.claude' .gitignore 2>/dev/null
```

If gitignored, present options:

```
Warning: `.claude/` is in .gitignore.

1. **Remove from .gitignore** — Track settings.json and hooks in git (shareable)
2. **Selective tracking** — Add `!.claude/settings.json` and `!.claude/hooks/` exceptions
3. **Keep local only** — Don't add to git
```

### 4d. Stage in Git

If option 1 or 2:

```bash
git add .claude/settings.json .claude/hooks/
```

Do NOT commit — just stage.

---

## Step 5: Report

```
## Done

N hooks have been configured.

| Hook | Event | File |
|------|-------|------|
| ... | ... | ... |

Files have been added to the staging area. Let me know when you're ready to commit.
```

---

## Hook Catalog

The catalog in `references/hook-catalog.md` provides **example implementations** for common hook patterns. Use them as starting points — adapt commands, file patterns, timeouts, and runner prefixes to match what you actually discovered in the project.

The catalog is not exhaustive. If you discover a tool that isn't in the catalog, build the hook yourself following the same patterns (PreToolUse for blocking, PostToolUse for auto-fixing, SessionStart for context injection).
