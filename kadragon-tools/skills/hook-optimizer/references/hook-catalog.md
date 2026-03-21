# Hook Catalog

Example hook implementations organized by category. These are **templates to adapt**, not an exhaustive list. When building hooks for a project, modify the commands, file patterns, runner prefixes, and timeouts based on what you actually discover in the repository.

If the project uses a tool not covered here, follow the same patterns:
- **PreToolUse** for blocking (exit 2 to block, exit 0 to allow)
- **PostToolUse** for auto-fixing after edits (always exit 0, output goes to Claude as context)
- **SessionStart** for context injection

## Table of Contents

1. [Safety Hooks](#safety-hooks)
   - [S1: Block Dangerous Commands](#s1-block-dangerous-commands)
   - [S2: Protect Main Branch](#s2-protect-main-branch)
   - [S3: Protect Sensitive Files](#s3-protect-sensitive-files)
   - [S4: Block Web Access](#s4-block-web-access)
2. [Code Quality Hooks](#code-quality-hooks)
   - [Q1: Auto-Format (Biome)](#q1-auto-format-biome)
   - [Q2: Auto-Format (Prettier)](#q2-auto-format-prettier)
   - [Q3: Auto-Format (Black/Ruff)](#q3-auto-format-blackruff)
   - [Q4: Auto-Format (Go/Rust/Other)](#q4-auto-format-gorustother)
   - [Q5: Enforce Package Manager](#q5-enforce-package-manager)
   - [Q6: TypeScript Type Check](#q6-typescript-type-check)
   - [Q7: Python Type Check (Pyright / mypy)](#q7-python-type-check-pyright--mypy)
3. [Workflow Hooks](#workflow-hooks)
   - [W1: Auto-Run Related Tests](#w1-auto-run-related-tests)
   - [W2: Auto-Install Dependencies](#w2-auto-install-dependencies)
   - [W3: Git Context on Session Start](#w3-git-context-on-session-start)
   - [W4: Context Recovery After Compaction](#w4-context-recovery-after-compaction)
   - [W5: Audit Bash Commands](#w5-audit-bash-commands)

---

## Safety Hooks

### S1: Block Dangerous Commands

**Precondition**: Always applicable.

**Script**: `.claude/hooks/block-dangerous-commands.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Dangerous patterns — case-insensitive match
PATTERNS=(
  'rm\s+-rf\s+/'
  'rm\s+-rf\s+~'
  'rm\s+-rf\s+\.'
  'git\s+push\s+.*(-f|--force)'
  'git\s+reset\s+--hard'
  'DROP\s+(TABLE|DATABASE)'
  'TRUNCATE\s+TABLE'
  ':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;'
  'mkfs\.'
  'dd\s+if='
  '>\s*/dev/sd'
  'chmod\s+-R\s+777\s+/'
)

for pattern in "${PATTERNS[@]}"; do
  if echo "$CMD" | grep -qEi "$pattern"; then
    echo "Blocked: dangerous pattern detected — $pattern" >&2
    exit 2
  fi
done

exit 0
```

**Settings entry**:
```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-dangerous-commands.sh",
      "timeout": 5
    }
  ]
}
```

**Event**: `PreToolUse`

---

### S2: Protect Main Branch

**Precondition**: Git repository detected.

**Settings entry** (inline — no separate script needed):
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "BRANCH=$(git branch --show-current 2>/dev/null); if [ \"$BRANCH\" = \"main\" ] || [ \"$BRANCH\" = \"master\" ]; then echo 'Blocked: Cannot edit files on main/master branch. Create a feature branch first.' >&2; exit 2; fi; exit 0",
      "timeout": 5
    }
  ]
}
```

**Event**: `PreToolUse`

---

### S3: Protect Sensitive Files

**Precondition**: Always applicable. Customize the deny list based on detected project files.

**Script**: `.claude/hooks/protect-sensitive-files.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Normalize to relative path
FILE_PATH="${FILE_PATH#$CLAUDE_PROJECT_DIR/}"

# Denied patterns — adjust per project
DENY_PATTERNS=(
  '\.env'
  '\.env\.'
  'credentials'
  'secrets'
  '\.pem$'
  '\.key$'
  '\.p12$'
  '\.git/'
)

# Lock files — add the project's actual lock file
# __LOCKFILE_PATTERNS__

for pattern in "${DENY_PATTERNS[@]}"; do
  if echo "$FILE_PATH" | grep -qEi "$pattern"; then
    echo "Blocked: $FILE_PATH is a sensitive file and cannot be edited directly." >&2
    exit 2
  fi
done

exit 0
```

When generating this script, replace `# __LOCKFILE_PATTERNS__` with the detected lock file patterns:

**JS examples:**
```bash
# pnpm
DENY_PATTERNS+=('pnpm-lock\.yaml$')
# bun
DENY_PATTERNS+=('bun\.lockb$')
```

**Python examples:**
```bash
# uv
DENY_PATTERNS+=('uv\.lock$')
# poetry
DENY_PATTERNS+=('poetry\.lock$')
```

**Settings entry**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-sensitive-files.sh",
      "timeout": 5
    }
  ]
}
```

**Event**: `PreToolUse`

---

### S4: Block Web Access

**Precondition**: Only recommend if the project has strict offline/security requirements. Not common — ask before recommending.

**Settings entry** (inline):
```json
{
  "matcher": "WebFetch|WebSearch",
  "hooks": [
    {
      "type": "command",
      "command": "echo 'Blocked: Web access is disabled by project policy.' >&2; exit 2",
      "timeout": 5
    }
  ]
}
```

**Event**: `PreToolUse`

---

## Code Quality Hooks

### Q1: Auto-Format (Biome)

**Precondition**: `biome.json` or `biome.jsonc` exists, or `@biomejs/biome` in devDependencies.

Biome handles both formatting and linting in a single tool. The `check --write` command runs both formatter and linter with auto-fix.

**Settings entry** (inline):
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.(js|jsx|ts|tsx|json|css)$'; then npx @biomejs/biome check --write \"$FILE_PATH\" 2>/dev/null; fi; exit 0",
      "timeout": 15
    }
  ]
}
```

**Event**: `PostToolUse`

**Overlap note**: If the project uses Husky + lint-staged with biome, the pre-commit hook already runs biome on staged files. The Claude Code hook provides immediate feedback on every edit (not just at commit time), so both can coexist. Mention this to the user.

---

### Q2: Auto-Format (Prettier)

**Precondition**: `prettier` in devDependencies, or `.prettierrc*` / `prettier.config.*` exists.

**Settings entry** (inline):
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.(js|jsx|ts|tsx|css|scss|json|md|html|vue|svelte|yaml|yml)$'; then npx prettier --write \"$FILE_PATH\" 2>/dev/null; fi; exit 0",
      "timeout": 30
    }
  ]
}
```

**Event**: `PostToolUse`

---

### Q3: Auto-Format (Ruff / Black)

**Precondition**: `ruff` or `black` in dependencies, or `ruff.toml` / `.ruff.toml` / `[tool.ruff]` in `pyproject.toml`.

Adapt the command prefix based on the Python package manager:
- uv → `uv run ruff` / `uv run black`
- Poetry → `poetry run ruff` / `poetry run black`
- pip/venv → bare `ruff` / `black`

**For Ruff + uv** (preferred if available):
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.py$'; then uv run ruff format \"$FILE_PATH\" 2>/dev/null && uv run ruff check --fix \"$FILE_PATH\" 2>/dev/null; fi; exit 0",
      "timeout": 30
    }
  ]
}
```

**For Ruff (bare / pip venv)**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.py$'; then ruff format \"$FILE_PATH\" 2>/dev/null && ruff check --fix \"$FILE_PATH\" 2>/dev/null; fi; exit 0",
      "timeout": 30
    }
  ]
}
```

**For Black + uv**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.py$'; then uv run black --quiet \"$FILE_PATH\" 2>/dev/null; fi; exit 0",
      "timeout": 30
    }
  ]
}
```

**Event**: `PostToolUse`

**Overlap note**: If the project uses `pre-commit` with ruff/black hooks, note this to the user. The Claude Code hook provides immediate feedback per-edit; `pre-commit` runs at commit time. Both can coexist.

---

### Q4: Auto-Format (Go/Rust/Other)

**Go** — Precondition: `go.mod` exists.
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.go$'; then gofmt -w \"$FILE_PATH\" 2>/dev/null; fi; exit 0",
      "timeout": 15
    }
  ]
}
```

**Rust** — Precondition: `Cargo.toml` exists.
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.rs$'; then rustfmt \"$FILE_PATH\" 2>/dev/null; fi; exit 0",
      "timeout": 15
    }
  ]
}
```

**Event**: `PostToolUse`

---

### Q5: Enforce Package Manager

**Precondition**: A non-default package manager detected.

**JS/TS detection** (priority order):
1. `packageManager` field in `package.json` (e.g., `"bun@1.2.20"` → Bun)
2. Lock file: `bun.lockb` → Bun, `pnpm-lock.yaml` → pnpm, `yarn.lock` → Yarn

**Python detection** (priority order):
1. `uv.lock` or `[tool.uv]` in `pyproject.toml` → uv
2. `poetry.lock` → Poetry
3. `Pipfile.lock` → Pipenv

Customize the blocked command and suggestion:

**JS/TS:**
- Bun → block `npm` and `yarn`, suggest `bun`
- pnpm → block `npm` and `yarn`, suggest `pnpm`
- Yarn → block `npm`, suggest `yarn`

**Python:**
- uv → block `pip install` and `pip3 install`, suggest `uv add` / `uv sync`
- Poetry → block `pip install`, suggest `poetry add`

**Example for uv (Python)**:
```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r '.tool_input.command // empty'); if echo \"$CMD\" | grep -qE '\\bpip3?\\s+install\\b'; then echo 'Blocked: This project uses uv. Use \"uv add <package>\" or \"uv sync\" instead of pip install.' >&2; exit 2; fi; exit 0",
      "timeout": 5
    }
  ]
}
```

**Example for Bun (JS)**:
```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r '.tool_input.command // empty'); if echo \"$CMD\" | grep -qE '\\b(npm|yarn)\\s+(install|i|add|remove|run|exec|ci)\\b'; then echo 'Blocked: This project uses Bun. Use bun instead of npm/yarn.' >&2; exit 2; fi; exit 0",
      "timeout": 5
    }
  ]
}
```

**Example for pnpm**:
```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r '.tool_input.command // empty'); if echo \"$CMD\" | grep -qE '\\bnpm\\s+(install|i|add|remove|run|exec|ci)\\b'; then echo 'Blocked: This project uses pnpm. Use pnpm instead of npm.' >&2; exit 2; fi; exit 0",
      "timeout": 5
    }
  ]
}
```

**Event**: `PreToolUse`

---

### Q6: TypeScript Type Check

**Precondition**: `tsconfig.json` exists.

**Single tsconfig (simple project)**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.(ts|tsx)$'; then npx tsc --noEmit 2>&1 | head -20; fi; exit 0",
      "timeout": 30
    }
  ]
}
```

**Monorepo (multiple tsconfig files)** — use a script that detects which sub-project the file belongs to:

**Script**: `.claude/hooks/typecheck.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || ! echo "$FILE_PATH" | grep -qE '\.(ts|tsx)$'; then
  exit 0
fi

# Walk up from file to find nearest tsconfig.json
DIR=$(dirname "$FILE_PATH")
while [ "$DIR" != "/" ] && [ "$DIR" != "." ]; do
  if [ -f "$DIR/tsconfig.json" ]; then
    npx tsc --noEmit --project "$DIR/tsconfig.json" 2>&1 | head -20
    exit 0
  fi
  DIR=$(dirname "$DIR")
done

# Fallback to root tsconfig
npx tsc --noEmit 2>&1 | head -20
exit 0
```

Adapt `npx` to `bunx`/`pnpm exec` based on detected package manager.

**Event**: `PostToolUse`

Note: This can be slow on large projects. Only recommend if the project is small-medium or the user explicitly wants it.

---

### Q7: Python Type Check (Pyright / mypy)

**Precondition**: `pyright` or `mypy` in dependencies, or `[tool.pyright]` / `[tool.mypy]` in `pyproject.toml`.

Adapt command prefix based on Python package manager (uv → `uv run`, Poetry → `poetry run`, etc.).

**For Pyright + uv**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.py$'; then uv run pyright \"$FILE_PATH\" 2>&1 | tail -20; fi; exit 0",
      "timeout": 30
    }
  ]
}
```

**For mypy + uv**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.py$'; then uv run mypy \"$FILE_PATH\" 2>&1 | tail -20; fi; exit 0",
      "timeout": 30
    }
  ]
}
```

**Event**: `PostToolUse`

Note: Same performance caveat as Q6. Only recommend for small-medium projects or if the user explicitly wants it.

---

## Workflow Hooks

### W1: Auto-Run Related Tests

**Precondition**: Test framework detected.

Customize the test command based on detected framework and package manager:

| Framework | npm/npx | Bun | pnpm |
|-----------|---------|-----|------|
| Jest | `npx jest --findRelatedTests "$FILE_PATH" --passWithNoTests` | `bunx jest --findRelatedTests "$FILE_PATH" --passWithNoTests` | `pnpm exec jest --findRelatedTests "$FILE_PATH" --passWithNoTests` |
| Vitest | `npx vitest related "$FILE_PATH" --run` | `bunx vitest related "$FILE_PATH" --run` | `pnpm exec vitest related "$FILE_PATH" --run` |
| Pytest | `python -m pytest "$FILE_PATH" -x -q` | (same) | (same) |
| Go test | `go test ./...` | (same) | (same) |

**Example for Vitest + Bun**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.(test|spec)\\.(js|jsx|ts|tsx)$'; then bunx vitest related \"$FILE_PATH\" --run 2>&1 | tail -20; fi; exit 0",
      "timeout": 90
    }
  ]
}
```

