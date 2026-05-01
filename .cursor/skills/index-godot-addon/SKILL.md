---
name: index-godot-addon
description: >-
  Clone Godot addon git repos, scan for plugins/extensions, and add them to
  addon_index.json. Use when the user provides one or more git URLs
  (https://github.com/..., https://github.com/...*.git, or
  git@github.com:...*.git) and wants to add them to the addon catalog.
  Triggers: 'add addon', 'add plugin', 'register addon',
  'register plugin'.
---

# Index Godot Addon

Add Godot addon repos to `addons/gd-plug-plus/addon_index.json` — the community
catalog used by the gd-plug-plus "Available" tab.

Supports batch processing — the user may provide multiple URLs at once.

## Supported URL Formats

All three formats must be accepted:
- `https://github.com/user/repo`
- `https://github.com/user/repo.git`
- `git@github.com:user/repo.git`

## addon_index.json Schema

```json
[
  {
    "url": "https://github.com/user/repo",
    "with_release": true,
    "release_asset_pattern": "addon-*-gdextension-*.zip",
    "addons": [
      {
        "name": "Plugin Name",
        "description": "Short description",
        "addon_dir": "addons/plugin_name",
        "author": "Author Name",
        "type": "plugin",
        "branch": "main"
      }
    ]
  }
]
```

Field notes:
- `type`: `"plugin"` for plugin.cfg, `"extension"` for *.gdextension
- `addon_dir`: relative path from repo root (e.g. `addons/my_addon`)
- `branch`: the repo's default branch (usually `main` or `master`)
- `with_release` (optional, default `true`): set to `false` to skip Release API queries for this repo
- `release_asset_pattern` (optional): glob pattern to match Release asset filenames (e.g. `godotsteam-*-gdextension-*.zip`). If omitted, AssetMatcher uses default heuristics (archives excluding "source code")

### Extension indexing notes

GDExtension addons typically distribute pre-compiled binaries via GitHub/Codeberg/Gitee Releases rather than source code in the repo. When indexing an Extension:

1. The repo source may NOT contain `*.gdextension` files — they are bundled inside Release archives
2. Set `with_release: true` (default) so the UI can search Release assets
3. Provide `release_asset_pattern` if the release archive names follow a specific pattern
4. Set `type: "extension"` for the addon entry

## Workflow

### Step 0: Detect user language

Identify the language the user is currently using (e.g. Chinese,
English, Japanese, etc.) from their message. **All subsequent
interaction with the user** — including status messages, result
summaries, AskQuestion prompts, option labels, warnings, error
messages, and the final summary line — MUST be in this same language.

Code-level content (repo names, addon names, URLs, addon_dir, JSON
field names) stays in their original form and is never translated.

### Processing strategy

The user may provide one or more git URLs.

**Single URL**: Execute steps 1–7 sequentially.

**Multiple URLs**: Maximize parallelism to save time.
- **Step 1 (Clone)**: Launch all `git clone` commands **in parallel**
  (multiple Shell tool calls in one message).
- **Step 2–4 (Branch detect + Scan + Validate)**: After all clones
  finish, run these for each repo. Can use **parallel subagents**
  (Task tool) for each repo, or parallel Shell calls.
- **Step 5 (Star count)**: Call **WebFetch in parallel** for all repos
  (multiple WebFetch calls in one message).
- **Step 6 (Build entries)**: Collect all results.
- **Step 7 (Show + Confirm)**: Show one unified summary table for all
  repos, then ask user to multi-select once.

### Step 1: Clone to temp directory

For **each** URL:

```bash
TMPDIR=$(mktemp -d)
git clone --depth=1 <URL> "$TMPDIR/repo"
```

### Step 2: Detect default branch

```bash
cd "$TMPDIR/repo"
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'
```

If that fails, fall back to:
```bash
git rev-parse --abbrev-ref HEAD
```

If both fail, default to `"main"`.

### Step 3: Scan for addons

Search the cloned repo for **all** `plugin.cfg` and `*.gdextension` files.

**Skip rules** (must match the engine's own EditorFileSystem behavior —
see `GitManager._should_skip_directory` in the codebase):
- Directories starting with `.` (covers `.git`, `.godot`, etc.)
- Directories containing `.gdignore`
- Directories containing `project.godot` (nested Godot projects)

```bash
find "$TMPDIR/repo" \
  -name ".git" -prune -o \
  -name ".godot" -prune -o \
  -name ".*" -prune -o \
  \( -name "plugin.cfg" -o -name "*.gdextension" \) -print
```

Then for each found file, verify its parent directory does NOT contain
`.gdignore` or `project.godot` — if it does, skip it.

#### Parsing plugin.cfg

INI format under `[plugin]` section:
```ini
[plugin]
name="My Plugin"
description="Does something useful"
author="Some Author"
version="1.0.0"
script="plugin.gd"
```

Extract: `name`, `description`, `author`. Ignore `version` and `script` for the index.

#### Parsing .gdextension

Use the filename (without extension) as `name`. Set description to
`"GDExtension"`, author to `""`.

