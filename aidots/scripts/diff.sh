#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# diff.sh — Compare local AI tool configs with backup
# Part of the aidots skill
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${HOME}/.aidots/config.json"

# ── Colors ──────────────────────────────────
if [[ -t 1 ]]; then
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_RED='\033[0;31m'
    C_DIM='\033[2m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_GREEN='' C_YELLOW='' C_RED='' C_DIM='' C_BOLD='' C_RESET=''
fi

# ── Locale ───────────────────────────────────
detect_locale() {
    local lang="${LANG:-${LC_ALL:-${LANGUAGE:-en}}}"
    case "$lang" in
        zh*) printf 'zh' ;;
        *)   printf 'en' ;;
    esac
}

LOCALE=$(detect_locale)

# ── Messages ─────────────────────────────────
if [[ "$LOCALE" == "zh" ]]; then
    MSG_ERROR="错误："
    MSG_DIR_REQUIRES_PATH="--dir 需要指定路径参数"
    MSG_UNKNOWN_OPTION="未知参数："
    MSG_CONFIG_NOT_FOUND="未找到配置文件 %s，请先执行 /aidots backup 或使用 --dir 指定备份目录"
    MSG_JQ_REQUIRED_CONFIG="需要 jq 来解析配置文件，请先安装：brew install jq"
    MSG_BACKUP_DIR_NOT_IN_CONFIG="配置文件中未找到 backup_dir，请先执行 /aidots backup"
    MSG_STATUS_ADDED="🟢 新增"
    MSG_STATUS_MODIFIED="🟡 修改"
    MSG_STATUS_UNCHANGED="⚪ 未变"
    MSG_STATUS_DELETED="🔴 已删除"
    MSG_ALL_IDENTICAL="⚪ 全部一致"
    MSG_BACKUP_DIR_MISSING="备份目录不存在，请先执行 /aidots backup"
    MSG_JQ_REQUIRED_SCAN="需要 jq 来解析扫描结果，请先安装：brew install jq"
    MSG_HEADER="🔍 配置差异对比"
    MSG_BACKUP_DIR_LABEL="备份目录："
    MSG_SUMMARY="汇总：%d 个新增，%d 个修改，%d 个删除，%d 个未变"
else
    MSG_ERROR="Error: "
    MSG_DIR_REQUIRES_PATH="--dir requires a path argument"
    MSG_UNKNOWN_OPTION="Unknown option: "
    MSG_CONFIG_NOT_FOUND="Config file not found: %s. Run /aidots backup first or use --dir to specify a backup directory"
    MSG_JQ_REQUIRED_CONFIG="jq is required to parse the config file. Install it with: brew install jq"
    MSG_BACKUP_DIR_NOT_IN_CONFIG="backup_dir not found in config file. Run /aidots backup first"
    MSG_STATUS_ADDED="🟢 Added"
    MSG_STATUS_MODIFIED="🟡 Modified"
    MSG_STATUS_UNCHANGED="⚪ Unchanged"
    MSG_STATUS_DELETED="🔴 Deleted"
    MSG_ALL_IDENTICAL="⚪ All identical"
    MSG_BACKUP_DIR_MISSING="Backup directory does not exist. Run /aidots backup first"
    MSG_JQ_REQUIRED_SCAN="jq is required to parse scan results. Install it with: brew install jq"
    MSG_HEADER="🔍 Config Diff"
    MSG_BACKUP_DIR_LABEL="Backup dir: "
    MSG_SUMMARY="Summary: %d added, %d modified, %d deleted, %d unchanged"
fi

# ── Globals ─────────────────────────────────
BACKUP_DIR=""
SHOW_ALL=false

# ── Counters ────────────────────────────────
TOTAL_ADDED=0
TOTAL_MODIFIED=0
TOTAL_DELETED=0
TOTAL_UNCHANGED=0

# ── Helpers ─────────────────────────────────

usage() {
    printf 'Usage: %s [--dir <path>] [--all] [--help]\n' "$(basename "$0")"
    printf '  --dir <path>  Override backup directory\n'
    printf '  --all         Show unchanged files too\n'
    printf '  --help        Show this help\n'
    exit 0
}

die() {
    printf '%b%s%s%b\n' "$C_RED" "$MSG_ERROR" "$1" "$C_RESET" >&2
    exit 1
}

# Shorten path for display: replace $HOME with ~
display_path() {
    local p="$1"
    if [[ "$p" == "${HOME}"* ]]; then
        printf '~%s' "${p#${HOME}}"
    else
        printf '%s' "$p"
    fi
}

