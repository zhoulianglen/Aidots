#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# scan.sh — Scan local AI coding tool configs
# Part of the aidots skill
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_CONF="${SCRIPT_DIR}/tools.conf"

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

if [[ "$LOCALE" == "zh" ]]; then
    MSG_SCAN_HEADER="🔍 AI Coding 工具配置扫描"
    MSG_FILE_COUNT="共 %d 个文件"
    MSG_NOT_INSTALLED="未安装"
    MSG_NO_CUSTOM_CONFIG="未发现个性化配置"
    MSG_SCAN_SUMMARY="扫描完成：发现 %d 个工具，共 %d 个配置文件"
else
    MSG_SCAN_HEADER="🔍 AI Coding Tool Config Scan"
    MSG_FILE_COUNT="%d files"
    MSG_NOT_INSTALLED="not installed"
    MSG_NO_CUSTOM_CONFIG="no custom config found"
    MSG_SCAN_SUMMARY="Scan complete: found %d tools, %d config files"
fi

# ── Globals ─────────────────────────────────
OUTPUT_MODE="human"

# scan_tool results are communicated via a temp file
# Each line: <size><TAB><relative_path>
SCAN_RESULT_FILE=""
SCAN_STATUS=""

# ── Helpers ─────────────────────────────────

usage() {
    printf 'Usage: %s [--json]\n' "$(basename "$0")"
    printf '  --json   Output JSON for programmatic consumption\n'
    exit 0
}

# Format byte count to human-readable size
human_size() {
    local bytes=$1
    if (( bytes >= 1048576 )); then
        printf '%.1f MB' "$(echo "scale=1; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf '%.1f KB' "$(echo "scale=1; $bytes / 1024" | bc)"
    else
        printf '%d B' "$bytes"
    fi
}

# Check if a file is "empty content": 0 bytes, or contains only {}, [], or whitespace
is_empty_content() {
    local filepath="$1"
    local filesize
    filesize=$(wc -c < "$filepath" | tr -d ' ')

    # 0 bytes
    if (( filesize == 0 )); then
        return 0
    fi

    # For small files (< 20 bytes), check if content is trivial
    if (( filesize <= 20 )); then
        local content
        content=$(tr -d '[:space:]' < "$filepath")
        if [[ -z "$content" || "$content" == "{}" || "$content" == "[]" ]]; then
            return 0
        fi
    fi

    return 1
}

# Check if filename matches sensitive patterns
is_sensitive() {
    local filename="$1"
    local base
    base=$(basename "$filename")
    case "$base" in
        auth.json|oauth_creds.json) return 0 ;;
        *credentials*|*Credentials*) return 0 ;;
        *token*|*Token*) return 0 ;;
        *secret*|*Secret*) return 0 ;;
    esac
    return 1
}

# Check if file is a binary type we want to skip
is_binary_ext() {
    local filepath="$1"
    case "$filepath" in
        *.pb|*.png|*.jpg|*.jpeg|*.svg|*.ico|*.gif|*.woff|*.woff2|*.ttf|*.eot) return 0 ;;
    esac
    return 1
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

# ── Glob matching via find ──────────────────

# Convert a single include glob and run find.
# Results are printed one per line as absolute paths.
find_matching_files() {
    local config_dir="$1"
    local glob="$2"

    if [[ "$glob" == "**" ]]; then
        # Match everything recursively
        find "$config_dir" -type f 2>/dev/null
    elif [[ "$glob" == *"/**" ]]; then
        # e.g. skills/** — match everything under skills/ recursively
        local prefix="${glob%/\*\*}"
        if [[ -d "${config_dir}/${prefix}" ]]; then
            find "${config_dir}/${prefix}" -type f 2>/dev/null
        fi
    elif [[ "$glob" == *"/*" && "$glob" != *"/**" ]]; then
        # e.g. extensions/* — one level under a directory
        local prefix="${glob%/\*}"
        if [[ -d "${config_dir}/${prefix}" ]]; then
            find "${config_dir}/${prefix}" -maxdepth 1 -type f 2>/dev/null
        fi
    elif [[ "$glob" == *"*"* ]]; then
        # Contains a wildcard but not ** — use -name at root level
        find "$config_dir" -maxdepth 1 -type f -name "$glob" 2>/dev/null
    elif [[ "$glob" == *"/"* ]]; then
        # Has a slash — treat as exact relative path
        local target="${config_dir}/${glob}"
        if [[ -f "$target" ]]; then
            printf '%s\n' "$target"
        fi
    else
        # Simple filename — match at root of config_dir
        local target="${config_dir}/${glob}"
        if [[ -f "$target" ]]; then
            printf '%s\n' "$target"
        fi
    fi
}

