---
name: harness-sync
version: 0.2.0
description: |
  This skill should be used when the user asks to "sync harness", "harness sync", "harness 동기화",
  "AGENTS.md 정리", "AGENTS.md 업데이트", "CLAUDE.md 동기화", "backlog 정리", "tasks 정리",
  "세션 시작 루틴", "하네스 유지보수", or when starting work in a repo that has AGENTS.md,
  backlog.md, or tasks.md. Also use proactively and silently at the start of any session in a repo
  with agent infrastructure (any of: AGENTS.md, CLAUDE.md pointing to AGENTS.md, backlog.md,
  tasks.md) — execute sections C through E before the user's first task and report only if
  something changed or errored.
---

# Harness Sync

Maintain the repository's agent instruction files under a **minimal-noise policy**.
Run at session start (silently) or on explicit request.

**Paired skill:** `harness-init` bootstraps the invariants that this skill
maintains. If first-run sync reports unexpected drift in a repo that *was*
init-bootstrapped, treat it as an init bug and fix the template — not as a
sync false positive.

**Primary goal:**
- `AGENTS.md` — canonical, minimal operational log (target ≤100 lines, hard warn >200)
- `CLAUDE.md` — must contain exactly one line: `@AGENTS.md`
- `.agents/skills` → `../.claude/skills` symlink
- `backlog.md` / `tasks.md` — follow the reconciliation contract

All thresholds, paths, and contracts live in `harness-init`'s
`references/harness-invariants.md`. Update there, not here, when values change.

## Execution Order

Run A → B → C → D → E → F in sequence. Each section is independent; skip gracefully if files
don't exist. Silent unless an action is taken or an error occurs.

---

## A) AGENTS.md Update Rules

The 4-rule edit policy below is also embedded verbatim in AGENTS.md's `## Maintenance`
section by `harness-init` (see `references/harness-invariants.md` → "AGENTS.md Edit Policy").
That means any session editing AGENTS.md — not only sessions that run sync — follows
the same filter. Keep the two copies in lockstep.

Update `AGENTS.md` **only** when ALL of the following are true:

1. The information is not directly discoverable from code / config / manifests / docs
2. It is operationally significant — affects build, test, deploy, or runtime safety
3. It would likely cause mistakes if left undocumented
4. It is stable and not task-specific

**Never add:**
- Architecture summaries or tech stack descriptions
- Directory structure overviews
- Style conventions already enforced by tooling
- Anything already visible in the repo
- Temporary or task-specific instructions

Keep edits minimal. Prefer modifying or removing outdated entries over appending.
When unsure, add a short inline `TODO:` comment rather than inventing guidance.

**If AGENTS.md lacks the `## Maintenance` section:** the repo was bootstrapped by an
older init or set up manually. Add the section in-place using this exact rule list
— it costs nothing and makes the policy visible to every future session.

---

## B) CLAUDE.md Deterministic Sync

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-sync/scripts/sync-claude-md.sh
```

Exit codes:
- `0` — Already contains exactly `@AGENTS.md`. Stop.
- `1` — Did not exist → script created it with `@AGENTS.md`. Done.
- `2` — Exists but differs → script printed the original content to stdout.

**If exit code 2:**
1. Read the extracted content from stdout.
2. Filter each instruction using the A) acceptance criteria above.
3. Merge qualifying items into `AGENTS.md`.
4. Rewrite `CLAUDE.md` to contain exactly (no extra text, no blank lines):
   ```
   @AGENTS.md
   ```

---

## C) Harness Reconciliation

Run silently. The script syncs `tasks.md` status into `backlog.md` and prints one status line.

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/harness-sync/scripts/reconcile-harness.py
```

Output:
- `Sprint active: <title>` — tasks.md is active or evaluating; leave intact
- `Backlog: N queued, M active` — backlog has pending items
- `Backlog clear.` — nothing pending

---

## D) Harness Docs & Skills Refresh

Run after C. Requires judgment — not scripted.

### D-1) Docs structure check

