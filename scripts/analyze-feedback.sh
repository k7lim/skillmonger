#!/bin/bash
# analyze-feedback.sh - Summarize feedback across all skills
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$PROJECT_ROOT/skills"

# shellcheck source=lib/skill-name.sh
. "$SCRIPT_DIR/lib/skill-name.sh"

usage() {
  cat << EOF
Usage: $(basename "$0") [options]

Analyzes FEEDBACK.jsonl files across all skills.

Options:
  --skill NAME    Analyze only the named skill
  --version VER   Filter to a specific version
  --export        Output raw JSONL (all entries, for piping to jq)
  --impact [NAME] Group outcomes by the skill version that produced them
  --no-harvest    Skip the harvest and read skills/ as it stands
  --help          Show this help message

Harvests first (see harvest-feedback.sh): a trace reaches this repo only
through a harvest, so a summary taken without one summarises whatever the
last deploy happened to leave behind. The harvest reports on stderr.

Examples:
  $(basename "$0")                              # summary of all skills
  $(basename "$0") --skill centers-of-excellence # one skill detail
  $(basename "$0") --impact project-juggler     # did the 1.1.0 edit help?
  $(basename "$0") --export | jq '.outcome'     # raw data pipeline
EOF
}

FILTER_SKILL=""
FILTER_VERSION=""
EXPORT_MODE=false
IMPACT_MODE=false
RUN_HARVEST=true

while [[ $# -gt 0 ]]; do
  case $1 in
    --skill)
      skill_name_require "$2"
      FILTER_SKILL="$2"
      shift 2
      ;;
    --version)
      FILTER_VERSION="$2"
      shift 2
      ;;
    --export)
      EXPORT_MODE=true
      shift
      ;;
    --impact)
      IMPACT_MODE=true
      # The skill name is optional; without one, every skill with traces.
      if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then
        skill_name_require "$2"
        FILTER_SKILL="$2"
        shift
      fi
      shift
      ;;
    --no-harvest)
      RUN_HARVEST=false
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option $1"
      usage
      exit 1
      ;;
  esac
done

# --- Harvest first ---
#
# Agents write their traces into the deployed copy, and a harvest is the only
# way one reaches this repo (ADR 0002), so analysing skills/ without harvesting
# analyses whatever the last deploy left behind. The harvester reports on
# stderr: --export stays a clean JSONL stream, and the summary below is
# byte-identical to a --no-harvest run.

if [ "$RUN_HARVEST" = true ] && [ -x "$SCRIPT_DIR/harvest-feedback.sh" ]; then
  harvest_args=()
  if [ -n "$FILTER_SKILL" ]; then
    harvest_args+=("$FILTER_SKILL")
  fi
  harvest_args+=(--quiet)
  if ! "$SCRIPT_DIR/harvest-feedback.sh" "${harvest_args[@]}" >&2; then
    echo "Warning: harvest failed; reporting the traces already in skills/." >&2
  fi
fi

# --- Impact mode ---
#
# Impact is the change in outcomes from one skill version to the next, and
# every trace already names the version it ran against, so it is computed here
# and never stored (CONTEXT.md: Impact). scripts/lib/impact.py owns the
# grouping so gate-skill.sh can import it for a baseline.

if [ "$IMPACT_MODE" = true ]; then
  if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required for --impact (JSON parsing)." >&2
    exit 2
  fi
  impact_args=(--skills-dir "$SKILLS_DIR")
  if [ -n "$FILTER_SKILL" ]; then
    impact_args+=("$FILTER_SKILL")
  fi
  exec python3 "$SCRIPT_DIR/lib/impact.py" "${impact_args[@]}"
fi

# --- Collect feedback files ---

feedback_files=()
if [ -n "$FILTER_SKILL" ]; then
  f="$SKILLS_DIR/$FILTER_SKILL/FEEDBACK.jsonl"
  if [ -f "$f" ]; then
    feedback_files+=("$f")
  else
    echo "No feedback found for skill: $FILTER_SKILL"
    exit 0
  fi
