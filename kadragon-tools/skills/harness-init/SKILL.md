---
name: harness-init
version: 0.3.0
description: |
  This skill should be used when the user asks to "set up a harness", "initialize agent infrastructure", "bootstrap AGENTS.md", "create agent rules", "set up Claude Code for a new repo", "하네스 초기화", "에이전트 설정", or wants to make a repository agent-ready. This skill should also be used when the user mentions wanting consistent AI-assisted development, delegation to sub-agents, automated code quality checks, or structured agent workflows for a codebase. This skill is repo-scoped — it does NOT modify global ~/.claude/CLAUDE.md.
---

# Harness Init

Set up a complete harness system for a repository so that Claude Code (and other AI agents) can do reliable, consistent work. The harness is the full environment of scaffolding, constraints, feedback loops, and documentation that surrounds an agent.

## Core Philosophy

Three sources inform this harness design:

1. **Anthropic** — Generator-Evaluator separation, context reset over compaction, every harness component encodes a model-limitation assumption that should be periodically re-examined
2. **OpenAI** — AGENTS.md is a map not an encyclopedia (~100 lines), repository is the system of record, golden principles enforced mechanically, automated garbage collection
3. **Practical experience** — Progressive disclosure (INDEX -> detail), agent-readable lint errors, sub-agent context manifests

The key insight: **if the agent struggles, that's a harness defect**, not an agent defect. Fix the environment, not the prompt.

**Simplification principle:** Find the simplest solution possible, and only increase complexity when needed. Every harness component encodes an assumption about what the model can't do alone — start minimal and add scaffolding only when you observe concrete failures. A harness built for the weakest model you've ever used will slow down a stronger model.

## When to Use

- Setting up a new repository for AI-assisted development
- Retrofitting an existing codebase with agent infrastructure
- After cloning a repo that has no AGENTS.md or docs/ structure
- When the user reports that AI agents keep making mistakes or forgetting context

## Prerequisites

Before starting, gather project information (ask the user if not obvious from the repo):

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

Record findings — these shape every artifact created downstream. If existing AGENTS.md or docs/ exist, read them and decide what to keep vs. replace.

### Step 2: Define Golden Principles

Golden principles are the 3-7 invariants that, if violated, cause the most damage. They must be:
- **Mechanically enforceable** (via lint, test, or hook — not verbal agreement)
- **Specific to this project** (not generic "write clean code")
- **Grounded in real pain** (past bugs, security issues, consistency problems)

Read `references/golden-principles-guide.md` for examples across different tech stacks.

**Delegation is a golden principle candidate.** Agents overestimate their understanding and skip delegation when it's "merely recommended." If the project uses sub-agents, include a delegation discipline principle with objective, measurable triggers — not subjective ones like "unfamiliar module." See the "Delegation Discipline" section in `references/golden-principles-guide.md` for examples.

Ask the user: "What are the rules that, if broken, cause the most pain in this codebase?" The answer seeds the golden principles.

### Step 3: Create AGENTS.md

AGENTS.md is a **map, not an encyclopedia**. See `references/harness-invariants.md` → "AGENTS.md Size Policy" for thresholds (target ≤100, hard warn >200). It must fit in the agent's context window without crowding out actual work.

See `examples/agents-md-example.md` for a complete reference.

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

## Delegation

## Token Economy

## Working with Existing Code

## Language Policy

## Maintenance

{embed the AGENTS.md Edit Policy — see below}
```

**The `## Maintenance` section is mandatory.** Paste the 4-rule edit policy verbatim from `references/harness-invariants.md` → "AGENTS.md Edit Policy". This internalizes the `harness-sync` acceptance filter so any session applying edits to AGENTS.md follows the same rule — sync is not the only guardrail.

**Token Economy is mandatory.** Include the standard 5-rule block verbatim — no re-reading files, no redundant tool calls, parallel independent calls, delegate >20-line output to sub-agents, no restating user input. These rules apply every message and are the single biggest lever for keeping the context window lean on long sessions. See `examples/agents-md-example.md` → "Token Economy" for the exact block to paste.

**Context anxiety warning:** Models on lengthy tasks may prematurely wrap up work or cut corners as context fills. AGENTS.md should include a note directing the agent to prefer context resets over compaction and to write `handoff-{feature}.md` at the start of multi-session work (not when context is already degraded). See `references/workflows-template.md` → "Context Anxiety" for countermeasures.

**What NOT to put in AGENTS.md:** workflow details, delegation details, evaluation criteria, architecture deep dives, API references. These belong in `docs/`.

### Step 4: Create docs/ Knowledge Base

Create these files. Each one is read **on demand**, not loaded every session.

#### `docs/architecture.md`
Project structure, layer rules, module boundaries, dependency directions. Read `references/architecture-template.md` for structure and a concrete example.

