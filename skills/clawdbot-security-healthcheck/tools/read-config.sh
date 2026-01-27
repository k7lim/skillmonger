#!/bin/bash
# read-config.sh - Safely read Clawdbot configuration with secret redaction
# Usage: ./read-config.sh [config-path]

set -euo pipefail

CONFIG_PATH="${1:-$HOME/.clawdbot/config.json}"

# Check if config exists
if [[ ! -f "$CONFIG_PATH" ]]; then
    echo "ERROR: Config file not found at $CONFIG_PATH"
    echo ""
    echo "Common locations:"
    echo "  - ~/.clawdbot/config.json"
    echo "  - ~/.config/clawdbot/config.json"
    echo "  - ./clawdbot.config.json"
    exit 1
fi

echo "Reading config from: $CONFIG_PATH"
echo "=============================================="
echo ""

# Read and redact secrets
# Patterns to redact (case-insensitive):
# - api_key, apikey, api-key
# - token, secret, password, credential
# - Any value that looks like a key (long alphanumeric strings)

if command -v jq &> /dev/null; then
    # Use jq for proper JSON handling with redaction
    jq '
    def redact:
        if type == "string" then
            if (. | test("^(sk-|xoxb-|xoxp-|ghp_|gho_|github_pat_)"; "i")) then
                "[REDACTED - API KEY]"
            elif (. | length > 30) and (. | test("^[A-Za-z0-9+/=_-]+$")) then
                "[REDACTED - POSSIBLE SECRET]"
            else
                .
            end
        elif type == "object" then
            with_entries(
                if (.key | test("(key|token|secret|password|credential|auth)"; "i")) then
                    .value = "[REDACTED]"
                else
                    .value = (.value | redact)
                end
            )
        elif type == "array" then
            map(redact)
        else
            .
        end;
    . | redact
    ' "$CONFIG_PATH"
else
    # Fallback: basic sed-based redaction (less precise)
    echo "WARNING: jq not installed, using basic redaction"
    echo ""
    cat "$CONFIG_PATH" | sed -E '
        s/("(api_?key|token|secret|password|credential|auth)[^"]*"[[:space:]]*:[[:space:]]*")[^"]+"/\1[REDACTED]"/gi
        s/(sk-|xoxb-|xoxp-|ghp_|gho_|github_pat_)[A-Za-z0-9_-]+/[REDACTED]/gi
    '
fi

echo ""
echo "=============================================="
echo "Note: Sensitive values have been redacted"
