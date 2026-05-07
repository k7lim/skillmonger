#!/bin/bash
# check-prereqs.sh - Verify prerequisites for writing-voice-coach
# Outputs JSON for agent consumption
set -euo pipefail

checks=()
all_ok=true

check_python() {
  local name="python3"
  local required=">=3.6"

  if ! command -v python3 &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"required\":\"$required\"}")
    all_ok=false
    return
  fi

  local version
  version=$(python3 --version 2>&1 | cut -d' ' -f2 || echo "unknown")
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\",\"required\":\"$required\"}")
}

# Run checks
check_python

# Build checks array
checks_json=""
for i in "${!checks[@]}"; do
  if [ $i -gt 0 ]; then
    checks_json+=","
  fi
  checks_json+="${checks[$i]}"
done

# Output
cat << EOF
{
  "ready": $all_ok,
  "checks": [$checks_json],
  "context": {}
}
EOF