#### `docs/conventions.md`
Naming patterns, coding standards, framework-specific rules. Only include conventions that agents frequently get wrong — do not duplicate the linter. Read `references/conventions-template.md` for the template.

#### `docs/workflows.md`
How work gets done. Read `references/workflows-template.md` for the standard six workflows (plan/code/draft/constrain/sweep/explore) and adapt to the project. Each workflow that modifies code has explicit delegation checkpoints built into its steps — delegation is not a separate document to "consult" but a mandatory gate within the workflow itself.

#### `docs/delegation.md`
Sub-agent routing table and context manifest. Read `references/delegation-template.md` for the full template including model selection per role. All triggers in the routing table must be **objective and measurable** — never use subjective conditions like "unfamiliar module" that the agent can rationalize away.

#### `docs/eval-criteria.md`
Product-level evaluation criteria with the Generator-Evaluator separation principle. Includes the Sprint Contract pattern (pre-implementation "done" negotiation), evaluator self-deception countermeasures, and calibration methodology. Read `references/eval-criteria-template.md` for the template.

#### `docs/runbook.md`
Build, test, deploy commands. Common failure modes and fixes. Environment setup. Read `references/runbook-template.md` for the template.

### Step 4b: Create Sprint / Backlog Files

Required so that `harness-sync` C (reconciliation) is a no-op on first run. Without these, sync will either silently report `Backlog clear.` forever (harmless but wasteful) or warn about a missing schema.

Create at the repo root:

- **`backlog.md`** — queue of work not yet in flight. Copy the minimal template from `references/backlog-template.md`. Empty sections are fine.
- **`tasks.md`** — DO NOT create at init time. This file only exists during an active sprint. Include the template path (`references/tasks-template.md`) as a reference in `docs/workflows.md` so the first sprint starter knows the schema.

Both files follow the **Reconciliation Contract** documented in `references/harness-invariants.md`.

### Step 5: Set Up Sweep Automation

Copy `scripts/sweep.sh` into the target project's `tools/` directory and adapt the `# ADAPT:` sections. Read `references/sweep-template.md` for ecosystem-specific adaptation guidance.

The sweep script performs five checks: lint scan, doc drift, golden principle violations, harness freshness, and finding report. It also includes a periodic **load-bearing assessment** — stress-testing whether each harness component still compensates for a real model limitation. See `references/sweep-template.md` → "Load-Bearing Assessment" for the methodology.

**Trigger policy is required** — sweep is deliberately NOT part of the session-start sync loop (too heavy to run on every session). Pick one and document it in `docs/runbook.md`:

- **Manual** (default) — developer runs `bash tools/sweep.sh` between features
- **SessionStart hook** — `.claude/settings.json` hook with a staleness guard (e.g., skip if `tools/.sweep-stamp` is <7 days old)
- **Cron / CI** — weekly GitHub Actions job or `CronCreate` schedule

Whichever is chosen, record it in `references/harness-invariants.md` → "Sweep Trigger Policy" so future sessions know where the cadence lives.

### Step 6: Improve Lint for Agent Readability

If the project has linters, improve error messages for agent consumption:

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

Each error message becomes a micro-instruction that tells the agent exactly how to fix the issue.

### Step 7: Build the Enforcement Chain

Build a multi-layer enforcement chain so golden principles are mechanically guaranteed. Read `references/enforcement-template.md` for detailed templates per layer.

**Four layers (defense in depth):**
1. **Real-time hooks** (`.claude/settings.json`) — Catch violations at edit time
2. **Pre-commit checks** — Block commits with unfixed violations
3. **CI gate** — Block merges on failure
4. **PR template** (optional) — Checklist derived from golden principles

Match enforcement depth to team size and risk tolerance. Not every project needs all 4 layers.

**Performance rule for hook scripts:** Hooks fire on every edit, so avoid `echo | grep` inside loops — each call forks a subprocess. Use bash builtin `[[ =~ ]]` (available since bash 3.0) for pattern matching instead. See the "Performance" section in `references/enforcement-template.md` for migration patterns.

**Token-economy hook worth considering:** `references/enforcement-template.md` → "Bash Output Truncation" documents a generic PostToolUse hook that tails/caps large Bash outputs (test suites, verbose builds, long `git log`). Not a golden principle but a zero-judgment win — enable for any repo that routinely runs commands with >200-line output.

### Step 8: Create Repo Root Configs

Three items at the repo root. All are mechanical wins — "create once, benefits every session."

#### `CLAUDE.md` (pointer)

```markdown
@AGENTS.md
```

Keeps the loading chain clean: Claude loads `CLAUDE.md` → `AGENTS.md` (the map) → `docs/` (read on demand). Invariant enforced by `harness-sync` B.