# Check if a file (relative path) matches any exclude glob.
# Exclude patterns passed as remaining arguments.
matches_exclude() {
    local relpath="$1"
    shift

    local pattern
    for pattern in "$@"; do
        [[ -z "$pattern" ]] && continue

        if [[ "$pattern" == "**" ]]; then
            return 0
        elif [[ "$pattern" == *"/**" ]]; then
            local prefix="${pattern%/\*\*}"
            if [[ "$relpath" == "${prefix}/"* ]]; then
                return 0
            fi
        elif [[ "$pattern" == *"/*" && "$pattern" != *"/**" ]]; then
            local prefix="${pattern%/\*}"
            local dir_part
            dir_part=$(dirname "$relpath")
            if [[ "$dir_part" == "$prefix" ]]; then
                return 0
            fi
        elif [[ "$pattern" == *"*"* ]]; then
            # Wildcard — check basename and full relpath
            local base
            base=$(basename "$relpath")
            # Use eval-free case matching
            if [[ "$base" == $pattern ]]; then
                return 0
            fi
            if [[ "$relpath" == $pattern ]]; then
                return 0
            fi
        elif [[ "$pattern" == *"/" ]]; then
            if [[ "$relpath" == "${pattern}"* ]]; then
                return 0
            fi
        else
            if [[ "$relpath" == "$pattern" || "$(basename "$relpath")" == "$pattern" ]]; then
                return 0
            fi
        fi
    done
    return 1
}

# ── Core scanning ───────────────────────────