#### Computing addon_dir

`addon_dir` = the path from repo root to the directory containing
plugin.cfg (or the .gdextension file), using forward slashes.

Example: if plugin.cfg is at `addons/my_plugin/plugin.cfg`,
then `addon_dir = "addons/my_plugin"`.

If plugin.cfg is at repo root, `addon_dir = "addons/<sanitized_name>"` where
`<sanitized_name>` is the plugin name lowercased with spaces/special chars replaced by underscores
(mirrors `GitManager._sanitize_addon_name`).

### Step 4: Validate scan results

After scanning, classify the structure of each found addon
(mirrors `GitManager._classify_structure`):

| Structure | Condition | Action |
|-----------|-----------|--------|
| `standard` | `addon_dir` starts with `addons/` | Normal — proceed |
| `root_level` | plugin.cfg at repo root | Warn user: addon sits at repo root, not under `addons/` |
| `no_addons` | cfg exists but not under any `addons/` path | Warn user: non-standard layout |
| `deep_nested` | `addons/` appears but not at the start | Warn user: unusual nesting |

**If NO plugin.cfg and NO .gdextension found at all**: the repo is not
a valid Godot addon. Print a warning and **skip this repo entirely** —
do not ask the user, do not add it to addon_index.json. Mark it as
"failed" in the batch summary and move on to the next URL.

### Step 5: Fetch star count

**MANDATORY — DO NOT SKIP.** You must call **WebFetch** yourself for
every successfully scanned repo. Do NOT delegate this to a subagent.
Star count is for display only, not written to addon_index.json.

If you show results with `Stars: N/A` but the repo URL is a valid
web page, you have failed this step.

#### 5a: Build the web URL

Use the normalized https URL (same as addon_index.json):
- `git@github.com:user/repo.git` → `https://github.com/user/repo`
- `https://gitee.com/user/repo.git` → `https://gitee.com/user/repo`
- Any host: strip `.git` suffix, convert SSH to HTTPS

#### 5b: Execute WebFetch

Call the WebFetch tool directly. Example:
```
WebFetch(url: "https://gitee.com/mirrors_nathanhoad/godot_dialogue_manager")
```

When processing multiple URLs, call WebFetch **in parallel** (multiple
tool calls in one message) while clone/scan steps are complete.

#### 5c: Extract star count from the returned content

WebFetch returns markdown-converted text, but the original HTML
attributes are often preserved in the output. Use the Grep tool or
string search on the fetched content with the regexes below.

Try each platform regex **in order**. Use the first match.

**GitHub** (`github.com`):
HTML source:
```html
<span id="repo-stars-counter-unstar" ... title="3,497" ...>3.5k</span>
```
Regex to run on fetched content:
```
aria-label="(\d[\d,]*)\s+users?\s+starred
```
Extract capture group 1, strip commas → integer. This matches the
`aria-label` attribute which always has the exact number.

Fallback regex:
```
title="([\d,]+)"[^>]*class="Counter
```

**Codeberg / Gitea / Forgejo** (`codeberg.org`, self-hosted):
HTML source:
```html
<a ... href="/user/repo/stars" aria-label="107次点赞">107</a>
```
Regex:
```
aria-label="(\d+)[^"]*"[^>]*href="[^"]*/stars"
```
Extract capture group 1.

Fallback regex:
```
href="[^"]*/stars"[^>]*>\s*(\d+)\s*<
```

**Gitee** (`gitee.com`):
HTML source:
```html
<a class="... action-social-count ..." title="7" href="/.../stargazers">7</a>
```
Regex:
```
title="(\d+)"[^>]*href="[^"]*/stargazers"
```
Extract capture group 1.

Fallback regex:
```
href="[^"]*/stargazers"[^>]*>\s*(\d+)\s*<
```

**GitLab** (`gitlab.com`, self-hosted):
GitLab uses client-side rendering — star count is usually absent
from the initial HTML. Run a single API fallback:
```bash
curl -s "https://gitlab.com/api/v4/projects/{owner}%2F{repo}?simple=true"
```
Regex on JSON response:
```
"star_count"\s*:\s*(\d+)
```
If this also fails → `N/A`.

**Unknown platforms** (fallback chain):
Try these regexes in order on the fetched content:
1. `aria-label="(\d[\d,]*)[^"]*star`  (aria-label with star keyword)
2. `href="[^"]*/stars?"[^>]*>\s*(\d+)` (link to /star or /stars)
3. `href="[^"]*/stargazers"[^>]*>\s*(\d+)` (link to /stargazers)
4. Nothing matched → `N/A`.

#### 5d: Failure handling

Only set `N/A` if WebFetch itself errors out or the content genuinely
has no star-related data. Never let this step block the workflow.

### Step 6: Build the entry

For each repo URL, construct one entry:

```json
{
  "url": "<normalized-url>",
  "addons": [
    {
      "name": "<from plugin.cfg>",
      "description": "<from plugin.cfg>",
      "addon_dir": "<computed relative path>",
      "author": "<from plugin.cfg>",
      "type": "plugin",
      "branch": "<default branch>"
    }
  ]
}
```