**Example for Jest + npm**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '\\.(test|spec)\\.(js|jsx|ts|tsx)$'; then npx jest --findRelatedTests \"$FILE_PATH\" --passWithNoTests 2>&1 | tail -20; fi; exit 0",
      "timeout": 90
    }
  ]
}
```

**Example for Pytest + uv**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '(test_.*\\.py|.*_test\\.py)$'; then uv run pytest \"$FILE_PATH\" -x -q 2>&1 | tail -20; fi; exit 0",
      "timeout": 90
    }
  ]
}
```

**Example for Pytest (bare / pip venv)**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE '(test_.*\\.py|.*_test\\.py)$'; then python -m pytest \"$FILE_PATH\" -x -q 2>&1 | tail -20; fi; exit 0",
      "timeout": 90
    }
  ]
}
```

**Event**: `PostToolUse`

---

### W2: Auto-Install Dependencies

**Precondition**: Package manager detected.

Customize the install command and trigger file based on detected package manager:

| Package Manager | Trigger File | Install Command |
|-----------------|-------------|-----------------|
| npm | `package.json` | `npm install` |
| pnpm | `package.json` | `pnpm install` |
| Yarn | `package.json` | `yarn install` |
| Bun | `package.json` | `bun install` |
| uv | `pyproject.toml` | `uv sync` |
| Poetry | `pyproject.toml` | `poetry install` |
| pip | `requirements.txt` | `pip install -r requirements.txt` |

**Example for Bun (JS)**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE 'package\\.json$'; then bun install 2>/dev/null; fi; exit 0",
      "timeout": 60
    }
  ]
}
```

