# Evaluation Criteria Template

Product-level evaluation criteria. The evaluator is a **separate role** from the generator — this separation is the single most impactful harness design decision (per Anthropic research).

Why separation matters: when asked to evaluate their own work, agents systematically lean toward leniency, praising mediocre output. An independent evaluator, while still inclined toward generosity, is far more tractable.

## Designing Criteria

Choose 3-5 criteria that cover the project's quality dimensions. Weight them by importance — don't distribute evenly.

### Template

```markdown
### {N}. {Criterion Name} (weight: {X}%)

{One sentence describing what this measures.}

| Score | Description |
|-------|-------------|
| 5 | {Excellent — specific description} |
| 4 | {Good — specific description} |
| 3 | {Acceptable — minimum bar} |
| 2 | {Poor — specific description} |
| 1 | {Broken — specific description} |

**How to test:** {Concrete steps to verify this criterion}
```

### Common Criteria by Project Type

**Web applications:**
- Functionality (40%) — Do features work end-to-end?
- UI/UX consistency (20%) — Does it match the design system?
- Performance (20%) — Page load, API response times
- Security (20%) — Auth, input validation, OWASP compliance

**APIs/Services:**
- Correctness (40%) — Do endpoints return expected data?
- Contract compliance (25%) — Does the API match its spec/schema?
- Error handling (20%) — Are errors meaningful and structured?
- Performance (15%) — Response times under load

**Libraries:**
- API design (30%) — Is the public API intuitive and consistent?
- Correctness (30%) — Do all functions work as documented?
- Documentation (20%) — Are examples and edge cases covered?
- Backward compatibility (20%) — Do existing users need to change code?

**Data pipelines:**
- Data quality (40%) — Are outputs correct and complete?
- Idempotency (20%) — Does rerunning produce the same result?
- Error recovery (20%) — Does it handle partial failures gracefully?
- Observability (20%) — Can you tell what happened from logs/metrics?

## Calibration Examples

Include 2-3 calibration examples — one excellent (score 5) and one poor (score 2). These anchor the evaluator's judgment and reduce drift across evaluations.

```markdown
### Example: Score 5 (Excellent)

{Specific, concrete example from the project showing what excellence looks like.}

### Example: Score 2 (Poor)

{Specific, concrete example showing what poor quality looks like, with specific defects listed.}
```

## Pass Threshold

Set a pass threshold that's high enough to catch real problems but not so high that minor issues block progress:

- **All criteria >= 3** (no single dimension is broken)
- **Weighted average >= 3.5** (overall quality is acceptable)

## Evaluator Execution Protocol

1. Read the `Done-when` criteria from `backlog.md`.
2. Read `docs/eval-criteria.md` for grading standards.
3. Read relevant project docs for context.
4. Exercise the feature (via Playwright MCP, API calls, or code review).
5. Grade each criterion with specific evidence.
6. Below threshold → findings become new `backlog.md` items → fix → re-evaluate.
7. All pass → feature done.

The evaluator must be **skeptical by default** — actively look for what's broken, not what works. Grade against criteria, not vibes.
