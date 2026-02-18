# aidots

[🇨🇳 中文](README.zh-CN.md)

Manage personalized configurations across all your AI coding tools — scan, backup, restore, and diff.

## Features

- **Scan** — Auto-detect installed AI coding tools and their personalized configs
- **Backup** — Back up config files to a Git repo with auto-generated README, commit and push
- **Restore** — Restore configs from backup to local machine (supports new machine migration)
- **Diff** — View differences between local configs and backup

## Supported Tools

| Tool | Config Path | Backed Up Content |
|------|------------|-------------------|
| Claude Code | `~/.claude/` | CLAUDE.md, settings.json, skills/, plugins/ |
| Claude-Mem | `~/.claude-mem/` | settings.json |
| Codex CLI | `~/.codex/` | config.toml, skills/ |
| Cursor | `~/.cursor/` | extensions.json, skills-cursor/ |
| Gemini CLI | `~/.gemini/` | GEMINI.md, settings.json |
| Antigravity | `~/.antigravity/` | argv.json, extensions/ |
| GitHub Copilot | `~/.copilot/` | Config files |
| Windsurf | `~/.windsurf/` | Config files |
| Aider | `~/.aider/` | Config files |

Tools not installed are automatically skipped. Sensitive files (credentials, tokens), empty files, and system defaults are never backed up.

## Install

As a Claude Code Skill:

```
/skill install zhoulianglen/aidots
```

## Usage

```
/aidots              # Scan local AI tool configs
/aidots scan         # Same as above
/aidots backup       # Back up configs to Git repo
/aidots diff         # Compare local vs backup
/aidots restore      # Restore configs from backup
```

On first `/aidots backup`, you'll be prompted to set a backup directory (default `~/dotai`). The setting is saved to `~/.aidots/config.json`.

Output language follows your system locale — English by default, Chinese for `zh_*` locales.

## Adding New Tools

Edit `aidots/scripts/tools.conf`, one line per tool:

```
tool_id|Display Name|config_dir|include_globs|exclude_globs
```

Example:
```
mytool|My Tool|~/.mytool|config.json,settings/**|cache/**,logs/**
```

## Dependencies

- `jq` — JSON processing (`brew install jq`)
- `git` — Version control
- Bash 3.2+ (macOS default)

## License

MIT
