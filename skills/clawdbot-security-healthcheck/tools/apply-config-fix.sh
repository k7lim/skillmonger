#!/bin/bash
# apply-config-fix.sh - Apply configuration changes with backup
# Usage: ./apply-config-fix.sh <json-path> <new-value> [config-file]
#
# Examples:
#   ./apply-config-fix.sh '.gateway.host' '"127.0.0.1"'
#   ./apply-config-fix.sh '.gateway.token' '"my-secret-token"'
#   ./apply-config-fix.sh '.sandbox' '"full"'
#   ./apply-config-fix.sh '.dm_policy' '"paired"'

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <json-path> <new-value> [config-file]"
    echo ""
    echo "Examples:"
    echo "  $0 '.gateway.host' '\"127.0.0.1\"'"
    echo "  $0 '.gateway.token' '\"my-secret-token\"'"
    echo "  $0 '.sandbox' '\"full\"'"
    echo ""
    echo "Note: String values must be quoted (e.g., '\"value\"')"
    exit 1
fi

JSON_PATH="$1"
NEW_VALUE="$2"
CONFIG_FILE="${3:-$HOME/.clawdbot/config.json}"

# Verify jq is installed
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed"
    echo "Install with: brew install jq (macOS) or apt install jq (Linux)"
    exit 1
fi

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Validate JSON path
if [[ ! "$JSON_PATH" =~ ^\. ]]; then
    echo "ERROR: JSON path must start with '.'"
    echo "Example: .gateway.host"
    exit 1
fi

# Show current value
echo "Config file: $CONFIG_FILE"
echo "=============================================="
echo ""

CURRENT_VALUE=$(jq -r "$JSON_PATH // \"[not set]\"" "$CONFIG_FILE" 2>/dev/null || echo "[path does not exist]")
echo "Current value of $JSON_PATH:"
echo "  $CURRENT_VALUE"
echo ""
echo "New value:"
echo "  $NEW_VALUE"
echo ""

# Create backup
BACKUP_DIR="$HOME/.clawdbot/backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/config.$(date +%Y%m%d_%H%M%S).json"

cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"
echo ""

# Apply the change
# Handle nested paths by ensuring parent objects exist
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

if jq "$JSON_PATH = $NEW_VALUE" "$CONFIG_FILE" > "$TEMP_FILE" 2>&1; then
    # Validate the result is valid JSON
    if jq empty "$TEMP_FILE" 2>/dev/null; then
        mv "$TEMP_FILE" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"

        echo "=============================================="
        echo "SUCCESS: Configuration updated"
        echo ""
        echo "New configuration value:"
        jq "$JSON_PATH" "$CONFIG_FILE"
        echo ""
        echo "To revert: cp '$BACKUP_FILE' '$CONFIG_FILE'"
    else
        echo "ERROR: Result is not valid JSON"
        echo "No changes made."
        exit 1
    fi
else
    echo "ERROR: Failed to apply change"
    echo "jq error output:"
    cat "$TEMP_FILE"
    echo ""
    echo "No changes made."
    exit 1
fi
