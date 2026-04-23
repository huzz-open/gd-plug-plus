# gd-plug-plus

**[English](README.md) | 中文**

Godot 4.x 插件管理器，内置编辑器 UI。在编辑器内完成插件的安装、更新和版本锁定，无需编写配置脚本。

## 功能

- **浏览与安装** — 从社区插件目录发现插件，或通过 Git URL 搜索
- **插件级版本控制** — 每个插件可独立锁定到分支、标签或指定 commit
- **一键更新** — 批量或逐个检查并应用更新
- **多插件仓库** — 自动检测仓库内的多个插件，独立管理
- **冲突检测** — 目录已存在时弹出提示，支持覆盖或取消
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

## 致谢

gd-plug-plus 参考了 [imjp94](https://github.com/imjp94) 的两个项目：

- [gd-plug](https://github.com/imjp94/gd-plug) — Godot git 插件管理器（MIT）
- [gd-plug-ui](https://github.com/imjp94/gd-plug-ui) — gd-plug 编辑器 UI（MIT）

## 许可证

[Apache-2.0](LICENSE)