#### `.claudeignore` (scan exclusions)

Prevents Claude from scanning vendored dependencies, build outputs, and generated artifacts. Without it a single glob can pull in `node_modules/` or `target/` and burn tokens on files the agent won't usefully read.

1. Detect the language set from Step 1's analysis
2. Compose using `references/claudeignore-template.md` — combine "Common" + one or more language sections
3. Never include source files, migration SQL, or canonical config (`package.json`, `tsconfig.json`, etc.)

#### `.agents/skills` symlink

Required for tooling that looks up project-local skills via the conventional `.agents/` path while the actual skill files live under `.claude/skills/`. Invariant enforced by `harness-sync` E.

Create once at init time:

```bash
mkdir -p .claude/skills .agents
ln -sfn ../.claude/skills .agents/skills
```

After init, verify with `readlink .agents/skills` → must print `../.claude/skills`.

### Step 9: Validate

Run `scripts/validate-harness.sh` against the target project to verify all artifacts are complete and consistent. The script checks:

- Required files exist (`AGENTS.md`, `CLAUDE.md`, `docs/*`, `backlog.md`)
- AGENTS.md size is within the policy band (see `references/harness-invariants.md`)
- `CLAUDE.md` is exactly `@AGENTS.md`
- `.agents/skills` points to `../.claude/skills`
- `backlog.md` schema (checkbox items under `##` headings)
- AGENTS.md `## Maintenance` section contains the edit-policy rules
- Golden Principles, Delegation, enforcement layers present

A clean validate run means `harness-sync` on first invocation will be a no-op.

Manual checklist for items the script cannot verify:
- [ ] Golden principles are enforceable (each has a lint rule, test, or hook)
- [ ] Delegation table specifies model per role (haiku/sonnet/opus)
- [ ] Eval criteria are concrete and gradeable (not vague)
- [ ] `docs/` files do not duplicate each other
- [ ] Sweep trigger policy recorded in `docs/runbook.md`

### Step 10: Explain to the User

After setup, walk the user through what was created. Key points:

- AGENTS.md is the entry point — keep it short, point to docs/
- The `## Maintenance` section in AGENTS.md carries the edit-policy rules; apply them whenever touching AGENTS.md
- Run sweep per the chosen trigger (manual / hook / cron)
- Update docs/ after implementing features — stale docs are worse than no docs
- Golden principles should evolve — add new ones when new pain points emerge, remove when model capability makes them unnecessary

**Handoff to `harness-sync`:** from this point on, `harness-sync` runs silently at session start to keep the harness tidy. It maintains these exact invariants (CLAUDE.md pointer, `.agents/skills` symlink, backlog/tasks schemas, AGENTS.md size warnings). If sync ever reports unexpected drift on first run, treat it as an init bug — not a sync false positive — and fix the template here.

## Additional Resources

### Reference Files

Detailed templates and guides in `references/`:
- **`references/harness-invariants.md`** — Shared contract between `harness-init` and `harness-sync` (thresholds, file layouts, edit policy, reconciliation contract)
- **`references/golden-principles-guide.md`** — Discovery questions, tech-stack examples, principle-to-enforcement mapping
- **`references/architecture-template.md`** — Architecture doc structure with a concrete Next.js example
- **`references/conventions-template.md`** — Naming, code style, framework-specific rules, API and git conventions
- **`references/runbook-template.md`** — Build/test/deploy commands, common failures, environment variables
- **`references/workflows-template.md`** — Six workflows (plan/code/draft/constrain/sweep/explore) with permitted side-effects
- **`references/delegation-template.md`** — 3-tier routing table, context manifests, model selection per role
- **`references/eval-criteria-template.md`** — Grading rubrics, calibration examples, evaluator execution protocol
- **`references/enforcement-template.md`** — 4-layer enforcement chain with CI/hook/pre-commit templates
- **`references/sweep-template.md`** — Ecosystem-specific adaptation guide for the sweep script
- **`references/backlog-template.md`** — Minimal `backlog.md` schema (checkbox states, headings)
- **`references/tasks-template.md`** — `tasks.md` schema for active sprints (status field, required sections)
- **`references/claudeignore-template.md`** — `.claudeignore` patterns by language
- **`references/power-user-settings.md`** — Optional env vars (AUTOCOMPACT threshold, extended thinking) and output-style customization — informational, not auto-applied

### Scripts

Utility scripts in `scripts/`:
- **`scripts/sweep.sh`** — Base sweep script to copy and adapt per project
- **`scripts/validate-harness.sh`** — Validates harness completeness (file existence, AGENTS.md size, reference integrity)

### Examples

Working examples in `examples/`:
- **`examples/agents-md-example.md`** — Complete AGENTS.md for a Next.js SaaS project
