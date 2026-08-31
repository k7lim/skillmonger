#!/bin/bash
# harvest-feedback.sh - Bring traces home from every deployed copy (ADR 0002)
#
# Agents run deployed copies of skills in places that cannot reach this repo,
# so a skill's epilogue appends its trace to the deployed copy's
# FEEDBACK.jsonl. This unions those files into skills/<name>/FEEDBACK.jsonl:
# existing lines are never rewritten, new ones are appended, `source` is
# normalised, and compaction.iteration_count is recomputed from the result.
#
# deploy-skill.sh runs this before it removes a deployed copy, so a redeploy
# no longer destroys the traces that copy accumulated.
#
# Concurrency: each skill is read, appended and recounted under that skill's
# lock (skills/<name>/.lock/, lib/skill_lock.py -- the same lock
# log-feedback.sh and sync-skill-back.sh take), so a gate run logging traces
# while this harvests loses no line and ends with the count it should have.
# CONFIG.yaml is replaced by rename, never written in place. A deployed
# copy is only read, without a lock: a line its agent is mid-write is skipped
# as unparseable and comes home whole on the next harvest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="${SKILLMONGER_SKILLS_DIR:-$PROJECT_ROOT/skills}"

# The deploy targets are defined once, next to the deploy script that writes
# them; a target this script does not know about is a target whose traces the
# next deploy destroys.
# shellcheck source=lib/deploy-targets.sh
. "$SCRIPT_DIR/lib/deploy-targets.sh"

usage() {
  cat << EOF
Usage: $(basename "$0") [skill-name] [options]

Harvests traces from every deployed copy into skills/<name>/FEEDBACK.jsonl.
With no skill name, harvests every skill. Idempotent: a second run adds
nothing.

Options:
  --target DIR   Also read deployed copies under DIR (repeatable; use for
                 project-local deployments made with deploy-skill.sh --local)
  --quiet        Say nothing when there was nothing to harvest
  --help         Show this help message

Environment:
  SKILLMONGER_SKILLS_DIR  Repo-side skills/ directory (default: $PROJECT_ROOT/skills)
  YOLOBOX_SANDBOX_HOME    Sandbox home holding SRT copies

Examples:
  $(basename "$0")                  # every skill, every deploy target
  $(basename "$0") handoff          # one skill
  $(basename "$0") handoff --target ./.claude/skills
EOF
}

SKILL_NAME=""
QUIET=""
EXTRA_TARGETS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --target)
      EXTRA_TARGETS+=("$2")
      shift 2
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -z "$SKILL_NAME" ]; then
        SKILL_NAME="$1"
      else
        echo "Error: Unexpected argument $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if ! command -v python3 &> /dev/null; then
  echo "Error: python3 is required to harvest traces (JSON parsing and dedupe)." >&2
  echo "       Install python3, or the deployed copies keep their traces." >&2
  exit 2
fi

ARGS=(--skills-dir "$SKILLS_DIR")
if [ -n "$QUIET" ]; then
  ARGS+=(--quiet)
fi
if [ -n "$SKILL_NAME" ]; then
  ARGS+=(--skill "$SKILL_NAME")
fi

while IFS= read -r root; do
  [ -n "$root" ] && ARGS+=(--target "$root")
done < <(deploy_target_roots)

if [ ${#EXTRA_TARGETS[@]} -gt 0 ]; then
  for root in "${EXTRA_TARGETS[@]}"; do
    ARGS+=(--target "$root")
  done
fi

exec python3 "$SCRIPT_DIR/lib/harvest.py" "${ARGS[@]}"
