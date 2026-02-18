# aidots

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](.claude-plugin/marketplace.json)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet.svg)](https://code.claude.com/docs/en/plugins)

[🇬🇧 English](README.md)

**AI 工具的 dotfiles。** 统一管理所有 AI 编码工具的个性化配置 — 扫描、备份、恢复、对比。

## 为什么需要 aidots？

每个 AI 编码工具都有自己的配置目录：Claude Code 在 `~/.claude/`，Cursor 在 `~/.cursor/`，Gemini CLI 在 `~/.gemini/`... 换机器或多设备同步时，没有统一的方式来管理它们。

aidots 像管理 dotfiles 一样管理你的 AI 工具配置 — 扫描已有配置，备份到 Git 仓库，随时恢复。

## 快速演示

```
$ /aidots scan

🔍 AI Coding Tool Config Scan

✅ Claude Code (~/.claude)
   CLAUDE.md                          455 B
   settings.json                      787 B
   skills/ceo-skill/SKILL.md          51.0 KB
   ...
   12 files

✅ Codex CLI (~/.codex)
   config.toml                        84 B
   skills/.system/skill-creator/...
   8 files

✅ Cursor (~/.cursor)
   extensions/extensions.json         4.2 KB
   3 files

⏭️  GitHub Copilot — 无自定义配置
❌ Windsurf — 未安装

────────────────────
扫描完成: 发现 4 个工具, 23 个配置文件
```

## 功能

- **扫描** — 自动检测本机已安装的 AI 编码工具及其个性化配置
- **备份** — 将配置文件备份到 Git 仓库，自动生成 README，提交并推送
- **恢复** — 从备份恢复配置到本机（支持新机器迁移）
- **对比** — 查看本地配置与备份之间的差异

## 支持的工具

| 工具 | 配置路径 |
|------|----------|
| Claude Code | `~/.claude/` |
| Codex CLI | `~/.codex/` |
| Cursor | `~/.cursor/` |
| Gemini CLI | `~/.gemini/` |
| Antigravity | `~/.antigravity/` |
| GitHub Copilot | `~/.copilot/` |
| Windsurf | `~/.windsurf/` |
| Aider | `~/.aider/` |

未安装的工具自动跳过。添加新工具只需在 `tools.conf` 中加一行。

## 安装

```bash
/plugins marketplace add zhoulianglen/Aidots
/plugins install aidots
```

## 使用

| 命令 | 说明 |
|------|------|
| `/aidots` | 扫描本机 AI 工具配置 |
| `/aidots backup` | 备份配置到 Git 仓库 |
| `/aidots diff` | 对比本地与备份的差异 |
| `/aidots restore` | 从备份恢复配置 |

首次备份时会提示设置备份目录（默认 `~/dotai`），配置保存在 `~/.aidots/config.json`。

输出语言跟随系统 locale — `zh_*` 显示中文，其他默认英文。

## 安全性

aidots 默认就是安全的：

- **无网络请求** — 脚本只操作本地文件。唯一的网络活动是你自己的 `git push`。
- **不碰密钥** — 凭据文件（`.env`、`auth.json`、`oauth_creds.json`、token、key）自动排除。
- **无遥测** — 不收集、不发送任何数据。
- **可审计** — 所有逻辑都是 `aidots/scripts/` 下的纯 bash 脚本，随时可读。

## 添加新工具

编辑 `aidots/scripts/tools.conf`，每行格式：

```
工具ID|显示名称|配置目录|包含规则|排除规则
```

示例：
```
mytool|My Tool|~/.mytool|config.json,settings/**|cache/**,logs/**
```

## 依赖

- Bash 3.2+（macOS 默认）
- `jq`（`brew install jq`）
- `git`

## License

MIT
