#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# restore.sh — Restore AI coding tool configs
# from backup repository to local machine
# Part of the aidots skill
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_CONF="${SCRIPT_DIR}/tools.conf"
CONFIG_FILE="${HOME}/.aidots/config.json"

# ── Colors ──────────────────────────────────
if [[ -t 1 ]]; then
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_RED='\033[0;31m'
    C_DIM='\033[2m'
    C_BOLD='\033[1m'
    C_CYAN='\033[0;36m'
    C_RESET='\033[0m'
else
    C_GREEN='' C_YELLOW='' C_RED='' C_DIM='' C_BOLD='' C_CYAN='' C_RESET=''
fi

# ── Globals ─────────────────────────────────
BACKUP_DIR=""
DRY_RUN=false
FORCE=false
TOOL_FILTER=""
TOTAL_RESTORED=0
TOTAL_SKIPPED=0
RESTORE_ALL=false

# ── Helpers ─────────────────────────────────

usage() {
    printf 'Usage: %s [OPTIONS]\n\n' "$(basename "$0")"
    printf 'Options:\n'
    printf '  --dir <path>      Override backup directory\n'
    printf '  --dry-run         Preview only, do not copy anything\n'
    printf '  --tool <tool_id>  Restore only a specific tool\n'
    printf '  --force           Do not ask for confirmation\n'
    printf '  --help, -h        Show this help message\n'
    exit 0
}

die() {
    printf '%bError: %s%b\n' "$C_RED" "$1" "$C_RESET" >&2
    exit 1
}

# Expand ~ to $HOME
expand_tilde() {
    local path="$1"
    if [[ "$path" == "~"* ]]; then
        printf '%s' "${HOME}${path#\~}"
    else
        printf '%s' "$path"
    fi
}

# Collapse $HOME to ~ for display
collapse_home() {
    local path="$1"
    if [[ "$path" == "${HOME}"* ]]; then
        printf '~%s' "${path#${HOME}}"
    else
        printf '%s' "$path"
    fi
}

# Verify config_dir looks reasonable (starts with ~/. or $HOME/.)
is_safe_config_dir() {
    local dir="$1"
    local expanded
    expanded=$(expand_tilde "$dir")

    # Must start with $HOME/.
    if [[ "$expanded" == "${HOME}/."* ]]; then
        return 0
    fi
    return 1
}

# Check if file is binary (non-text)
is_binary_file() {
    local filepath="$1"
    # Check by extension first (fast path)
    case "$filepath" in
        *.pb|*.png|*.jpg|*.jpeg|*.svg|*.ico|*.gif|*.woff|*.woff2|*.ttf|*.eot|*.so|*.dylib|*.o|*.a|*.bin|*.exe|*.dll)
            return 0 ;;
    esac
    # Use file command for remaining
    if file -b --mime-encoding "$filepath" 2>/dev/null | grep -q 'binary'; then
        return 0
    fi
    return 1
}

# Read backup_dir from config file
read_config_backup_dir() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    # Parse backup_dir from JSON — simple extraction, no jq dependency
    local val
    val=$(sed -n 's/.*"backup_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE")
    if [[ -n "$val" ]]; then
        printf '%s' "$val"
        return 0
    fi
    return 1
}

# ── Core Logic ──────────────────────────────