# ── Parse arguments ─────────────────────────

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --dir)
                [[ $# -lt 2 ]] && die "$MSG_DIR_REQUIRES_PATH"
                BACKUP_DIR="$2"
                shift 2
                ;;
            --all)
                SHOW_ALL=true
                shift
                ;;
            --help|-h)
                usage
                ;;
            *)
                die "${MSG_UNKNOWN_OPTION}$1"
                ;;
        esac
    done
}

# ── Resolve backup directory ────────────────

resolve_backup_dir() {
    # Already set via --dir
    if [[ -n "$BACKUP_DIR" ]]; then
        # Expand ~ if present
        if [[ "$BACKUP_DIR" == "~"* ]]; then
            BACKUP_DIR="${HOME}${BACKUP_DIR#\~}"
        fi
        return
    fi

    # Read from config
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "$(printf "$MSG_CONFIG_NOT_FOUND" "$CONFIG_FILE")"
    fi

    if ! command -v jq &>/dev/null; then
        die "$MSG_JQ_REQUIRED_CONFIG"
    fi

    BACKUP_DIR=$(jq -r '.backup_dir // empty' "$CONFIG_FILE" 2>/dev/null)

    if [[ -z "$BACKUP_DIR" ]]; then
        die "$MSG_BACKUP_DIR_NOT_IN_CONFIG"
    fi

    # Expand ~
    if [[ "$BACKUP_DIR" == "~"* ]]; then
        BACKUP_DIR="${HOME}${BACKUP_DIR#\~}"
    fi
}

# ── Compare a single tool ──────────────────

