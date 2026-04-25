# gd-plug-plus

**English | [中文](README_zh.md)**

A plugin manager for Godot 4.x with built-in editor UI. Manage addon installation, updates, and version pinning — all from within the editor, no config scripts needed.

## Features

- **Browse & Install** — discover addons from the community index or search by Git URL
- **GitHub Releases** — install addons directly from GitHub / Codeberg / Gitee Releases (GDExtensions, pre-built binaries, etc.)
- **Per-plugin versioning** — pin each addon to a branch, tag, or specific commit independently
- **One-click updates** — check for updates and apply them in batch or per-addon
- **Multi-plugin repos** — repos containing multiple addons are detected and managed individually
- **Conflict detection** — warns when an addon directory already exists, with overwrite/cancel options
- **API Token management** — configure platform tokens (PAT or GitHub Device Flow OAuth) once, shared across all projects
- **Self-update** — gd-plug-plus tracks and updates itself through its own UI
- **Legacy migration** — auto-imports existing `plug.gd` + `index.cfg` setups

## Requirements

- **Godot 4.x** (tested with 4.4+)
- **git** in system `PATH`

## Installation

Copy `addons/gd-plug-plus/` into your project's `addons/` directory, then enable the plugin in **Project → Project Settings → Plugins**.

## Usage

1. Open the **gd-plug-plus** panel in the editor
2. **Install New** tab → browse the Available list or enter a Git URL and search
3. Select addons, optionally change branch/tag, click **Install Selected**
4. **Installed** tab → check versions, update, switch branches, or uninstall

All state is stored in `addons.json` — no `plug.gd` file needed.

### Installing from Releases

Some addons (especially GDExtensions) are distributed as pre-built binaries via GitHub Releases rather than as source code in the repository tree.

1. Enter the repository URL and tick the **Search Releases** checkbox before searching
2. gd-plug-plus queries the platform's Release API, matches archive assets (`.zip`, `.tar.gz`, etc.) automatically, and presents them alongside source-based results
3. Select the desired release asset and click **Install Selected** — the asset is downloaded, extracted, and copied into your project
4. Installed release addons are marked with `[R]` in the branch/tag column and can be switched to a different release tag in-place

> If the platform token is not configured, gd-plug-plus will prompt you to set one up before the release search proceeds (see [Token Configuration](#token-configuration) below).

### Token Configuration

Platform API tokens are required for Release searches and downloads (to avoid rate limits and access private repos). Tokens are stored in an **encrypted file outside the project** and shared across all Godot projects on the same machine.

**Settings tab → Auth** provides per-platform token management:

| Platform | Auth Methods | How to obtain |
|---|---|---|
| GitHub | Device Flow OAuth / PAT | [github.com/settings/tokens](https://github.com/settings/tokens) |
| Codeberg | PAT | [codeberg.org/user/settings/applications](https://codeberg.org/user/settings/applications) |
| Gitee | PAT | [gitee.com/profile/personal_access_tokens](https://gitee.com/profile/personal_access_tokens) |

- **Device Flow** (GitHub only): click "Device Flow Login", a code appears — open the browser link, enter the code, authorize, and the token is saved automatically.
- **PAT** (all platforms): paste a Personal Access Token into the input field and click Save.
- **Validate**: verifies the token is still valid via an API call.

Token file location: `~/.config/gd-plug-plus/tokens.dat` (Linux/macOS) or `%APPDATA%/gd-plug-plus/tokens.dat` (Windows).

## How It Works

### Search Priority

When you search a URL, gd-plug-plus looks up data in this order:

1. **Local cache** (`.plugged/`) — instant, no network
2. **Plugin index** (`addon_index.json`) — instant, no network
3. **Remote** — `git ls-remote` + shallow clone

### Data Files

| File | Role |
|---|---|
| `addons.json` | Tracks installed addons (user data, gitignored) |
| `addon_index.json` | Community plugin catalog (ships with the plugin, updated via self-update) |

### Self-Update

gd-plug-plus registers itself in `addons.json` on first run. Updates flow through the same mechanism as any other addon. After self-update, `addon_index.json` is refreshed automatically and a project reload is prompted.

## Contributing to the Plugin Index

The Available list in the Install New tab is powered by `addon_index.json`. To add a plugin:

1. Fork the [gd-plug-plus repo](https://github.com/huzz-open/gd-plug-plus)
2. Edit `addons/gd-plug-plus/addon_index.json`
3. Add an entry following the format below
4. Submit a Pull Request

### Format

`addon_index.json` is a JSON array. Each element represents a repository:

```json
[
  {
    "url": "https://github.com/user/repo",
    "addons": [
      {
        "name": "My Plugin",
        "description": "A short description.",
        "addon_dir": "addons/my_plugin",
        "author": "Author Name",
        "type": "plugin",
        "branch": "main"
      }
    ]
  }
]
```

### Fields

| Field | Required | Description |
|---|---|---|
| `url` | Yes | Full git clone URL |
| `addons` | Yes | Array of addons in this repo |
| `addons[].name` | Yes | Display name |
| `addons[].addon_dir` | Yes | Install target directory (e.g. `addons/my_plugin`) |
| `addons[].branch` | Yes | Default branch (e.g. `main`) |
| `addons[].description` | No | One-line summary |
| `addons[].author` | No | Author name |
| `addons[].type` | No | `plugin` (default) or `gdextension` |

For repos with multiple addons, list each as a separate element in the `addons` array.

## GDScript Linting

This project uses [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) (`gdlint`) for static analysis of GDScript code.

### Install

```bash
pip3 install "gdtoolkit==4.*"
```

### Manual Usage

Lint a single file:

```bash
gdlint addons/gd-plug-plus/plugin.gd
```

Lint all `.gd` files in the project:

```bash
gdlint addons/gd-plug-plus/
```

### Cursor Hook (automatic)

A Cursor hook is configured in `.cursor/hooks.json`. After every `.gd` file edit, `gdlint` runs automatically and reports any issues in the agent context. No manual action required — just edit code and the hook handles the rest.

## Acknowledgements

gd-plug-plus is inspired by two projects from [imjp94](https://github.com/imjp94):

- [gd-plug](https://github.com/imjp94/gd-plug) — Git-based plugin manager for Godot (MIT)
- [gd-plug-ui](https://github.com/imjp94/gd-plug-ui) — Editor UI for gd-plug (MIT)

## License

[Apache-2.0](LICENSE)
