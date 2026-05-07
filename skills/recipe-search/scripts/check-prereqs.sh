#!/bin/bash
# check-prereqs.sh - Verify prerequisites for recipe-search
# Outputs JSON for agent consumption. Exit 0 always.
set -euo pipefail

checks=()
all_ok=true

check_python3() {
  local name="python3"
  local required=">=3.8"
  if ! command -v python3 &>/dev/null; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"required\":\"$required\"}")
    all_ok=false
    return
  fi
  local version
  version=$(python3 --version 2>&1 | awk '{print $2}')
  local major minor
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 8 ]; }; then
    checks+=("{\"name\":\"$name\",\"status\":\"outdated\",\"version\":\"$version\",\"required\":\"$required\"}")
    all_ok=false
    return
  fi
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\",\"required\":\"$required\"}")
}

check_pip_package() {
  local name="$1"
  local import_name="${2:-$1}"
  if ! python3 -c "import $import_name" &>/dev/null 2>&1; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"required\":\"latest\"}")
    all_ok=false
    return
  fi
  local version
  version=$(python3 -c "import importlib.metadata; print(importlib.metadata.version('$name'))" 2>/dev/null || echo "unknown")
  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"version\":\"$version\"}")
}

check_python3
check_pip_package "recipe-scrapers" "recipe_scrapers"
check_pip_package "scrape-schema-recipe" "scrape_schema_recipe"

# Build checks array
checks_json=""
for i in "${!checks[@]}"; do
  if [ "$i" -gt 0 ]; then
    checks_json+=","
  fi
  checks_json+="${checks[$i]}"
done

cat << EOF
{
  "ready": $all_ok,
  "checks": [$checks_json],
  "context": {}
}
EOF