# compare_tool <tool_id> <display_name> <config_dir> <files_json_array>
# Outputs diff lines and updates global counters
compare_tool() {
    local tool_id="$1"
    local display_name="$2"
    local config_dir="$3"
    local files_json="$4"

    local tool_backup_dir="${BACKUP_DIR}/${tool_id}"

    local added=0
    local modified=0
    local deleted=0
    local unchanged=0
    local lines=()

    # ── Check local files against backup ──

    local file_count
    file_count=$(printf '%s' "$files_json" | jq 'length')

    local seen_files=()

    local i
    for (( i = 0; i < file_count; i++ )); do
        local relpath
        relpath=$(printf '%s' "$files_json" | jq -r ".[$i].path")

        local local_file="${config_dir}/${relpath}"
        local backup_file="${tool_backup_dir}/${relpath}"

        seen_files+=("$relpath")

        if [[ ! -d "$tool_backup_dir" ]] || [[ ! -f "$backup_file" ]]; then
            # File exists locally but not in backup
            lines+=("$(printf '  %b%s  %s%b' "$C_GREEN" "$MSG_STATUS_ADDED" "$relpath" "$C_RESET")")
            added=$((added + 1))
        elif ! cmp -s "$local_file" "$backup_file"; then
            # Both exist but differ
            lines+=("$(printf '  %b%s  %s%b' "$C_YELLOW" "$MSG_STATUS_MODIFIED" "$relpath" "$C_RESET")")
            modified=$((modified + 1))
        else
            # Identical
            unchanged=$((unchanged + 1))
            if $SHOW_ALL; then
                lines+=("$(printf '  %b%s  %s%b' "$C_DIM" "$MSG_STATUS_UNCHANGED" "$relpath" "$C_RESET")")
            fi
        fi
    done

    # ── Check backup for deleted files (exist in backup but not locally) ──

    if [[ -d "$tool_backup_dir" ]]; then
        while IFS= read -r backup_file; do
            [[ -z "$backup_file" ]] && continue

            local relpath="${backup_file#${tool_backup_dir}/}"

            # Skip if we already saw this file from local scan
            local found=false
            local seen
            for seen in "${seen_files[@]+"${seen_files[@]}"}"; do
                if [[ "$seen" == "$relpath" ]]; then
                    found=true
                    break
                fi
            done

            if ! $found; then
                # File in backup but not found locally
                lines+=("$(printf '  %b%s  %s%b' "$C_RED" "$MSG_STATUS_DELETED" "$relpath" "$C_RESET")")
                deleted=$((deleted + 1))
            fi
        done < <(find "$tool_backup_dir" -type f 2>/dev/null | sort)
    fi

    # ── Output ──

    printf '%b%s%b (%s)\n' "$C_BOLD" "$display_name" "$C_RESET" "${tool_id}/"

    if (( ${#lines[@]} == 0 )); then
        printf '  %b%s%b\n' "$C_DIM" "$MSG_ALL_IDENTICAL" "$C_RESET"
    else
        local line
        for line in "${lines[@]}"; do
            printf '%s\n' "$line"
        done
    fi

    printf '\n'

    # Update global counters
    TOTAL_ADDED=$((TOTAL_ADDED + added))
    TOTAL_MODIFIED=$((TOTAL_MODIFIED + modified))
    TOTAL_DELETED=$((TOTAL_DELETED + deleted))
    TOTAL_UNCHANGED=$((TOTAL_UNCHANGED + unchanged))
}

# ── Main ────────────────────────────────────

main() {
    parse_args "$@"
    resolve_backup_dir

    # Validate backup directory exists
    if [[ ! -d "$BACKUP_DIR" ]]; then
        die "$MSG_BACKUP_DIR_MISSING"
    fi

    # Verify jq is available
    if ! command -v jq &>/dev/null; then
        die "$MSG_JQ_REQUIRED_SCAN"
    fi

    # Run scan.sh --json to get current local state
    local scan_json
    scan_json=$("${SCRIPT_DIR}/scan.sh" --json)

    # Header
    printf '\n%b%s%b\n\n' "$C_BOLD" "$MSG_HEADER" "$C_RESET"
    printf '%s%s\n\n' "$MSG_BACKUP_DIR_LABEL" "$(display_path "$BACKUP_DIR")"

    # Iterate over each tool
    local tool_count
    tool_count=$(printf '%s' "$scan_json" | jq '.tools | length')

    local i
    for (( i = 0; i < tool_count; i++ )); do
        local status
        status=$(printf '%s' "$scan_json" | jq -r ".tools[$i].status")

        # Only compare tools that are found (have local files)
        if [[ "$status" != "found" ]]; then
            continue
        fi

        local tool_id display_name config_dir files_json
        tool_id=$(printf '%s' "$scan_json" | jq -r ".tools[$i].id")
        display_name=$(printf '%s' "$scan_json" | jq -r ".tools[$i].name")
        config_dir=$(printf '%s' "$scan_json" | jq -r ".tools[$i].config_dir")
        files_json=$(printf '%s' "$scan_json" | jq ".tools[$i].files")

        compare_tool "$tool_id" "$display_name" "$config_dir" "$files_json"
    done

    # Also check for tools that exist in backup but were not found locally
    for backup_tool_dir in "${BACKUP_DIR}"/*/; do
        [[ ! -d "$backup_tool_dir" ]] && continue

        local backup_tool_id
        backup_tool_id=$(basename "$backup_tool_dir")

        # Check if this tool was in the scan with status "found"
        local was_found=false
        local j
        for (( j = 0; j < tool_count; j++ )); do
            local tid tstatus
            tid=$(printf '%s' "$scan_json" | jq -r ".tools[$j].id")
            tstatus=$(printf '%s' "$scan_json" | jq -r ".tools[$j].status")
            if [[ "$tid" == "$backup_tool_id" && "$tstatus" == "found" ]]; then
                was_found=true
                break
            fi
        done

        if ! $was_found; then
            # Tool exists in backup but not locally — all files are deleted
            local backup_file_count
            backup_file_count=$(find "$backup_tool_dir" -type f 2>/dev/null | wc -l | tr -d ' ')

            if (( backup_file_count > 0 )); then
                # Get display name from scan if available, else use tool_id
                local dn="$backup_tool_id"
                for (( j = 0; j < tool_count; j++ )); do
                    local tid
                    tid=$(printf '%s' "$scan_json" | jq -r ".tools[$j].id")
                    if [[ "$tid" == "$backup_tool_id" ]]; then
                        dn=$(printf '%s' "$scan_json" | jq -r ".tools[$j].name")
                        break
                    fi
                done

                printf '%b%s%b (%s/)\n' "$C_BOLD" "$dn" "$C_RESET" "$backup_tool_id"

                while IFS= read -r bf; do
                    [[ -z "$bf" ]] && continue
                    local rp="${bf#${backup_tool_dir}}"
                    printf '  %b%s  %s%b\n' "$C_RED" "$MSG_STATUS_DELETED" "$rp" "$C_RESET"
                    TOTAL_DELETED=$((TOTAL_DELETED + 1))
                done < <(find "$backup_tool_dir" -type f 2>/dev/null | sort)

                printf '\n'
            fi
        fi
    done

    # Summary
    printf '────────────────────\n'
    printf "${MSG_SUMMARY}\n\n" \
        "$TOTAL_ADDED" "$TOTAL_MODIFIED" "$TOTAL_DELETED" "$TOTAL_UNCHANGED"
}

main "$@"
