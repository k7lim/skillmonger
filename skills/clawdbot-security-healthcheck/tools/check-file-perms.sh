#!/bin/bash
# check-file-perms.sh - Check file and directory permissions for security issues
# Usage: ./check-file-perms.sh [path]

set -euo pipefail

TARGET_PATH="${1:-$HOME/.clawdbot}"

echo "Checking permissions for: $TARGET_PATH"
echo "=============================================="
echo ""

# Check if path exists
if [[ ! -e "$TARGET_PATH" ]]; then
    echo "ERROR: Path does not exist: $TARGET_PATH"
    exit 1
fi

# Function to check and report on a file/directory
check_perms() {
    local path="$1"
    local expected_mode="${2:-}"

    if [[ ! -e "$path" ]]; then
        echo "  [SKIP] $path (does not exist)"
        return
    fi

    # Get permissions
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        local perms=$(stat -f "%Sp %OLp" "$path")
        local mode=$(stat -f "%OLp" "$path")
        local owner=$(stat -f "%Su:%Sg" "$path")
    else
        # Linux
        local perms=$(stat -c "%A %a" "$path")
        local mode=$(stat -c "%a" "$path")
        local owner=$(stat -c "%U:%G" "$path")
    fi

    # Determine status
    local status="INFO"
    local note=""

    # Check for world-readable
    if [[ "$mode" =~ [0-7][0-7][4-7]$ ]]; then
        status="WARN"
        note="world-readable"
    fi

    # Check for world-writable
    if [[ "$mode" =~ [0-7][0-7][2367]$ ]]; then
        status="CRIT"
        note="world-writable!"
    fi

    # Check for group-writable on sensitive files
    if [[ "$path" =~ (config|secret|key|token|credential) ]] && [[ "$mode" =~ [0-7][2367][0-7]$ ]]; then
        status="WARN"
        note="group-writable"
    fi

    # Check against expected mode if provided
    if [[ -n "$expected_mode" ]] && [[ "$mode" != "$expected_mode" ]]; then
        if [[ "$status" == "INFO" ]]; then
            status="WARN"
        fi
        note="${note:+$note, }expected $expected_mode"
    fi

    # Color output
    case "$status" in
        CRIT) local color="\033[31m" ;;  # Red
        WARN) local color="\033[33m" ;;  # Yellow
        *)    local color="\033[32m" ;;  # Green
    esac
    local reset="\033[0m"

    printf "  [${color}%s${reset}] %s %s (%s)%s\n" \
        "$status" "$mode" "$path" "$owner" "${note:+ - $note}"
}

# Check main directory
echo "Directory permissions:"
check_perms "$TARGET_PATH" "700"
echo ""

# If it's a directory, check contents
if [[ -d "$TARGET_PATH" ]]; then
    echo "File permissions:"

    # Check common sensitive files
    check_perms "$TARGET_PATH/config.json" "600"
    check_perms "$TARGET_PATH/config.yaml" "600"
    check_perms "$TARGET_PATH/secrets.json" "600"
    check_perms "$TARGET_PATH/.env" "600"
    check_perms "$TARGET_PATH/credentials" "600"
    check_perms "$TARGET_PATH/token" "600"

    echo ""
    echo "All files in directory:"

    # List all files
    for f in "$TARGET_PATH"/*; do
        if [[ -e "$f" ]]; then
            check_perms "$f"
        fi
    done

    # Check for hidden files
    for f in "$TARGET_PATH"/.*; do
        if [[ -e "$f" ]] && [[ "$(basename "$f")" != "." ]] && [[ "$(basename "$f")" != ".." ]]; then
            check_perms "$f"
        fi
    done
fi

echo ""
echo "=============================================="
echo ""
echo "Permission Guide:"
echo "  700 - Directory (owner only)"
echo "  600 - Sensitive files (owner read/write only)"
echo "  644 - Regular files (owner write, everyone read)"
echo ""
echo "To fix permissions:"
echo "  chmod 700 ~/.clawdbot"
echo "  chmod 600 ~/.clawdbot/config.json"
