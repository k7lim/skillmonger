#!/bin/bash
# check-prereqs.sh - Verify prerequisites for skillmonger workflow skill
set -euo pipefail

checks=()
all_ok=true

SKILLMONGER_ROOT="${SKILLMONGER_ROOT:-$HOME/Development/host/skillmonger}"
SANDBOX_ROOT="${SANDBOX_ROOT:-$HOME/Development/sandbox}"

check_skillmonger_dir() {
  local name="skillmonger-project"

  if [ ! -d "$SKILLMONGER_ROOT" ]; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"path\":\"$SKILLMONGER_ROOT\"}")
    all_ok=false
    return
  fi

  if [ ! -d "$SKILLMONGER_ROOT/seeds" ] || [ ! -d "$SKILLMONGER_ROOT/skills" ]; then
    checks+=("{\"name\":\"$name\",\"status\":\"incomplete\",\"path\":\"$SKILLMONGER_ROOT\"}")
    all_ok=false
    return
  fi

  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"path\":\"$SKILLMONGER_ROOT\"}")
}

check_sandbox_dir() {
  local name="sandbox"

  if [ ! -d "$SANDBOX_ROOT" ]; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"path\":\"$SANDBOX_ROOT\",\"note\":\"Will be created on first use\"}")
    # Not a blocker - develop-skill.sh creates it
    return
  fi

  checks+=("{\"name\":\"$name\",\"status\":\"ok\",\"path\":\"$SANDBOX_ROOT\"}")
}

check_scripts() {
  local name="framework-scripts"
  local missing=()

  for script in develop-skill.sh ship-skill.sh deploy-skill.sh; do
    if [ ! -x "$SKILLMONGER_ROOT/scripts/$script" ]; then
      missing+=("$script")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    checks+=("{\"name\":\"$name\",\"status\":\"missing\",\"scripts\":[\"${missing[*]}\"]}")
    all_ok=false
    return
  fi

  checks+=("{\"name\":\"$name\",\"status\":\"ok\"}")
}

# Run checks
check_skillmonger_dir
check_sandbox_dir
check_scripts

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
  "context": {
    "skillmonger_root": "$SKILLMONGER_ROOT",
    "sandbox_root": "$SANDBOX_ROOT"
  }
}
EOF