Verify the **schema** (not the content) of harness-related docs. Full schemas live in
`harness-init`'s `references/backlog-template.md` and `references/tasks-template.md`;
the minimal assertions below match those templates:

- `backlog.md` items must follow `[ ]` / `[>]` / `[x]` checkbox pattern under `##` headings
- `tasks.md` must have: top-level `# Title`, a `status:` line, and the sections
  `Scope`, `Acceptance Criteria`, `Evaluator Feedback`

If structural drift is detected, fix the schema in-place. Do **not** rewrite content.

If either file is entirely missing, the repo was not fully bootstrapped — point the
user at `harness-init` Step 4b rather than guessing at content.

### D-2) Skills refresh

```bash
find .claude/skills -name "SKILL.md" 2>/dev/null
```

For each `SKILL.md` found:
- Verify frontmatter is parseable (must have `name` and `description` fields)
- Flag stale skills: not referenced in `backlog.md` or `tasks.md` for 5+ sprints

Print stale list to stdout if any. Do **not** auto-delete — human decides.

---

## E) Skills Symlink Guard

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-sync/scripts/symlink-guard.sh
```

Ensures `.agents/skills` is a symlink pointing to `../.claude/skills`.
Silent on success; prints one line on change.

---

## F) Context Size Check

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/harness-sync/scripts/check-context-size.sh
```

Warns when the file Claude reloads every message grows past the hard-warn
threshold (default 200 lines; see `harness-invariants.md` → "AGENTS.md Size
Policy"). `harness-init` targets ≤100 lines, so the 100–200 band is a soft
zone — `validate-harness.sh` flags it at init time; this sync check stays
silent until it exceeds 200. Resolves the effective file automatically:

- If `CLAUDE.md` is exactly `@AGENTS.md` → checks `AGENTS.md`
- Otherwise → checks `CLAUDE.md` directly

Silent under the limit. On overflow, prints one line to stdout plus optional
bloat-source hints:

```
context-size: AGENTS.md is 247 lines (>200) — consider splitting into docs/*.md and leaving pointers
  hint: ~140 lines are inside fenced code blocks — AGENTS.md is a map, move examples to docs/
  hint: duplicate ## headings detected (5 total, 3 unique) — merge redundant sections
```

The two heuristics catch the most common causes of bloat:
- **Fenced code blocks > 20% of total** — AGENTS.md should be a map, not a cookbook. Long code examples belong in `docs/*.md`.
- **Duplicate `##` headings** — stale appends instead of edits; merge duplicates or subdivide with `###`.

**Do not auto-trim.** A 200+ line file may still be load-bearing. Surface the warning,
let the human decide what to move into `docs/*.md` and replace with a pointer line in
`AGENTS.md` (pattern: `See docs/conventions.md for naming rules.`).

Override the threshold via env var: `CONTEXT_SIZE_LIMIT=300 bash ...`.

---

## Bundled Scripts

| Script | Section | Purpose |
|--------|---------|---------|
| `scripts/sync-claude-md.sh` | B | Check CLAUDE.md state; exit 0/1/2 |
| `scripts/reconcile-harness.py` | C | Sync tasks.md → backlog.md |
| `scripts/symlink-guard.sh` | E | Ensure .agents/skills symlink |
| `scripts/check-context-size.sh` | F | Warn when effective CLAUDE.md/AGENTS.md > 200 lines |

All scripts are run from the repo root and operate on files in the current working directory.

## What sync does NOT do

- **sweep** — `tools/sweep.sh` (installed by `harness-init` Step 5) is deliberately
  out of the session-start loop. Too heavy to run on every session. Trigger
  policy (manual / SessionStart hook / cron) is chosen at init time and
  recorded in `docs/runbook.md`.
- **full validation** — `harness-init`'s `scripts/validate-harness.sh` does deeper
  structural checks (golden principle count, reference integrity, enforcement
  layer detection). Run it after any intentional harness change; sync only
  catches the drift it can fix mechanically.
- **content rewriting** — sync never rewrites the body of `backlog.md`,
  `tasks.md`, or `AGENTS.md`. It fixes schemas and moves state through the
  reconciliation contract; everything else is the human's call.
