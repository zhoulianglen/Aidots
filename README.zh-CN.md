# aidots

[🇬🇧 English](README.md)

AI Coding 工具个性化配置管理 — 扫描、备份、恢复、对比你的 AI 编码工具配置。

## 功能

- **扫描** — 自动检测本机已安装的 AI 编码工具及其个性化配置
- **备份** — 将配置文件备份到 Git 仓库，自动生成 README，提交并推送
- **恢复** — 从备份仓库恢复配置到本机（支持新机器迁移）
- **对比** — 查看本地配置与备份之间的差异

## 支持的工具

| 工具 | 配置路径 | 备份内容 |
|------|----------|----------|
| Claude Code | `~/.claude/` | CLAUDE.md、settings.json、skills/、plugins/ |
| Claude-Mem | `~/.claude-mem/` | settings.json |
| Codex CLI | `~/.codex/` | config.toml、skills/ |
| Cursor | `~/.cursor/` | extensions.json、skills-cursor/ |
| Gemini CLI | `~/.gemini/` | GEMINI.md、settings.json |
| Antigravity | `~/.antigravity/` | argv.json、extensions/ |
| GitHub Copilot | `~/.copilot/` | 配置文件 |
| Windsurf | `~/.windsurf/` | 配置文件 |
| Aider | `~/.aider/` | 配置文件 |

未安装的工具自动跳过。敏感文件（凭据、token）、空文件和系统默认内容不会被备份。

## 安装

作为 Claude Code Skill 安装：

```
/skill install zhoulianglen/aidots
```

## 使用

```
/aidots              # 扫描本机 AI 工具配置
/aidots scan         # 同上
/aidots backup       # 备份配置到 Git 仓库
/aidots diff         # 对比本地与备份的差异
/aidots restore      # 从备份恢复配置
```

首次执行 `/aidots backup` 时会提示设置备份目录（默认 `~/dotai`），配置保存在 `~/.aidots/config.json`。

输出语言跟随系统 locale — `zh_*` 显示中文，其他默认英文。

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

- `jq` — JSON 处理（`brew install jq`）
- `git` — 版本控制
- Bash 3.2+（macOS 默认）

## License

MIT