**Example for uv (Python)**:
```json
{
  "matcher": "Edit|Write",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); FILE_PATH=$(echo \"$INPUT\" | jq -r '.tool_input.file_path // empty'); if [ -n \"$FILE_PATH\" ] && echo \"$FILE_PATH\" | grep -qE 'pyproject\\.toml$'; then uv sync 2>/dev/null; fi; exit 0",
      "timeout": 60
    }
  ]
}
```

**Event**: `PostToolUse`

---

### W3: Git Context on Session Start

**Precondition**: Git repository.

```json
{
  "matcher": "startup|resume",
  "hooks": [
    {
      "type": "command",
      "command": "echo \"Branch: $(git branch --show-current 2>/dev/null || echo 'detached'). Recent: $(git log --oneline -3 2>/dev/null || echo 'no commits'). Status: $(git status --short 2>/dev/null | head -5)\"",
      "timeout": 5
    }
  ]
}
```

**Event**: `SessionStart`

---

### W4: Context Recovery After Compaction

**Precondition**: Git repository. Especially useful for long sessions.

```json
{
  "matcher": "compact",
  "hooks": [
    {
      "type": "command",
      "command": "echo \"[Post-compaction context] Branch: $(git branch --show-current 2>/dev/null). Last commit: $(git log --oneline -1 2>/dev/null). Uncommitted changes: $(git status --short 2>/dev/null | wc -l | tr -d ' ') files.\"",
      "timeout": 5
    }
  ]
}
```

**Event**: `SessionStart`

---

### W5: Audit Bash Commands

**Precondition**: Always applicable. Useful for security-conscious projects.

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r '.tool_input.command // empty'); echo \"$(date -u +%Y-%m-%dT%H:%M:%SZ) $CMD\" >> \"$CLAUDE_PROJECT_DIR\"/.claude/command-audit.log; exit 0",
      "async": true
    }
  ]
}
```

**Event**: `PostToolUse`

Note: If this hook is selected, add `.claude/command-audit.log` to `.gitignore`.
