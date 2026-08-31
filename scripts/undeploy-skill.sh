#!/bin/bash
# undeploy-skill.sh - Remove deployed skill symlinks and installed copies
# Inverse of deploy-skill.sh
#
# The deploy targets are defined once, in lib/deploy-targets.sh, and this
# script removes from exactly the places deploy-skill.sh writes to. A deployed
# copy is where agents write their traces (ADR 0002), so every target is
# harvested before it is removed -- undeploy must never be the step that
# destroys a trace deploy would have brought home.
#
# Removal is opt-in. The plan (one line per target) is printed first; then a
# terminal is asked once, and a non-terminal must have passed --yes or the
# script refuses (exit 2). --dry-run prints the plan and stops, harvesting
# nothing and removing nothing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/deploy-targets.sh
. "$SCRIPT_DIR/lib/deploy-targets.sh"
# shellcheck source=lib/skill-name.sh
. "$SCRIPT_DIR/lib/skill-name.sh"

# Parse arguments
SKILL_NAME=""
DO_GLOBAL=""
LOCAL_DIR=""
TOOLS=""
DRY_RUN=""
ASSUME_YES=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --global)
      DO_GLOBAL=1
      shift
      ;;
    --local)
      LOCAL_DIR="$2"
      shift 2
      ;;
    --tools)
      TOOLS="$2"
      shift 2
      ;;
    --dry-run|-n)
      DRY_RUN=1
      shift
      ;;
    --yes|-y)
      ASSUME_YES=1
      shift
      ;;
    --help|-h)
      echo "Usage: undeploy-skill.sh <skill-name> [options]"
      echo ""
      echo "Options:"
      echo "  --global          Remove from the store ($SKILLMONGER_DIR),"
      echo "                    the user-global tool directories, and the SRT"
      echo "                    sandbox home ($YOLOBOX_SANDBOX_HOME)"
      echo "  --local <dir>     Remove copies from project tool directories"
      echo "  --tools <list>    Comma-separated tools: claude,codex,opencode,pi (default: all)"
      echo "  --dry-run, -n     Print what would be harvested and removed, one line"
      echo "                    per target, and change nothing (no harvest either)"
      echo "  --yes, -y         Remove without asking. Required when stdin is not a"
      echo "                    terminal; otherwise the script refuses with exit 2."
      echo ""
      echo "At least one of --global or --local must be specified."
      echo "The plan is printed before anything happens; a terminal is asked once."
      echo "Every copy is harvested (harvest-feedback.sh) before it is removed."
      exit 0
      ;;
    *)
      # A bare name, or a path to an existing skill directory (skills/<name>/).
      # Anything else with a slash in it is taken as a name, and rejected as
      # one. `.` and `..` never get path treatment: their basename would have
      # been the target root itself, and rm -rf follows.
      SKILL_NAME="$1"
      case "$SKILL_NAME" in
        */*)
          if [ -d "$SKILL_NAME" ]; then
            SKILL_NAME="$(cd "$SKILL_NAME" && pwd)"
            SKILL_NAME="${SKILL_NAME##*/}"
          fi
          ;;
      esac
      skill_name_require "$SKILL_NAME"
      shift
      ;;
  esac
done

if [ -z "$SKILL_NAME" ]; then
  echo "Usage: undeploy-skill.sh <skill-name> [--global] [--local <dir>] [--tools <list>] [--dry-run] [--yes]"
  echo "Run with --help for more information."
  exit 1
fi

if [ -z "$DO_GLOBAL" ] && [ -z "$LOCAL_DIR" ]; then
  echo "ERROR: Specify --global and/or --local <dir>"
  exit 1
fi

# Default to all tools if not specified
if [ -z "$TOOLS" ]; then
  TOOLS="claude,codex,opencode,pi"
fi

echo "Undeploying skill: $SKILL_NAME"
echo "Tools: $TOOLS"
if [ -n "$DRY_RUN" ]; then
  echo "Dry run: the plan is printed, nothing is changed."
fi
echo ""

# Helper: check if tool is in the list
tool_enabled() {
  [[ ",$TOOLS," == *",$1,"* ]]
}

# One planned action per line.
plan() {
  printf '  %-8s %s\n' "$1" "$2"
}

