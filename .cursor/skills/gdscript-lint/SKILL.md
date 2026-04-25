---
name: gdscript-lint
description: >-
  Run gdlint on GDScript files, report issues, and auto-fix them.
  Use when the user wants to lint GDScript code, check code quality,
  or fix lint errors. Triggers: 'gdlint', 'lint', 'lint check',
  '代码检查', '检查代码', 'lint修复', 'fix lint', 'gdformat'.
---

# GDScript Lint & Fix

Run `gdlint` / `gdformat` on project `.gd` files, report problems, and fix what can be fixed automatically.

## Prerequisites

`gdtoolkit` must be installed:

```bash
pip install "gdtoolkit==4.*"
```

Verify with `gdlint --version` before proceeding. If missing, install it first.

## Workflow

### 1. Determine scope

Ask yourself (do NOT ask the user unless ambiguous):

| User says | Scope |
|-----------|-------|
| A specific file path | That file only |
| "all" / "whole project" / no file mentioned | `addons/gd-plug-plus/` (project GDScript root) |
| A directory | That directory recursively |

### 2. Run gdlint

```bash
gdlint <scope>
```

Capture the full output. If exit code is 0 and no output, report all clean and stop.

### 3. Categorize issues

Group the output into two buckets:

**Auto-fixable** (fix without asking):
- `max-line-length` — break long lines
- `trailing-whitespace` — remove trailing spaces
- `mixed-tabs-and-spaces` — normalize to tabs

**Needs review** (fix then show the user what changed):
- `class-definitions-order` — reorder declarations
- `function-variable-name` / `class-variable-name` — rename identifiers
- `unused-argument` — prefix with `_`
- `max-public-methods` / `max-returns` / `max-file-lines` — refactoring needed

### 4. Auto-fix formatting issues

Run `gdformat` first to handle whitespace / line-length problems:

```bash
gdformat <file>
```

**WARNING**: `gdformat` rewrites files in-place. Only run on files with lint issues.

### 5. Fix remaining issues

For each file with remaining issues after `gdformat`:

1. Read the file
2. Apply fixes:
   - **unused-argument**: prefix the argument name with `_` (e.g. `delta` → `_delta`)
   - **class-variable-name**: rename constants to `UPPER_SNAKE_CASE` only if they are truly constant; otherwise rename to `lower_snake_case`
   - **function-variable-name**: rename `_prefixed` locals that aren't unused — remove the prefix; or rename non-snake_case vars
   - **class-definitions-order**: reorder to: `class_name` → `extends` → `signal` → `enum` → `const` → `@export var` → `var` → `@onready var` → `func _init` → `func _ready` → other `func`
   - **max-returns**: extract early-return guard clauses or use match
3. Edit the file with the fixes

### 6. Re-run gdlint

After all fixes, re-run `gdlint` on the same scope to verify. Repeat steps 4-5 if new issues appear (max 3 iterations).

### 7. Report results

Summarize:
- Total files checked
- Issues found → issues fixed → issues remaining
- List any remaining issues that need manual intervention

## Example invocation

User: "检查并修复所有 GDScript 代码"

→ Run `gdlint addons/gd-plug-plus/`
→ Run `gdformat` on files with formatting issues
→ Fix remaining lint issues in code
→ Re-run `gdlint` to confirm
→ Report summary
