# Sweep Script Template

The sweep script is the automated garbage collector for the harness. It catches drift, stale docs, and principle violations before they compound.

## Base Template (Bash)

Adapt this to the project's tech stack. The five checks are universal; the implementation details change.

```bash
#!/bin/bash
# sweep.sh — Automated garbage collection
# Usage:
#   ./tools/sweep.sh              # full sweep
#   ./tools/sweep.sh --quick      # lint only

set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJ_DIR="$(cd "$TOOLS_DIR/.." && pwd)"

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

FINDINGS=()
QUICK_MODE=false
[[ "${1:-}" == "--quick" ]] && QUICK_MODE=true

cd "$PROJ_DIR"

echo -e "${CYAN}=== Sweep ===${NC}"
echo -e "  Date: $(date '+%Y-%m-%d %H:%M')"

# ── 1. Lint scan ─────────────────────────────────────────────
echo -e "${CYAN}[1/5] Lint scan...${NC}"
# ADAPT: Replace with your project's lint command
# Examples:
#   npm run lint 2>&1
#   cargo clippy 2>&1
#   python -m flake8 . 2>&1
#   ./tools/lint.sh --all 2>&1
lint_output=$(echo "No lint configured — adapt this section" 2>&1) || true
# Parse lint output and add to FINDINGS if issues found

$QUICK_MODE && { echo "Quick mode — done."; exit 0; }

# ── 2. Doc drift check ──────────────────────────────────────
echo -e "${CYAN}[2/5] Doc drift...${NC}"
# Check if recently modified source files have corresponding doc updates
recent_files=$(git log --since="24 hours ago" --name-only --pretty=format: 2>/dev/null | sort -u | grep -v '^$' || true)
if [[ -n "$recent_files" ]]; then
    # ADAPT: Define which source files should have corresponding docs
    # Example: for each modified service file, check if docs/spec/ was updated
    echo -e "  ${GREEN}Checked $(echo "$recent_files" | wc -l) recent file(s)${NC}"
else
    echo -e "  ${GREEN}No recent commits${NC}"
fi

# ── 3. Golden principle spot-check ───────────────────────────
echo -e "${CYAN}[3/5] Golden principles...${NC}"
# ADAPT: Check project-specific golden principles on recently modified files
# Examples:
#   - Check for raw SQL (grep for string concatenation in query files)
#   - Check for missing error handling (grep for empty catch blocks)
#   - Check for hardcoded secrets (grep for API keys, passwords)
#   - Check for missing audit fields (grep INSERT/UPDATE statements)
echo -e "  ${GREEN}Adapt golden principle checks to your project${NC}"

# ── 4. Harness freshness ────────────────────────────────────
echo -e "${CYAN}[4/5] Harness freshness...${NC}"
harness_issues=0

# Check that all files referenced in AGENTS.md exist
if [[ -f "AGENTS.md" ]]; then
    referenced_docs=$(grep -oP 'docs/[a-zA-Z0-9_./-]+\.(md|txt)' AGENTS.md 2>/dev/null || true)
    for doc in $referenced_docs; do
        if [[ ! -f "$doc" ]]; then
            FINDINGS+=("[harness] AGENTS.md references missing file: $doc")
            harness_issues=$((harness_issues + 1))
        fi
    done
fi

# Check key docs exist
for key_doc in docs/architecture.md docs/conventions.md docs/workflows.md docs/delegation.md docs/eval-criteria.md; do
    if [[ ! -f "$key_doc" ]]; then
        FINDINGS+=("[harness] Missing key doc: $key_doc")
        harness_issues=$((harness_issues + 1))
    fi
done

[[ $harness_issues -eq 0 ]] && echo -e "  ${GREEN}All references valid${NC}"

# ── 5. Summary ──────────────────────────────────────────────
echo ""
if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    echo -e "${GREEN}=== Sweep clean ===${NC}"
    exit 0
fi

echo -e "${YELLOW}=== ${#FINDINGS[@]} finding(s) ===${NC}"
for f in "${FINDINGS[@]}"; do echo "  $f"; done

# Append to tasks.md if it exists
if [[ -f "tasks.md" ]]; then
    echo "" >> tasks.md
    echo "## Sweep $(date '+%Y-%m-%d %H:%M')" >> tasks.md
    for f in "${FINDINGS[@]}"; do
        echo "- [ ] $f" >> tasks.md
    done
    echo -e "${GREEN}Added ${#FINDINGS[@]} item(s) to tasks.md${NC}"
fi

exit 1
```

## Adapting to Other Ecosystems

### Node.js / TypeScript
- Lint: `npx eslint . --format compact`
- Golden principles: check for `any` type usage, missing error boundaries, untyped API responses
- Doc drift: check if modified API routes have corresponding OpenAPI spec updates

### Python
- Lint: `ruff check .` or `flake8 .`
- Golden principles: check for bare `except:`, missing type hints on public functions, raw SQL
- Doc drift: check if modified modules have corresponding docstrings

### Rust
- Lint: `cargo clippy -- -W warnings`
- Golden principles: check for `unwrap()` in non-test code, missing error types
- Doc drift: check if public API changes have doc comment updates

### Go
- Lint: `golangci-lint run`
- Golden principles: check for ignored errors (`_ = func()`), missing context propagation
- Doc drift: check if exported functions have godoc comments
