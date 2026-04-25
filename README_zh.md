# gd-plug-plus

**[English](README.md) | 中文**

Godot 4.x 插件管理器，内置编辑器 UI。在编辑器内完成插件的安装、更新和版本锁定，无需编写配置脚本。

## 功能

- **浏览与安装** — 从社区插件目录发现插件，或通过 Git URL 搜索
- **Release 安装** — 直接从 GitHub / Codeberg / Gitee Releases 安装扩展（GDExtension、预编译二进制文件等）
- **插件级版本控制** — 每个插件可独立锁定到分支、标签或指定 commit
- **一键更新** — 批量或逐个检查并应用更新
- **多插件仓库** — 自动检测仓库内的多个插件，独立管理
- **冲突检测** — 目录已存在时弹出提示，支持覆盖或取消
- **API Token 管理** — 配置平台令牌（PAT 或 GitHub Device Flow OAuth），一次配置全局共享
- **自更新** — gd-plug-plus 通过自身 UI 跟踪和更新自己
- **旧版迁移** — 自动导入已有的 `plug.gd` + `index.cfg` 配置

## 环境要求

- **Godot 4.x**（4.4+ 测试通过）
- **git** 已添加到系统 `PATH`

## 安装

将 `addons/gd-plug-plus/` 复制到项目的 `addons/` 目录，然后在 **项目 → 项目设置 → 插件** 中启用。

## 使用方法

1. 打开编辑器中的 **gd-plug-plus** 面板
2. **安装新扩展** 选项卡 → 浏览可用列表，或输入 Git URL 搜索
3. 选择插件，可选修改分支/标签，点击 **安装选中**
4. **已安装** 选项卡 → 检查版本、更新、切换分支或卸载

所有状态存储在 `addons.json` 中，无需 `plug.gd` 文件。

### 从 Release 安装

部分扩展（尤其是 GDExtension）以预编译二进制的形式通过 GitHub Releases 发布，而非以源码形式存在于仓库目录中。

1. 输入仓库 URL，搜索前勾选 **搜索 Release** 复选框
2. gd-plug-plus 会查询平台 Release API，自动匹配压缩包资产（`.zip`、`.tar.gz` 等），与源码搜索结果一起展示
3. 选择目标 Release 资产，点击 **安装选中** — 资产将被下载、解压并复制到项目中
4. 已安装的 Release 扩展在分支/标签列会标记 `[R]`，支持原地切换到其他 Release 标签

> 如果未配置平台令牌，gd-plug-plus 会在 Release 搜索前提示你进行配置（参见下方 [Token 配置](#token-配置)）。

### Token 配置

Release 搜索和下载需要平台 API 令牌（避免速率限制，同时支持访问私有仓库）。令牌存储在**项目外部的加密文件**中，同一台机器上的所有 Godot 项目共享。

**设置选项卡 → 认证** 提供各平台的令牌管理：

| 平台 | 认证方式 | 获取方式 |
|---|---|---|
| GitHub | Device Flow OAuth / PAT | [github.com/settings/tokens](https://github.com/settings/tokens) |
| Codeberg | PAT | [codeberg.org/user/settings/applications](https://codeberg.org/user/settings/applications) |
| Gitee | PAT | [gitee.com/profile/personal_access_tokens](https://gitee.com/profile/personal_access_tokens) |

- **Device Flow**（仅 GitHub）：点击"Device Flow 登录"，界面显示一组验证码 — 打开浏览器链接、输入验证码、授权后令牌自动保存。
- **PAT**（所有平台）：将 Personal Access Token 粘贴到输入框并点击保存。
- **验证**：通过 API 调用检测令牌是否仍然有效。

令牌文件位置：`~/.config/gd-plug-plus/tokens.dat`（Linux/macOS）或 `%APPDATA%/gd-plug-plus/tokens.dat`（Windows）。

## 工作原理

### 搜索优先级

搜索 URL 时，gd-plug-plus 按以下顺序查找数据：

1. **本地缓存**（`.plugged/`）— 即时，无需网络
2. **插件目录**（`addon_index.json`）— 即时，无需网络
3. **远程** — `git ls-remote` + 浅克隆

### 数据文件

| 文件 | 作用 |
|---|---|
| `addons.json` | 跟踪已安装的插件（用户数据，已 gitignore） |
| `addon_index.json` | 社区插件目录（随插件分发，通过自更新保持最新） |

### 自更新

gd-plug-plus 在首次运行时将自身注册到 `addons.json`。更新机制与其他插件完全相同。自更新后 `addon_index.json` 会自动刷新，同时提示重新加载项目。

## 贡献插件目录

安装新扩展选项卡中的"可用"列表由 `addon_index.json` 驱动。添加插件的步骤：

1. Fork [gd-plug-plus 仓库](https://github.com/huzz-open/gd-plug-plus)
2. 编辑 `addons/gd-plug-plus/addon_index.json`
3. 按以下格式添加条目
4. 提交 Pull Request

### 格式

`addon_index.json` 是一个 JSON 数组，每个元素代表一个仓库：

```json
[
  {
    "url": "https://github.com/user/repo",
    "addons": [
      {
        "name": "我的插件",
        "description": "一行简短描述。",
        "addon_dir": "addons/my_plugin",
        "author": "作者",
        "type": "plugin",
        "branch": "main"
      }
    ]
  }
]
```

### 字段说明

| 字段 | 必需 | 说明 |
|---|---|---|
| `url` | 是 | 完整的 git 克隆地址 |
| `addons` | 是 | 该仓库中的插件数组 |
| `addons[].name` | 是 | 显示名称 |
| `addons[].addon_dir` | 是 | 安装目标目录（如 `addons/my_plugin`） |
| `addons[].branch` | 是 | 默认分支（如 `main`） |
| `addons[].description` | 否 | 一行描述 |
| `addons[].author` | 否 | 作者名 |
| `addons[].type` | 否 | `plugin`（默认）或 `gdextension` |

多插件仓库中，每个插件作为 `addons` 数组中的独立元素列出。

## GDScript 代码检查

本项目使用 [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit)（`gdlint`）对 GDScript 代码进行静态分析。

### 安装

```bash
pip3 install "gdtoolkit==4.*"
```

### 手动检查

检查单个文件：

```bash
gdlint addons/gd-plug-plus/plugin.gd
```

检查项目中所有 `.gd` 文件：

```bash
gdlint addons/gd-plug-plus/
```

### Cursor Hook（自动检查）

`.cursor/hooks.json` 中配置了 Cursor Hook。每次编辑 `.gd` 文件后，`gdlint` 会自动运行并将问题反馈到 agent 上下文中，无需手动操作。

## 致谢

gd-plug-plus 参考了 [imjp94](https://github.com/imjp94) 的两个项目：

- [gd-plug](https://github.com/imjp94/gd-plug) — Godot git 插件管理器（MIT）
- [gd-plug-ui](https://github.com/imjp94/gd-plug-ui) — gd-plug 编辑器 UI（MIT）

## 许可证

[Apache-2.0](LICENSE)
