# Workflows Template

Six workflows. Pick the primary one per cycle. Minor side-effects are allowed (see bottom).

Adapt these to the project — not all projects need all six. A small library might only use `code` and `draft`. A large system might use all six.

## `plan` — Spec Generation

Expand a short prompt into a full product spec.

1. Expand into `docs/design/{feature}.md`: user stories, high-level tech design, phased feature list. **No granular implementation details** — errors cascade downstream.
2. Review with user. Don't proceed until approved.
3. Generate `backlog.md` items from approved spec.

Skip for trivial features.

## `code` — Implementation

The primary cycle for behavioral changes.

**Adapt the cycle to the project's testing infrastructure:**

- **Projects with test frameworks:** Red → Green → Refactor (TDD cycle)
- **Projects without tests:** Reference implementation → Implement → Lint/verify → Manual check
- **Legacy systems:** Read existing patterns → Implement following patterns → Cross-verify consistency

**`backlog.md` format:**

```markdown
## Feature Name
> Goal: what and why.
> Design: docs/design/{feature}.md
> Done-when: (concrete acceptance criteria — agreed BEFORE coding)

- [ ] Simplest case
- [ ] Next case builds on previous
```

**Delegation during code:** Consult `docs/delegation.md` for which sub-agents to invoke at each step.

## `draft` — Documentation

Write or update `docs/`. Ground every claim in current code. Never modify production code. If the doc reveals a missing constraint, add to `backlog.md` or `tasks.md`.

## `constrain` — Architectural Enforcement

1. Write structural test or lint rule first.
2. Run it.
3. If current code violates → add remediation to `backlog.md`, don't fix here.
4. Update `docs/architecture.md`.

## `sweep` — Garbage Collection

Fight entropy. Run between features or on a schedule.

- Run automated sweep script (`tools/sweep.sh` or equivalent)
- List findings in `tasks.md` tagged as `[doc]`, `[constraint]`, `[debt]`, or `[harness]`
- Fix trivials inline
- Leave complex items for later
- Include harness simplification: "Is this component still compensating for a real model limitation?"

## `explore` — Research

State the question → research/prototype → report options and tradeoffs → **do not commit**. If approved, flows into `plan` or `code`.

---

## Permitted Side-Effects

While in a primary workflow, these side-effects are allowed without switching:

| Primary workflow | Permitted side-effect |
|------------------|-----------------------|
| `code` | Add `[doc]` or `[constraint]` item to `tasks.md` when discovering issues |
| `code` | Update relevant docs after implementation |
| `draft` | Add `backlog.md` item when doc reveals missing behavior |
| `sweep` | Fix trivial `[doc]` items inline |

**Not permitted:** Writing production code during `draft` or `sweep`.
