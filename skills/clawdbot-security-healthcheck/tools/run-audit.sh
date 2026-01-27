#!/bin/bash
# run-audit.sh - Run Clawdbot security audit
# Usage: ./run-audit.sh [--deep]

set -euo pipefail

DEEP_FLAG=""
if [[ "${1:-}" == "--deep" ]] || [[ "${1:-}" == "-d" ]]; then
    DEEP_FLAG="--deep"
fi

# Check if clawdbot is installed
if ! command -v clawdbot &> /dev/null; then
    echo "ERROR: clawdbot command not found"
    echo "Please ensure Clawdbot is installed and in your PATH"
    exit 1
fi

# Run the security audit
echo "Running Clawdbot security audit${DEEP_FLAG:+ (deep scan)}..."
echo "=============================================="
echo ""

if [[ -n "$DEEP_FLAG" ]]; then
    clawdbot security audit --deep 2>&1
else
    clawdbot security audit 2>&1
fi

EXIT_CODE=$?

echo ""
echo "=============================================="
echo "Audit complete (exit code: $EXIT_CODE)"

exit $EXIT_CODE