# The harvester reads <root>/<skill> under every deploy target root plus any
# --target DIR it is given; list the copies it would find.
plan_harvest() {
  local root
  while IFS= read -r root; do
    if [ -n "$root" ] && [ -e "$root/$SKILL_NAME" ]; then
      plan harvest "$root/$SKILL_NAME"
    fi
  done < <(deploy_target_roots)
  while [ $# -gt 0 ]; do
    if [ "$1" = "--target" ] && [ -e "$2/$SKILL_NAME" ]; then
      plan harvest "$2/$SKILL_NAME"
    fi
    shift
  done
}

# Same contract as deploy-skill.sh: a copy is removed only after its traces
# are home. A failed harvest aborts before anything is touched. In a dry run
# the harvest itself is only planned: it writes into skills/, and a dry run
# writes nowhere.
harvest_before_removal() {
  if [ -n "$DRY_RUN" ]; then
    plan_harvest "$@"
    return 0
  fi
  if ! "$SCRIPT_DIR/harvest-feedback.sh" "$SKILL_NAME" --quiet "$@"; then
    echo "ERROR: Harvest failed for $SKILL_NAME. Refusing to undeploy: the" >&2
    echo "       deployed copies hold traces that undeploy would destroy." >&2
    exit 1
  fi
}

# --- Plan: what is there to remove ------------------------------------------
# PLAN_PATHS holds what rm -rf gets; PLAN_LABELS the line shown for it.
PLAN_PATHS=()
PLAN_LABELS=()
plan_remove() {
  PLAN_PATHS+=("$1")
  PLAN_LABELS+=("$2")
}

if [ -n "$DO_GLOBAL" ]; then
  # Links or copies in the tool directories.
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
    if tool_enabled "$tool"; then
      target="$global_path/$SKILL_NAME"
      if [ -L "$target" ] || [ -e "$target" ]; then
        plan_remove "$target" "$target"
      else
        plan skip "$target (not found)"
      fi
    fi
  done

  # The real copies deploy-skill.sh made in the SRT sandbox home.
  for entry in "${SANDBOX_TOOL_PATHS[@]}"; do
    IFS=':' read -r tool sandbox_path <<< "$entry"
    if tool_enabled "$tool"; then
      target="$sandbox_path/$SKILL_NAME"
      if [ -d "$target" ]; then
        plan_remove "$target" "$target (SRT sandbox)"
      fi
    fi
  done

  # The installed copy in the store.
  installed="$SKILLMONGER_DIR/$SKILL_NAME"
  if [ -d "$installed" ]; then
    plan_remove "$installed" "$installed"
  else
    plan skip "$installed (not found)"
  fi
fi

# The project's copies are deploy targets the harvester cannot enumerate on
# its own, so name them explicitly before removing them.
LOCAL_TARGETS=()
if [ -n "$LOCAL_DIR" ]; then
  LOCAL_DIR="$(cd "$LOCAL_DIR" && pwd)"

  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
    if tool_enabled "$tool" && [ -d "$LOCAL_DIR/$local_path" ]; then
      LOCAL_TARGETS+=(--target "$LOCAL_DIR/$local_path")
    fi
  done

  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
    if tool_enabled "$tool"; then
      target="$LOCAL_DIR/$local_path/$SKILL_NAME"
      if [ -L "$target" ] || [ -d "$target" ]; then
        plan_remove "$target" "$target"
      else
        plan skip "$target (not found)"
      fi
    fi
  done
fi

if [ ${#PLAN_PATHS[@]} -eq 0 ]; then
  echo ""
  echo "Nothing to remove. Skill '$SKILL_NAME' was not deployed."
  exit 0
fi

# --- Show the plan -----------------------------------------------------------
# Harvest reads the global roots on every call and the project dirs when
# named; one call covers both, and it runs before the first rm -rf.
if [ -n "$DRY_RUN" ]; then
  harvest_before_removal ${LOCAL_TARGETS[@]+"${LOCAL_TARGETS[@]}"}
fi
i=0
while [ "$i" -lt ${#PLAN_LABELS[@]} ]; do
  plan remove "${PLAN_LABELS[$i]}"
  i=$((i + 1))
done
echo ""

if [ -n "$DRY_RUN" ]; then
  echo "Dry run complete. Nothing was changed."
  exit 0
fi

# --- Confirm -----------------------------------------------------------------
if [ -z "$ASSUME_YES" ]; then
  if [ -t 0 ]; then
    # EOF (Ctrl-D) is a no, not a crash.
    read -rp "Harvest traces and remove ${#PLAN_PATHS[@]} item(s)? [y/N] " answer || answer=""
    case "$answer" in
      y|Y|yes|YES) ;;
      *)
        echo "Aborted. Nothing was changed."
        exit 1
        ;;
    esac
  else
    echo "ERROR: stdin is not a terminal, so nobody can confirm the removal above." >&2
    echo "       Re-run with --yes (-y) to remove, or --dry-run to only see the plan." >&2
    exit 2
  fi
fi

# --- Harvest, then remove ----------------------------------------------------
harvest_before_removal ${LOCAL_TARGETS[@]+"${LOCAL_TARGETS[@]}"}

REMOVED=0
i=0
while [ "$i" -lt ${#PLAN_PATHS[@]} ]; do
  rm -rf "${PLAN_PATHS[$i]}"
  echo "✓ Removed ${PLAN_LABELS[$i]}"
  REMOVED=$((REMOVED + 1))
  i=$((i + 1))
done

echo ""
echo "Done. Removed $REMOVED item(s)."
