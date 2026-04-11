---
name: harness-init
description: |
  Initialize a harness system for any repository — AGENTS.md (map), docs/ knowledge base, delegation routing, evaluation criteria, golden principles, and automated sweep tooling. Based on Anthropic and OpenAI harness engineering principles. Use this skill whenever the user asks to "set up a harness", "initialize agent infrastructure", "bootstrap AGENTS.md", "create agent rules", "set up Claude Code for a new repo", "하네스 초기화", "에이전트 설정", or wants to make a repository agent-ready. Also use when the user mentions wanting consistent AI-assisted development, delegation to sub-agents, automated code quality checks, or structured agent workflows for a codebase. This skill is repo-scoped — it does NOT modify global ~/.claude/CLAUDE.md.
---

# Harness Init

Set up a complete harness system for a repository so that Claude Code (and other AI agents) can do reliable, consistent work. The harness is the full environment of scaffolding, constraints, feedback loops, and documentation that surrounds an agent.

## Core Philosophy

Three sources inform this harness design:

1. **Anthropic** — Generator-Evaluator separation, context reset over compaction, every harness component encodes a model-limitation assumption that should be periodically re-examined
2. **OpenAI** — AGENTS.md is a map not an encyclopedia (~100 lines), repository is the system of record, golden principles enforced mechanically, automated garbage collection
3. **Practical experience** — Progressive disclosure (INDEX → detail), agent-readable lint errors, sub-agent context manifests

The key insight: **if the agent struggles, that's a harness defect**, not an agent defect. Fix the environment, not the prompt.

## When to Use

- Setting up a new repository for AI-assisted development
- Retrofitting an existing codebase with agent infrastructure
- After cloning a repo that has no AGENTS.md or docs/ structure
- When the user says their AI agent keeps making mistakes or forgetting context

## Prerequisites

Before starting, you need to understand the project. Gather this information (ask the user if not obvious from the repo):

1. **Tech stack** — Language(s), framework(s), database, frontend
2. **Project type** — Greenfield, legacy, monorepo, library
3. **Team size** — Solo dev, small team, large org
4. **Existing tooling** — Linters, CI, test frameworks, build tools
5. **Pain points** — What goes wrong when agents work on this repo?

## Execution Steps

Work through these steps in order. Each step produces concrete artifacts.

### Step 1: Analyze the Repository

Before creating anything, understand what exists.

```
Scan the repo for:
- README.md, CLAUDE.md, AGENTS.md (existing agent config)
- docs/ directory (existing documentation)
- Build/CI config (package.json, Cargo.toml, pom.xml, Makefile, etc.)
- Lint config (.eslintrc, checkstyle, rustfmt, etc.)
- Test infrastructure (test directories, test config)
- Source structure (how code is organized)
- Git history (commit message patterns, branch strategy)
```

Record findings — they'll shape every artifact you create. If existing AGENTS.md or docs/ exist, read them and decide what to keep vs. replace.

### Step 2: Define Golden Principles

Golden principles are the 3-7 invariants that, if violated, will cause the most damage. They should be:
- **Mechanically enforceable** (via lint, test, or hook — not verbal agreement)
- **Specific to this project** (not generic "write clean code")
- **Grounded in real pain** (past bugs, security issues, consistency problems)

Read `references/golden-principles-guide.md` for examples across different tech stacks.

Ask the user: "What are the rules that, if broken, cause the most pain in this codebase?" Their answer seeds the golden principles.

### Step 3: Create AGENTS.md

AGENTS.md is a **map, not an encyclopedia**. Target ~80-100 lines. It should fit in the agent's context window without crowding out actual work.

**Structure:**

```markdown
# {Project Name} Agent Rules

{One-line description of the project and its tech stack.}

## Docs Index (read on demand)

| File | When to read |
|------|--------------|
| `docs/architecture.md` | {when} |
| `docs/conventions.md` | {when} |
| `docs/workflows.md` | {when} |
| `docs/delegation.md` | {when} |
| `docs/eval-criteria.md` | {when} |
| `docs/runbook.md` | {when} |

## Golden Principles

Invariants enforced mechanically. Violations block commits.

1. {Principle 1}
2. {Principle 2}
...

## Delegation

Read `docs/delegation.md` for full routing table. Summary:

| {trigger} | → {agent} ({blocking/background}) |
|---|---|
...

## Working with Existing Code

- {3-5 bullet points specific to this project}

## Language Policy

- {if applicable}
```

**What NOT to put in AGENTS.md:**
- Workflow details (→ `docs/workflows.md`)
- Delegation details (→ `docs/delegation.md`)
- Evaluation criteria (→ `docs/eval-criteria.md`)
- Architecture deep dives (→ `docs/architecture.md`)
- API references, naming conventions (→ `docs/conventions.md`)

### Step 4: Create docs/ Knowledge Base

Create these files. Each one is read **on demand**, not loaded every session.

#### `docs/architecture.md`
Project structure, layer rules, module boundaries, dependency directions. This is the "lay of the land" document. Read `references/architecture-template.md` for structure.

#### `docs/conventions.md`
Naming patterns, coding standards, framework-specific rules. Only include conventions that agents frequently get wrong — don't duplicate the linter.

