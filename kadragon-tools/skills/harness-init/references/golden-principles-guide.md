# Golden Principles Guide

Golden principles are the 3-7 invariants specific to a project that, if violated, cause the most damage. They must be mechanically enforceable — a principle without a lint rule, test, or hook is just a wish.

## How to Discover Golden Principles

Ask these questions:

1. **"What breaks production most often?"** → The answer usually reveals the top 2-3 principles.
2. **"What do new team members get wrong first?"** → Agents will make the same mistakes.
3. **"What rules exist that people forget?"** → If humans forget, agents will too — encode mechanically.
4. **"What security boundaries must never be crossed?"** → SQL injection, auth bypass, secret exposure.

## Examples by Tech Stack

### Web Backend (Node/Python/Java/Go)

1. **Input validation at boundaries** — Parse and validate all external input at API entry points, not deep in business logic.
2. **No raw SQL with user input** — Use parameterized queries or ORM. String concatenation with user data is a security boundary violation.
3. **Auth middleware on every route** — No endpoint should be accidentally unprotected.
4. **Structured logging** — All log statements use structured format (JSON/key-value), never string interpolation.
5. **Database migrations are additive** — Never drop columns in a migration; deprecate first.

### Frontend (React/Vue/Svelte)

1. **No inline styles for layout** — Use the design system's spacing/layout tokens.
2. **All user-facing strings go through i18n** — No hardcoded text in components.
3. **API calls go through the client layer** — Components never call fetch/axios directly.
4. **Error boundaries on every route** — No route should crash the entire app.

### Data Pipeline (Python/Spark/dbt)

1. **Schema validation on ingestion** — Every data source has a schema contract; fail fast on mismatch.
2. **Idempotent transforms** — Running the same transform twice produces the same result.
3. **No PII in logs** — All logging must sanitize sensitive fields.
4. **Partition keys are immutable** — Never change the partitioning scheme of a production table.

### Mobile (iOS/Android/React Native)

1. **No network calls on main thread** — All IO is async.
2. **Feature flags for new features** — Nothing ships without a kill switch.
3. **Backward-compatible API changes** — Old app versions must not break on API updates.

### Infrastructure (Terraform/Pulumi/CDK)

1. **No manual resource creation** — Everything is in code; drift is a bug.
2. **Least privilege IAM** — No wildcard permissions; scope to specific resources.
3. **State file is sacred** — Never manually edit terraform state.

## Writing Good Principles

**Good:** "All INSERT/UPDATE statements include audit timestamp columns via the `audit_macro` include."
- Specific, mechanically checkable, explains the mechanism.

**Bad:** "Always write secure code."
- Vague, not checkable, not actionable.

**Good:** "API response types must be generated from OpenAPI spec. Hand-written response types are not allowed."
- Specific, enforceable via lint rule, prevents drift.

**Bad:** "Keep types in sync with the API."
- How? When? What does "in sync" mean?

## From Principle to Enforcement

Each principle needs at least one enforcement mechanism:

| Enforcement | When to use | Example |
|-------------|-------------|---------|
| **Lint rule** | Pattern is syntactically detectable | "No `${}` in SQL without justification comment" |
| **Structural test** | Architectural boundary | "Controllers may not import from data layer" |
| **Pre-commit hook** | Must catch before commit | "Run schema validation on migration files" |
| **CI check** | Needs full build context | "SpotBugs static analysis on compiled classes" |
| **PostToolUse hook** | Catch during agent editing | "Run lint on every file save" |