else
  for skill_dir in "$SKILLS_DIR"/*/; do
    f="$skill_dir/FEEDBACK.jsonl"
    if [ -f "$f" ]; then
      feedback_files+=("$f")
    fi
  done
fi

if [ ${#feedback_files[@]} -eq 0 ]; then
  echo "No feedback data found."
  echo "Log feedback with: scripts/log-feedback.sh <skill-name>"
  exit 0
fi

# --- Export mode ---

if [ "$EXPORT_MODE" = true ]; then
  for f in "${feedback_files[@]}"; do
    if [ -n "$FILTER_VERSION" ]; then
      grep "\"version\":\"$FILTER_VERSION\"" "$f" 2>/dev/null || true
    else
      cat "$f"
    fi
  done
  exit 0
fi

# --- Summary mode ---

echo "Feedback Summary"
echo "================"
echo ""

total_entries=0
total_outcome_sum=0

for f in "${feedback_files[@]}"; do
  skill_name=$(basename "$(dirname "$f")")
  entries=$(wc -l < "$f" | xargs)

  if [ "$entries" -eq 0 ]; then
    continue
  fi

  # Filter by version if specified
  if [ -n "$FILTER_VERSION" ]; then
    filtered=$(grep -c "\"version\":\"$FILTER_VERSION\"" "$f" 2>/dev/null || echo "0")
    if [ "$filtered" -eq 0 ]; then
      continue
    fi
    entries="$filtered"
  fi

  echo "--- $skill_name ($entries entries) ---"

  # Calculate stats using awk (no jq dependency)
  if [ -n "$FILTER_VERSION" ]; then
    data=$(grep "\"version\":\"$FILTER_VERSION\"" "$f" 2>/dev/null || true)
  else
    data=$(cat "$f")
  fi

  # Extract outcomes and compute stats
  # `|| true`: a skill whose traces all score with `score` instead of
  # `outcome` matches nothing here, and under pipefail that ended the run.
  stats=$(echo "$data" | grep -oE '"outcome":[1-5]' | grep -oE '[1-5]' | awk '
    BEGIN { sum=0; count=0; s1=0; s2=0; s3=0; s4=0; s5=0 }
    {
      sum += $1; count++
      if ($1==1) s1++
      if ($1==2) s2++
      if ($1==3) s3++
      if ($1==4) s4++
      if ($1==5) s5++
    }
    END {
      if (count > 0) {
        avg = sum / count
        printf "avg=%.1f count=%d s1=%d s2=%d s3=%d s4=%d s5=%d sum=%d\n", avg, count, s1, s2, s3, s4, s5, sum
      }
    }
  ' || true)

  if [ -n "$stats" ]; then
    eval "$stats"
    echo "  Average: $avg / 5.0"
    echo "  Distribution: 1=$s1  2=$s2  3=$s3  4=$s4  5=$s5"
    total_entries=$((total_entries + count))
    total_outcome_sum=$((total_outcome_sum + sum))
  fi

  # Source breakdown
  llm_count=$(echo "$data" | grep -c '"source":"llm"' || true)
  script_count=$(echo "$data" | grep -c '"source":"script"' || true)
  user_count=$(echo "$data" | grep -c '"source":"user"' || true)
  echo "  Sources: llm=$llm_count  script=$script_count  user=$user_count"

  # Failed checks. Only script-scored traces carry `checks`, so most skills
  # print nothing here. Failure is read from the value, never from the name: a
  # boolean false, an object whose pass/ok/status field says so, or a status
  # string (fail, failed, error, no, missing). A number is a measurement and
  # not a verdict -- centers-of-excellence writes entry_count: true beside
  # entry_count_value: 10 -- so numbers never count as failures.
  # `[[ == ]]` and not `grep -q`: under pipefail, grep -q closing the pipe
  # early makes printf exit 141 and the whole test read as false.
  if command -v python3 &> /dev/null && [[ "$data" == *'"checks"'* ]]; then
    checks_summary=$(printf '%s\n' "$data" | python3 -c '
import json, sys
from collections import Counter

FAIL_WORDS = ("fail", "failed", "error", "false", "no", "missing")
PASS_WORDS = ("pass", "passed", "ok", "true", "yes", "skip", "skipped")


def verdict(value, depth=0):
    # True when the value says the check failed, False when it passed, None
    # when it is a measurement rather than a verdict.
    if isinstance(value, bool):
        return not value
    if isinstance(value, dict) and depth < 2:
        for key in ("pass", "passed", "ok", "success", "status", "result"):
            if key in value:
                return verdict(value[key], depth + 1)
        return None
    if isinstance(value, str):
        word = value.strip().lower()
        if word in FAIL_WORDS:
            return True
        if word in PASS_WORDS:
            return False
    return None


def entries(checks):
    if isinstance(checks, dict):
        return list(checks.items())
    if isinstance(checks, list):
        out = []
        for index, item in enumerate(checks):
            if isinstance(item, dict):
                name = item.get("name") or item.get("check") or ("#%d" % index)
                out.append((name, item))
            else:
                out.append(("#%d" % index, item))
        return out
    return []


carried = 0
failed = Counter()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        trace = json.loads(line)
    except ValueError:
        continue
    if not isinstance(trace, dict):
        continue
    checks = trace.get("checks")
    if not checks:
        continue
    carried += 1
    for name, value in entries(checks):
        if verdict(value) is True:
            failed[str(name)] += 1

if carried:
    total = sum(failed.values())
    line = "  Checks: %d trace(s) carry checks, %d failed" % (carried, total)
    if failed:
        line += " (%s)" % ", ".join(
            "%s=%d" % (name, count) for name, count in failed.most_common(5)
        )
    print(line)
' || true)
    if [ -n "$checks_summary" ]; then
      echo "$checks_summary"
    fi
  fi

  # Latest entry timestamp
  latest_ts=$(tail -1 "$f" | grep -oE '"ts":"[^"]*"' | head -1 | sed 's/"ts":"//;s/"//' || echo "unknown")
  echo "  Latest: $latest_ts"

  # Version breakdown if multiple versions
  versions=$(echo "$data" | grep -oE '"version":"[^"]*"' | sort -u | sed 's/"version":"//;s/"//' || true)
  version_count=$(echo "$versions" | wc -l | xargs)
  if [ "$version_count" -gt 1 ]; then
    echo "  Versions: $version_count ($versions)"
  fi

  echo ""
done

# --- Overall ---

if [ "$total_entries" -gt 0 ]; then
  overall_avg=$(awk "BEGIN {printf \"%.1f\", $total_outcome_sum / $total_entries}")
  echo "================"
  echo "Total: $total_entries entries across ${#feedback_files[@]} skill(s)"
  echo "Overall average: $overall_avg / 5.0"
fi
