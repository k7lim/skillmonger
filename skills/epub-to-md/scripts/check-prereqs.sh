#!/bin/bash
# check-prereqs - Verify prerequisites for epub-to-md skill
# Outputs JSON for agent consumption. Exit 0 always.
set -uo pipefail

checks=()
all_ok=true

check_node() {
  local name="node"
  local required=">=18.0"

  if ! command -v node &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"required\":\"$required\"}")
    all_ok=false
    return
  fi

  local version
  version=$(node --version 2>&1 | sed 's/^v//' || echo "unknown")
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\",\"required\":\"$required\"}")
}

check_npm() {
  local name="npm"

  if ! command -v npm &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\"}")
    all_ok=false
    return
  fi

  local version
  version=$(npm --version 2>&1 || echo "unknown")
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

check_epub2md() {
  local name="epub2md"

  if ! command -v epub2md &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"install\":\"npm install -g epub2md\"}")
    all_ok=false
    return
  fi

  local version
  version=$(epub2md --version 2>&1 | head -1 || echo "unknown")
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

# Run all checks
check_node
check_npm
check_epub2md

# Build checks array JSON
checks_json=""
for i in "${!checks[@]}"; do
  if [ $i -gt 0 ]; then
    checks_json+=","
  fi
  checks_json+="${checks[$i]}"
done

# Output JSON
cat << EOF
{
  "ready": $all_ok,
  "checks": [$checks_json],
  "context": {}
}
EOF