#### `docs/workflows.md`
How work gets done. Read `references/workflows-template.md` for the standard six workflows (plan/code/draft/constrain/sweep/explore) and adapt to the project. Include the "Permitted Side-Effects" table to avoid over-rigid workflow separation.

#### `docs/delegation.md`
Sub-agent routing table and context manifest. For each delegation target, specify:
- **Trigger** — when to invoke
- **Blocking or background**
- **Context to pass** — specific file paths the sub-agent needs
- **Expected output** — what the sub-agent should produce

Read `references/delegation-template.md` for the full template.

#### `docs/eval-criteria.md`
Product-level evaluation criteria. The evaluator is a **separate role** from the generator (this is critical — self-evaluation creates systematic bias toward leniency).

Define 3-5 grading criteria with:
- Score rubric (1-5 scale)
- Weight per criterion
- Pass threshold
- How to test each criterion
- Calibration examples (what a score of 5 vs 2 looks like)

Read `references/eval-criteria-template.md` for the template.

#### `docs/runbook.md`
Build, test, deploy commands. Common failure modes and fixes. Environment setup.

### Step 5: Set Up Sweep Automation

Create `tools/sweep.sh` (or equivalent for the project's ecosystem). The sweep script performs automated garbage collection:

1. **Lint scan** — run existing linters, auto-fix trivials
2. **Doc drift** — check if recently modified code areas have stale docs
3. **Golden principle violations** — spot-check recent changes against golden principles
4. **Harness freshness** — verify AGENTS.md and docs/ references still point to existing files
5. **Report** — append findings to `tasks.md`

Read `references/sweep-template.md` for the base script, then adapt to the project's tech stack.

### Step 6: Improve Lint for Agent Readability

If the project has linters, improve their error messages for agent consumption:

**Before (human-oriented):**
```
ERROR: Line 42 — violation of rule X
```

**After (agent-readable):**
```
ERROR: Line 42 — violation of rule X
  FIX: {what to change and how}
  REF: {which doc or config file explains this rule}
```

This is the "맞춤 린트 에러 메시지에 수정 지침을 주입" pattern from OpenAI's harness engineering. Each error message becomes a micro-instruction that tells the agent exactly how to fix the issue.

### Step 7: Build the Enforcement Chain

Documentation alone doesn't prevent violations. Build a multi-layer enforcement chain so golden principles are mechanically guaranteed, not just documented.

**Layer 1: Real-time hooks** (`.claude/settings.json`)

Create `.claude/settings.json` with hooks that fire during agent editing:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{"type": "command", "command": "bash .claude/hooks/pre-edit-guard.sh"}]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [{"type": "command", "command": "bash .claude/hooks/post-edit-lint.sh"}]
      }
    ]
  }
}
```

Design hooks that catch golden principle violations **at edit time**, before they're even committed. The hook's error message should tell the agent exactly what's wrong and how to fix it.

**Layer 2: Pre-commit checks**

Wire golden principle checks into git pre-commit hooks or the project's existing pre-commit framework. This catches anything the real-time hooks missed.

**Layer 3: CI gate**

Add golden principle enforcement to the CI pipeline. If the project has GitHub Actions, Jenkins, etc., add a step that runs the lint/check tools and blocks merge on failure.

**Layer 4: PR template** (optional)

If the project uses pull requests, create a PR template (`.github/PULL_REQUEST_TEMPLATE.md` or equivalent) with a checklist derived from golden principles.

The goal is defense in depth — each layer catches what the previous one missed:
```
Agent edits a file
  → PostToolUse hook warns immediately (Layer 1)
  → Pre-commit blocks the commit if unfixed (Layer 2)
  → CI blocks the merge (Layer 3)
  → PR reviewer confirms via checklist (Layer 4)
```

Not every project needs all 4 layers. Match the enforcement depth to the team size and risk tolerance.

### Step 8: Create CLAUDE.md Pointer

Create `CLAUDE.md` in the repo root with a single line:

```markdown
@AGENTS.md
```

This keeps the loading chain clean: Claude loads `CLAUDE.md` → which loads `AGENTS.md` (the map) → which points to `docs/` (read on demand).

### Step 9: Validate

After creating all artifacts, verify:

- [ ] AGENTS.md is under 100 lines
- [ ] All files referenced in AGENTS.md docs index actually exist
- [ ] Golden principles are enforceable (each one has a lint rule, test, or hook)
- [ ] Enforcement chain has at least 2 layers (e.g., hook + CI, or hook + pre-commit)
- [ ] Delegation table covers the project's main workflows
- [ ] Delegation table specifies model per role (haiku/sonnet/opus)
- [ ] Eval criteria are concrete and gradeable (not vague)
- [ ] Sweep script runs without errors
- [ ] `docs/` files don't duplicate each other
- [ ] `.claude/settings.json` hooks are configured for golden principle enforcement

### Step 10: Explain to the User

After setup, walk the user through what was created and how to use it. Key points:

- AGENTS.md is the entry point — keep it short, point to docs/
- Run sweep periodically (between features, or automate with CronCreate)
- Update docs/ after implementing features — stale docs are worse than no docs
- Golden principles should evolve — add new ones when new pain points emerge, remove when model capability makes them unnecessary