A single repo may contain multiple addons — include all of them
in the `addons` array.

### Step 7: Show results and confirm

Print the formatted summary (see Output section) for all scanned repos.
Then **stop and ask the user for explicit confirmation** before writing.

Do NOT write to addon_index.json until the user confirms.

Use the **AskQuestion tool** to let the user confirm. Always use
`allow_multiple: true` so the user can multi-select. Each option =
one successfully scanned repo, using the **full normalized URL** as
the label (e.g. `https://github.com/user/repo`, not `user/repo`).
Failed repos are not listed as options.

Always include a **cancel option** (e.g. "Cancel / Do not add any").
If the user selects only the cancel option, skip writing entirely.

The question prompt and all option labels must be written in the
**same language the user is currently using** in the conversation.
Keep the prompt neutral and factual — do NOT make assumptions or
judgments (e.g. don't say "this is a mirror").

### Step 8: Update addon_index.json (only after confirmation)

1. Read `addons/gd-plug-plus/addon_index.json`
2. Check for duplicates by **exact normalized URL** — only the same URL
   counts as a duplicate. Different hosts (e.g. GitHub vs Gitee mirror
   of the same project) are treated as **different entries**
3. If the exact URL already exists, ask the user whether to update or skip
4. Append the new entry (or update existing)
5. Write back with tab indentation (match existing formatting)

**Same-name note**: If the scanned addon name matches an existing
entry in addon_index.json but under a different URL, show in the
output table's Note column:
`Same-name addon exists at <existing-url>`
— state the fact only, do not speculate on the reason.

### Step 9: Cleanup

```bash
rm -rf "$TMPDIR"
```

## URL Normalization

The `url` stored in addon_index.json should always be the **https** form
**without** `.git` suffix: `https://github.com/user/repo`.

Normalization rules:
1. `git@github.com:user/repo.git` → `https://github.com/user/repo`
2. `https://github.com/user/repo.git` → `https://github.com/user/repo`
3. `https://github.com/user/repo` → as-is
4. Strip trailing `/`
5. Compare case-insensitively when checking duplicates

## Output

After all repos are processed, show a formatted summary.

### Single-addon repo (most common)

```
Repo:        https://github.com/user/repo
Addon:       Plugin Name
Description: A powerful nonlinear dialogue system
Type:        plugin
Branch:      main
addon_dir:   addons/plugin_name
Author:      Author Name
Stars:       1234
Note:        -
```

If there is a same-name match or other warning, show it in the Note line:
```
Note:        Same-name addon exists at https://github.com/other-user/repo
```

### Multi-addon repo

```
Repo:   https://github.com/user/repo
Stars:  567

| # | Addon | Description | Type | addon_dir | Author |
|---|-------|-------------|------|-----------|--------|
| 1 | Plugin A | Does X | plugin | addons/plugin_a | Author A |
| 2 | Extension B | GDExtension | extension | addons/ext_b | - |
```

### Batch (multiple URLs)

Use a **single unified table** so all repos are visible at a glance.
The `Note` column carries mirror hints, structure warnings, etc.
Use `-` when there is nothing to note.

```
| # | Repo | Addon | Description | Type | Branch | addon_dir | Author | Stars | Note |
|---|------|-------|-------------|------|--------|-----------|--------|-------|------|
| 1 | https://github.com/user/repo-a | Plugin A | Does X | plugin | main | addons/plugin_a | Author A | 1234 | - |
| 2 | https://github.com/user/repo-b | Plugin B | Does Y | plugin | master | addons/plugin_b | Author B | 567 | - |
| 3 | https://gitee.com/mirror/repo-a | Plugin A | Does X | plugin | main | addons/plugin_a | Author A | N/A | Same-name addon exists at https://github.com/user/repo-a |

Failed repos (clone error or no addon found):

| # | Repo | Reason |
|---|------|--------|
| 4 | https://github.com/user/repo-c | Clone failed: timeout |
| 5 | https://github.com/user/repo-d | No plugin.cfg or .gdextension found |
```

For repos containing multiple addons, list each addon as a separate
row in the table, with the `Repo` and `Stars` columns spanning
(or repeating) for each addon row.

### Summary line

Always end with a one-line summary:
`addon_index.json: X to add, Y to update, Z failed.`

## Error Handling

- **git clone fails**: Report the error, mark as "failed", continue to
  next URL. Do not ask the user. Do NOT try alternative download methods
  (wget, curl archive, etc.) — only `git clone` is allowed
- **git clone timeout**: Retry once. If it fails again, report the
  timeout error and mark as "failed"
- **No plugin.cfg or .gdextension found**: Mark as "failed", skip
  automatically. Do not ask the user whether to force-add
- **Duplicate URL**: Ask user whether to update or skip
- **Non-standard addon structure**: Warn but still include in results
- **Star count fetch fails**: Silently fall back to `N/A`, do not block