# Restore files for a single tool
restore_tool() {
    local tool_id="$1"
    local display_name="$2"
    local config_dir="$3"

    local expanded_dir
    expanded_dir=$(expand_tilde "$config_dir")

    local backup_tool_dir="${BACKUP_DIR}/.${tool_id}"

    # Check if backup directory exists for this tool
    if [[ ! -d "$backup_tool_dir" ]]; then
        return 0
    fi

    # Safety: verify config_dir looks reasonable
    if ! is_safe_config_dir "$config_dir"; then
        printf '%b⚠️  跳过 %s — 配置目录不安全：%s%b\n\n' "$C_YELLOW" "$display_name" "$config_dir" "$C_RESET"
        return 0
    fi

    # Enumerate files in backup
    local file_count=0
    local new_count=0
    local overwrite_count=0
    local skip_count=0

    # Collect file classifications
    local new_files=()
    local overwrite_files=()
    local skip_files=()

    while IFS= read -r backup_file; do
        [[ -z "$backup_file" ]] && continue

        local relpath="${backup_file#${backup_tool_dir}/}"

        # Skip binary files
        if is_binary_file "$backup_file"; then
            continue
        fi

        file_count=$((file_count + 1))
        local target="${expanded_dir}/${relpath}"

        if [[ ! -e "$target" ]]; then
            # New file
            new_files+=("$relpath")
            new_count=$((new_count + 1))
        elif cmp -s "$backup_file" "$target"; then
            # Same content
            skip_files+=("$relpath")
            skip_count=$((skip_count + 1))
        else
            # Different content — overwrite
            overwrite_files+=("$relpath")
            overwrite_count=$((overwrite_count + 1))
        fi
    done < <(find "$backup_tool_dir" -type f 2>/dev/null | sort)

    if (( file_count == 0 )); then
        return 0
    fi

    # Display header
    local actionable_count=$((new_count + overwrite_count))

    printf '%b%s (%s/)%b — %d 个文件\n' \
        "$C_BOLD" "$display_name" "$config_dir" "$C_RESET" "$file_count"

    # If everything is identical, show short message
    if (( actionable_count == 0 )); then
        printf '  ⏭️  全部一致，跳过\n\n'
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + skip_count))
        return 0
    fi

    # Show new files
    for f in "${new_files[@]}"; do
        printf '  %b🆕 新文件%b  %s\n' "$C_GREEN" "$C_RESET" "$f"
    done

    # Show overwrite files
    for f in "${overwrite_files[@]}"; do
        printf '  %b📝 覆盖%b    %s\n' "$C_YELLOW" "$C_RESET" "$f"
    done

    # Show skip files
    for f in "${skip_files[@]}"; do
        printf '  %b⏭️  跳过%b    %s%b（内容相同）%b\n' "$C_DIM" "$C_RESET" "$f" "$C_DIM" "$C_RESET"
    done

    # In dry-run mode, just tally up
    if $DRY_RUN; then
        TOTAL_RESTORED=$((TOTAL_RESTORED + actionable_count))
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + skip_count))
        printf '\n'
        return 0
    fi

    # Ask for confirmation unless --force or user previously chose "all"
    if ! $FORCE && ! $RESTORE_ALL; then
        local answer=""
        printf '恢复 %s 的 %d 个文件？(y/n/all) ' "$display_name" "$actionable_count"
        read -r answer </dev/tty
        case "$answer" in
            y|Y) ;;
            all|ALL|a|A) RESTORE_ALL=true ;;
            *)
                printf '  ⏭️  已跳过\n\n'
                TOTAL_SKIPPED=$((TOTAL_SKIPPED + file_count))
                return 0
                ;;
        esac
    fi

    # Perform the restore — copy new and overwrite files
    local restored=0

    for f in "${new_files[@]}" "${overwrite_files[@]}"; do
        local src="${backup_tool_dir}/${f}"
        local dst="${expanded_dir}/${f}"
        local dst_dir
        dst_dir=$(dirname "$dst")

        # Create parent directories
        mkdir -p "$dst_dir"

        # Copy file preserving permissions
        cp -p "$src" "$dst"
        restored=$((restored + 1))
    done

    printf '  %b✅ 已恢复 %d 个文件%b\n\n' "$C_GREEN" "$restored" "$C_RESET"

    TOTAL_RESTORED=$((TOTAL_RESTORED + restored))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + skip_count))
}

# ── Main ────────────────────────────────────

