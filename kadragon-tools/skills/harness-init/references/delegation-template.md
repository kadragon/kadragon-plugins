# Delegation Template

The orchestrator plans, routes, and verifies. It does NOT do the heavy lifting itself.

## Routing Table Structure

Organize into three tiers:

### Mandatory Gates (blocking)

Tasks that must complete before the workflow can proceed. These ensure quality at critical checkpoints.

```markdown
| Trigger | Delegate to | Context to pass |
|---------|-------------|-----------------|
| Before modifying a module | Analysis agent | Module path, related docs |
| Implementation task | Implementation agent | Spec, conventions, reference files |
| After implementation | QA/verification agent | Modified files list, conventions |
| Feature complete | Product evaluator | Done-when criteria, eval-criteria.md |
```

### Background Gates (non-blocking)

Fire-and-forget tasks that improve quality but don't block progress.

```markdown
| Trigger | Delegate to | Context to pass |
|---------|-------------|-----------------|
| Every commit | Code reviewer (background) | Commit hash, changed files |
| Periodic | Sweep agent (background) | tasks.md path |
```

### Escalation

When the orchestrator gets stuck.

```markdown
| Trigger | Delegate to |
|---------|-------------|
| Same failure x2 | Deep investigation agent (blocking) |
| Large refactor needed | Refactor agent (background) |
| Design decision needed | Design exploration agent (blocking) |
```

## Context Manifest

For each delegation target, specify exactly what context it needs. Pass via **file paths**, not inline content. This is critical — sub-agents start with zero context.

### Template per Agent

```markdown
### {Agent Name}

**Purpose:** {one sentence}

**Required context:**
- `{file path}` — {why this file is needed}
- `{file path}` — {why}
- {any other inputs}

**Expected output:** {what the agent should produce}
```

## Choosing Delegation Targets

Map these to the tools available in your environment:

| Need | Claude Code option | Alternative |
|------|-------------------|-------------|
| Code analysis | `Explore` subagent, custom analyzer | Inline analysis by orchestrator |
| Implementation | `general-purpose` subagent | Orchestrator implements directly |
| QA verification | Custom QA subagent | Lint + manual review |
| Code review | `code-reviewer` subagent, `/codex:review` | `pr-review-toolkit:code-reviewer` |
| Deep debugging | `/codex:rescue`, `general-purpose` subagent | Orchestrator debugs directly |
| Product evaluation | Custom evaluator with Playwright MCP | Manual testing + review |

For projects without specialized sub-agents, the `general-purpose` Agent subagent with a well-crafted prompt is sufficient. The key is separation of concerns — the agent that generates should not be the agent that evaluates.

## Model Selection per Role

Not all sub-agent tasks need the most powerful (and expensive) model. Match the model to the cognitive complexity of the task:

| Role | Recommended Model | Reasoning |
|------|------------------|-----------|
| **Structural grading** (file exists? line count?) | `haiku` | Mechanical checks, no judgment needed |
| **Code review** (bugs, style) | `sonnet` | Solid reasoning at lower cost, good for pattern matching |
| **Implementation** (write code) | `sonnet` | Standard coding tasks, follows patterns well |
| **Codebase exploration** | `sonnet` | Searching and reading, summarizing findings |
| **Architecture analysis** | `opus` | Complex multi-file reasoning, design tradeoffs |
| **Product evaluation** | `opus` | Subjective judgment, skeptical assessment, calibration needed |
| **Deep debugging** (2nd attempt) | `opus` | Root cause analysis after simpler approaches failed |
| **Sweep / garbage collection** | `haiku` or `sonnet` | Mostly grep + pattern matching, light judgment |

**Rules of thumb:**
- If the task is **checking known criteria**, use `haiku` — it's fast and cheap.
- If the task is **following instructions to produce output**, use `sonnet` — good balance of quality and cost.
- If the task requires **judgment, creativity, or multi-step reasoning**, use `opus` — worth the cost for high-stakes decisions.
- When in doubt, start with `sonnet` and escalate to `opus` only if quality is insufficient.

In Claude Code, specify the model when spawning a sub-agent:
```
Agent({
  description: "...",
  prompt: "...",
  model: "sonnet"  // or "haiku", "opus"
})
```

## Workflow → Delegation Mapping

```markdown
| Workflow | Step | Delegate |
|----------|------|----------|
| `plan` | Domain research | Analysis agent (optional) |
| `code` | Before implementation | Analysis agent (mandatory for unfamiliar areas) |
| `code` | Implementation | Implementation agent (or orchestrator for small changes) |
| `code` | Post-implementation | QA agent (mandatory) |
| `code` | Feature complete | Product evaluator (mandatory) |
| `draft` | Context gathering | Analysis agent (optional) |
| `sweep` | Large scan | Sweep agent (background) |
```

## Applying Sub-Agent Output

- **Structural fix** (typo, missing import) → apply in current cycle.
- **Behavioral change** (new feature, changed logic) → add to `backlog.md`. Never apply directly.
- **Contradicts design doc** → report both options to user. Do not choose.