# Scan a single tool. Writes results to SCAN_RESULT_FILE (temp file).
# Each line: <size>\t<relative_path>
# Sets SCAN_STATUS to: "found", "empty", or "not_installed"
scan_tool() {
    local tool_id="$1"
    local display_name="$2"
    local config_dir="$3"
    local include_str="$4"
    local exclude_str="$5"

    # Clear result file
    : > "$SCAN_RESULT_FILE"

    # Expand config_dir
    config_dir=$(expand_tilde "$config_dir")

    # Check if directory exists
    if [[ ! -d "$config_dir" ]]; then
        SCAN_STATUS="not_installed"
        return 0
    fi

    # Parse include globs into positional-friendly format
    local IFS_SAVE="$IFS"
    IFS=',' read -ra include_globs <<< "$include_str"
    IFS="$IFS_SAVE"

    # Parse exclude globs
    local exclude_globs=()
    if [[ -n "$exclude_str" ]]; then
        IFS_SAVE="$IFS"
        IFS=',' read -ra exclude_globs <<< "$exclude_str"
        IFS="$IFS_SAVE"
    fi

    # Collect all matching files (deduplicated via sort -u)
    local all_files_tmp
    all_files_tmp=$(mktemp)

    local glob
    for glob in "${include_globs[@]}"; do
        # Trim whitespace
        glob=$(echo "$glob" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$glob" ]] && continue
        find_matching_files "$config_dir" "$glob"
    done | sort -u > "$all_files_tmp"

    # Filter files
    local found_any=false

    while IFS= read -r filepath; do
        [[ -z "$filepath" ]] && continue

        # Get relative path
        local relpath="${filepath#${config_dir}/}"

        # Check exclude patterns
        if (( ${#exclude_globs[@]} > 0 )); then
            if matches_exclude "$relpath" "${exclude_globs[@]}"; then
                continue
            fi
        fi

        # Skip binary extensions
        if is_binary_ext "$filepath"; then
            continue
        fi

        # Skip sensitive files
        if is_sensitive "$filepath"; then
            continue
        fi

        # Skip empty content
        if is_empty_content "$filepath"; then
            continue
        fi

        local fsize
        fsize=$(wc -c < "$filepath" | tr -d ' ')
        printf '%s\t%s\n' "$fsize" "$relpath" >> "$SCAN_RESULT_FILE"
        found_any=true

    done < "$all_files_tmp"

    rm -f "$all_files_tmp"

    if $found_any; then
        SCAN_STATUS="found"
    else
        SCAN_STATUS="empty"
    fi
}

# ── Output: JSON ────────────────────────────

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

output_json() {
    local first_tool=true
    local tools_found=0
    local total_files=0

    printf '{\n  "tools": [\n'

    while IFS='|' read -r tool_id display_name config_dir include_globs exclude_globs; do
        # Skip comments and blank lines
        [[ -z "$tool_id" || "$tool_id" == \#* ]] && continue

        local expanded_dir
        expanded_dir=$(expand_tilde "$config_dir")

        scan_tool "$tool_id" "$display_name" "$config_dir" "$include_globs" "${exclude_globs:-}"

        if [[ "$SCAN_STATUS" == "found" ]]; then
            tools_found=$((tools_found + 1))
            local file_count
            file_count=$(wc -l < "$SCAN_RESULT_FILE" | tr -d ' ')
            total_files=$((total_files + file_count))
        fi

        if $first_tool; then
            first_tool=false
        else
            printf ',\n'
        fi

        printf '    {\n'
        printf '      "id": "%s",\n' "$(json_escape "$tool_id")"
        printf '      "name": "%s",\n' "$(json_escape "$display_name")"
        printf '      "config_dir": "%s",\n' "$(json_escape "$expanded_dir")"
        printf '      "status": "%s",\n' "$SCAN_STATUS"
        printf '      "files": ['

        if [[ -s "$SCAN_RESULT_FILE" ]]; then
            printf '\n'
            local first_file=true
            while IFS=$'\t' read -r fsize fpath; do
                if $first_file; then
                    first_file=false
                else
                    printf ',\n'
                fi
                printf '        {"path": "%s", "size": %s}' \
                    "$(json_escape "$fpath")" "$fsize"
            done < "$SCAN_RESULT_FILE"
            printf '\n      '
        fi
        printf ']\n'
        printf '    }'

    done < "$TOOLS_CONF"

    printf '\n  ],\n'
    printf '  "summary": {\n'
    printf '    "tools_found": %d,\n' "$tools_found"
    printf '    "total_files": %d\n' "$total_files"
    printf '  }\n'
    printf '}\n'
}

# ── Output: Human-readable ──────────────────

output_human() {
    local tools_found=0
    local total_files=0

    printf '\n%b%s%b\n\n' "$C_BOLD" "$MSG_SCAN_HEADER" "$C_RESET"

    while IFS='|' read -r tool_id display_name config_dir include_globs exclude_globs; do
        # Skip comments and blank lines
        [[ -z "$tool_id" || "$tool_id" == \#* ]] && continue

        # Display path with ~ for readability
        local display_dir="${config_dir}"

        scan_tool "$tool_id" "$display_name" "$config_dir" "$include_globs" "${exclude_globs:-}"

        if [[ "$SCAN_STATUS" == "found" ]]; then
            tools_found=$((tools_found + 1))
            local file_count
            file_count=$(wc -l < "$SCAN_RESULT_FILE" | tr -d ' ')
            total_files=$((total_files + file_count))

            printf '%b✅ %s (%s)%b\n' "$C_GREEN" "$display_name" "$display_dir" "$C_RESET"

            while IFS=$'\t' read -r fsize fpath; do
                local hsize
                hsize=$(human_size "$fsize")
                printf '   %-50s %s\n' "$fpath" "$hsize"
            done < "$SCAN_RESULT_FILE"

            printf "   %b${MSG_FILE_COUNT}%b\n\n" "$C_DIM" "$file_count" "$C_RESET"

        elif [[ "$SCAN_STATUS" == "not_installed" ]]; then
            printf '%b❌ %s (%s) — %s%b\n\n' "$C_RED" "$display_name" "$display_dir" "$MSG_NOT_INSTALLED" "$C_RESET"

        else
            printf '%b⏭️  %s (%s) — %s%b\n\n' "$C_YELLOW" "$display_name" "$display_dir" "$MSG_NO_CUSTOM_CONFIG" "$C_RESET"
        fi

    done < "$TOOLS_CONF"

    printf '────────────────────\n'
    printf "${MSG_SCAN_SUMMARY}\n\n" "$tools_found" "$total_files"
}

# ── Main ────────────────────────────────────

cleanup() {
    [[ -n "$SCAN_RESULT_FILE" && -f "$SCAN_RESULT_FILE" ]] && rm -f "$SCAN_RESULT_FILE"
}

main() {
    # Parse arguments
    while (( $# > 0 )); do
        case "$1" in
            --json)  OUTPUT_MODE="json"; shift ;;
            --help|-h) usage ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; usage ;;
        esac
    done

    # Verify tools.conf exists
    if [[ ! -f "$TOOLS_CONF" ]]; then
        printf 'Error: tools.conf not found at %s\n' "$TOOLS_CONF" >&2
        exit 1
    fi

    # Create temp file for scan results
    SCAN_RESULT_FILE=$(mktemp)
    trap cleanup EXIT

    if [[ "$OUTPUT_MODE" == "json" ]]; then
        output_json
    else
        output_human
    fi
}

main "$@"