main() {
    # Parse arguments
    while (( $# > 0 )); do
        case "$1" in
            --dir)
                [[ -z "${2:-}" ]] && die "--dir requires a path argument"
                BACKUP_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --tool)
                [[ -z "${2:-}" ]] && die "--tool requires a tool_id argument"
                TOOL_FILTER="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done

    # Verify tools.conf exists
    if [[ ! -f "$TOOLS_CONF" ]]; then
        die "tools.conf not found at ${TOOLS_CONF}"
    fi

    # Determine backup directory
    if [[ -z "$BACKUP_DIR" ]]; then
        if ! BACKUP_DIR=$(read_config_backup_dir); then
            die "未找到备份目录。请使用 --dir <path> 指定，或在 ${CONFIG_FILE} 中配置 backup_dir。"
        fi
    fi

    # Expand tilde in backup_dir
    BACKUP_DIR=$(expand_tilde "$BACKUP_DIR")

    # Verify backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        die "备份目录不存在：${BACKUP_DIR}"
    fi

    # Safety: never restore to / or $HOME directly
    if [[ "$BACKUP_DIR" == "/" || "$BACKUP_DIR" == "$HOME" ]]; then
        die "备份目录不安全：${BACKUP_DIR}"
    fi

    # Header
    local display_backup
    display_backup=$(collapse_home "$BACKUP_DIR")
    if $DRY_RUN; then
        printf '\n%b🔄 aidots 配置恢复（预览模式）%b\n\n' "$C_BOLD" "$C_RESET"
    else
        printf '\n%b🔄 aidots 配置恢复%b\n\n' "$C_BOLD" "$C_RESET"
    fi
    printf '备份目录：%s\n\n' "$display_backup"

    # Scan backup directory for .tool_id/ directories
    local found_any_tool=false

    # If --tool is specified, validate it exists in tools.conf
    if [[ -n "$TOOL_FILTER" ]]; then
        local tool_found=false
        while IFS='|' read -r tool_id display_name config_dir include_globs exclude_globs; do
            [[ -z "$tool_id" || "$tool_id" == \#* ]] && continue
            if [[ "$tool_id" == "$TOOL_FILTER" ]]; then
                tool_found=true
                break
            fi
        done < "$TOOLS_CONF"
        if ! $tool_found; then
            die "工具 '${TOOL_FILTER}' 未在 tools.conf 中定义"
        fi
    fi

    # Process each tool from tools.conf
    while IFS='|' read -r tool_id display_name config_dir include_globs exclude_globs; do
        [[ -z "$tool_id" || "$tool_id" == \#* ]] && continue

        # If filtering, skip non-matching tools
        if [[ -n "$TOOL_FILTER" && "$tool_id" != "$TOOL_FILTER" ]]; then
            continue
        fi

        # Check if backup exists for this tool
        if [[ -d "${BACKUP_DIR}/.${tool_id}" ]]; then
            found_any_tool=true
            restore_tool "$tool_id" "$display_name" "$config_dir"
        fi
    done < "$TOOLS_CONF"

    # Warn about backup directories not in tools.conf
    while IFS= read -r backup_subdir; do
        [[ -z "$backup_subdir" ]] && continue
        local dirname
        dirname=$(basename "$backup_subdir")

        # Only process directories starting with .
        [[ "$dirname" != .* ]] && continue

        local bid="${dirname#.}"

        # Skip if already processed (exists in tools.conf)
        local known=false
        while IFS='|' read -r conf_id _rest; do
            [[ -z "$conf_id" || "$conf_id" == \#* ]] && continue
            if [[ "$conf_id" == "$bid" ]]; then
                known=true
                break
            fi
        done < "$TOOLS_CONF"

        if ! $known; then
            printf '%b⚠️  发现未知工具备份：%s（不在 tools.conf 中，已跳过）%b\n\n' \
                "$C_YELLOW" "$dirname" "$C_RESET"
        fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    if ! $found_any_tool; then
        printf '%b未在备份目录中找到任何工具配置%b\n\n' "$C_YELLOW" "$C_RESET"
        exit 0
    fi

    # Summary
    printf '────────────────────\n'
    if $DRY_RUN; then
        printf '[预览] 将恢复 %d 个文件，跳过 %d 个\n\n' \
            "$TOTAL_RESTORED" "$TOTAL_SKIPPED"
    else
        printf '恢复完成：恢复 %d 个文件，跳过 %d 个\n\n' \
            "$TOTAL_RESTORED" "$TOTAL_SKIPPED"
    fi
}

main "$@"
