# aidots

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-green.svg)](.claude-plugin/marketplace.json)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-blueviolet.svg)](https://code.claude.com/docs/en/plugins)

[🇨🇳 中文](README.zh-CN.md)

**Your dotfiles, but for AI.** Manage personalized configurations across all your AI coding tools — scan, backup, restore, and diff.

## Why aidots?

Every AI coding tool stores its own config: Claude Code has `~/.claude/`, Cursor has `~/.cursor/`, Gemini CLI has `~/.gemini/`... When you set up a new machine or want to keep configs in sync, there's no unified way to manage them all.

aidots treats your AI tool configs like dotfiles — scan what you have, back it up to a Git repo, and restore it anywhere.

## Quick Demo

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

⏭️  GitHub Copilot — no custom config found
❌ Windsurf — not installed

────────────────────
Scan complete: found 4 tools, 23 config files
```

## Features

- **Scan** — Auto-detect installed AI coding tools and list personalized config files
- **Backup** — Back up configs to a Git repo with auto-generated README, commit and push
- **Restore** — Restore configs from backup (supports new machine migration)
- **Diff** — Compare local configs against backup to see what changed

## Supported Tools

| Tool | Config Path |
|------|------------|
| Claude Code | `~/.claude/` |
| Codex CLI | `~/.codex/` |
| Cursor | `~/.cursor/` |
| Gemini CLI | `~/.gemini/` |
| Antigravity | `~/.antigravity/` |
| GitHub Copilot | `~/.copilot/` |
| Windsurf | `~/.windsurf/` |
| Aider | `~/.aider/` |

Tools not installed are automatically skipped. Adding a new tool takes one line in `tools.conf`.

## Install

```bash
/plugins marketplace add zhoulianglen/aidots
/plugins install aidots
```

## Usage

| Command | Description |
|---------|-------------|
| `/aidots` | Scan local AI tool configs |
| `/aidots backup` | Back up configs to Git repo |
| `/aidots diff` | Compare local vs backup |
| `/aidots restore` | Restore configs from backup |

On first backup, you'll be prompted to set a backup directory (default `~/dotai`). The config is saved to `~/.aidots/config.json`.

Output language follows your system locale — English by default, Chinese for `zh_*` locales.

## Security

aidots is designed to be safe by default:

- **No network calls** — Scripts only operate on local files. The only network activity is your own `git push`.
- **No secrets** — Credential files (`.env`, `auth.json`, `oauth_creds.json`, tokens, keys) are automatically excluded.
- **No telemetry** — Nothing is collected or sent anywhere.
- **Audit-friendly** — All logic is in plain bash scripts under `aidots/scripts/`. Read them yourself.

## Adding New Tools

Edit `aidots/scripts/tools.conf`, one line per tool:

```
tool_id|Display Name|config_dir|include_globs|exclude_globs
```

Example:
```
mytool|My Tool|~/.mytool|config.json,settings/**|cache/**,logs/**
```

## Requirements

- Bash 3.2+ (macOS default)
- `jq` (`brew install jq`)
- `git`

## License

MIT
