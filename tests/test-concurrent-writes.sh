#!/bin/bash
# Two writers on one skill at once must lose nothing: twenty log-feedback.sh
# appenders, then the same twenty racing a harvest and three sync-backs.
# Every path runs against a throwaway skills/ and HOME, never the real ones.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

LOG="$PROJECT_ROOT/scripts/log-feedback.sh"
HARVEST="$PROJECT_ROOT/scripts/harvest-feedback.sh"
SYNC="$PROJECT_ROOT/scripts/sync-skill-back.sh"

# `! cmd` never trips errexit; a negative check has to fail out loud.
refute() {
  if "$@"; then
    echo "expected to fail, but passed: $*" >&2
    exit 1
  fi
}

FAKE_HOME="$TEST_ROOT/home"
FAKE_SKILLS="$TEST_ROOT/repo/skills"
SKILL_DIR="$FAKE_SKILLS/example-skill"
FEEDBACK="$SKILL_DIR/FEEDBACK.jsonl"
CONFIG="$SKILL_DIR/CONFIG.yaml"
export SKILLMONGER_SKILLS_DIR="$FAKE_SKILLS"
export HOME="$FAKE_HOME"
mkdir -p "$SKILL_DIR" "$FAKE_HOME"

cat > "$SKILL_DIR/SKILL.md" <<'EOF'
---
name: example-skill
description: Fixture for concurrent-write tests.
---

# Example Skill
EOF

# Quoted values, a comment and a block no script knows about: every rewrite
# of this file must hand them back untouched.
cat > "$CONFIG" <<'EOF'
skill:
  name: example-skill
  format: 2
  version: "1.0.0"   # quoted on purpose
  updated: 2026-01-01
upstream:
  repo: "https://github.com/example/skills"
compaction:
  cycle_threshold: 15
  last_compaction: null
  iteration_count: 0
custom_block:
  keep_me: true
EOF
ORIGINAL_CONFIG="$(cat "$CONFIG")"

# The file must be exactly the original with iteration_count set to $1.
config_is_original_with_count() {
  [ "$(cat "$CONFIG")" = "$(printf '%s\n' "$ORIGINAL_CONFIG" | sed "s/iteration_count: 0/iteration_count: $1/")" ]
}

# Every line parses, and each prompt in $2.. appears exactly once.
assert_lines() {
  python3 - "$FEEDBACK" "$@" <<'PYEOF'
import json, sys
path, expected_count, prompts = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
raw = open(path, encoding="utf-8").read()
assert raw.endswith("\n"), "file does not end in a newline"
lines = raw.split("\n")[:-1]
assert len(lines) == expected_count, "expected %d lines, got %d" % (expected_count, len(lines))
rows = []
for line in lines:
    try:
        rows.append(json.loads(line))
    except ValueError as exc:
        raise AssertionError("torn line: %r (%s)" % (line, exc))
seen = [r["prompt"] for r in rows]
for prompt in prompts:
    n = seen.count(prompt)
    assert n == 1, "prompt %r appears %d times" % (prompt, n)
assert len(set(seen)) == len(seen), "duplicate lines: %r" % [p for p in seen if seen.count(p) > 1]
PYEOF
}

# Run $1 writers in parallel; each exit status must be 0.
run_writers() {
  local prefix="$1" n="$2" i pids=() pid
  for i in $(seq 0 $((n - 1))); do
    "$LOG" example-skill --outcome $(( (i % 5) + 1 )) --prompt "$prefix $i" --note "" --source user </dev/null \
      > "$TEST_ROOT/$prefix-$i.out" 2>&1 &
    pids+=($!)
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || { echo "a $prefix writer failed:" >&2; cat "$TEST_ROOT/$prefix-"*.out >&2; exit 1; }
  done
}

# --- Twenty appenders, one skill ------------------------------------------

run_writers writer 20
WRITER_PROMPTS=()
for i in $(seq 0 19); do WRITER_PROMPTS+=("writer $i"); done

assert_lines 20 "${WRITER_PROMPTS[@]}"
grep -q '^  iteration_count: 20$' "$CONFIG"
config_is_original_with_count 20
[ ! -e "$SKILL_DIR/.lock" ]
refute ls "$SKILL_DIR"/CONFIG.yaml.tmp.* 2>/dev/null

# --- Twenty appenders racing a harvest ------------------------------------

# A deployed copy in the store with five traces of its own.
STORE="$FAKE_HOME/.local/share/skillmonger/skills/example-skill"
mkdir -p "$STORE"
cp "$SKILL_DIR/SKILL.md" "$CONFIG" "$STORE/"
HARVEST_PROMPTS=()
for i in $(seq 0 4); do
  printf '%s\n' "{\"ts\":\"2026-08-30T0$i:00:00Z\",\"skill\":\"example-skill\",\"version\":\"1.0.0\",\"prompt\":\"harvested $i\",\"outcome\":4,\"note\":\"\",\"source\":\"llm\",\"schema_version\":1}" \
    >> "$STORE/FEEDBACK.jsonl"
  HARVEST_PROMPTS+=("harvested $i")
done

"$HARVEST" example-skill > "$TEST_ROOT/harvest-1.out" 2>&1 &
HARVEST_PID=$!
run_writers racer 20
wait "$HARVEST_PID" || { cat "$TEST_ROOT/harvest-1.out" >&2; exit 1; }
RACER_PROMPTS=()
for i in $(seq 0 19); do RACER_PROMPTS+=("racer $i"); done

assert_lines 45 "${WRITER_PROMPTS[@]}" "${RACER_PROMPTS[@]}" "${HARVEST_PROMPTS[@]}"
grep -q '^  iteration_count: 45$' "$CONFIG"
config_is_original_with_count 45
[ ! -e "$SKILL_DIR/.lock" ]

# Harvest is still idempotent afterwards.
"$HARVEST" example-skill >/dev/null
assert_lines 45 "${HARVEST_PROMPTS[@]}"
grep -q '^  iteration_count: 45$' "$CONFIG"

# --- Ten appenders racing three sync-backs of the same deployed copy ------

DEPLOYED="$TEST_ROOT/deployed/example-skill"
mkdir -p "$DEPLOYED"
cp "$SKILL_DIR/SKILL.md" "$DEPLOYED/"
sed 's/version: "1.0.0"/version: "1.1.0"/; s/updated: 2026-01-01/updated: 2026-08-31/' "$CONFIG" > "$DEPLOYED/CONFIG.yaml"
SYNC_PROMPTS=()
for i in $(seq 0 4); do
  printf '%s\n' "{\"ts\":\"2026-08-31T0$i:00:00Z\",\"skill\":\"example-skill\",\"version\":\"1.1.0\",\"prompt\":\"synced $i\",\"outcome\":5,\"note\":\"\",\"source\":\"user\",\"schema_version\":1}" \
    >> "$DEPLOYED/FEEDBACK.jsonl"
  SYNC_PROMPTS+=("synced $i")
done

SYNC_PIDS=()
for i in 1 2 3; do
  "$SYNC" example-skill --from "$DEPLOYED" --auto > "$TEST_ROOT/sync-$i.out" 2>&1 &
  SYNC_PIDS+=($!)
done
run_writers late 10
for pid in "${SYNC_PIDS[@]}"; do
  wait "$pid" || { cat "$TEST_ROOT"/sync-*.out >&2; exit 1; }
done
LATE_PROMPTS=()
for i in $(seq 0 9); do LATE_PROMPTS+=("late $i"); done

# Three syncs, five entries, appended once.
assert_lines 60 "${SYNC_PROMPTS[@]}" "${LATE_PROMPTS[@]}"
[ "$(grep -c '"prompt":"synced' "$FEEDBACK")" -eq 5 ]
# Ten bumps on top of 45, and the five synced entries are counted too.
grep -q '^  iteration_count: 60$' "$CONFIG"
# The version merged in, in the quotes the source used, comment intact;
# everything else byte for byte.
grep -q '^  version: "1.1.0"   # quoted on purpose$' "$CONFIG"
grep -q '^  repo: "https://github.com/example/skills"$' "$CONFIG"
grep -q '^  keep_me: true$' "$CONFIG"
grep -q '^  updated: 2026-08-31$' "$CONFIG"
[ "$(cat "$CONFIG")" = "$(printf '%s\n' "$ORIGINAL_CONFIG" | sed 's/iteration_count: 0/iteration_count: 60/; s/version: "1.0.0"/version: "1.1.0"/; s/updated: 2026-01-01/updated: 2026-08-31/')" ]
[ ! -e "$SKILL_DIR/.lock" ]

# --- The lock itself --------------------------------------------------------

# A lock older than SKILLMONGER_LOCK_STALE is a dead holder's: stolen, with a warning.
mkdir "$SKILL_DIR/.lock"
echo 99999 > "$SKILL_DIR/.lock/pid"
touch -t 202001010000 "$SKILL_DIR/.lock"
SKILLMONGER_LOCK_STALE=1 "$LOG" example-skill --outcome 3 --prompt "after stale" --note "" --source user </dev/null \
  > "$TEST_ROOT/stale.out" 2>&1
grep -q 'stale lock' "$TEST_ROOT/stale.out"
grep -q '"prompt":"after stale"' "$FEEDBACK"
grep -q '^  iteration_count: 61$' "$CONFIG"
[ ! -e "$SKILL_DIR/.lock" ]

# A fresh lock someone holds is waited on, then given up without writing.
mkdir "$SKILL_DIR/.lock"
echo $$ > "$SKILL_DIR/.lock/pid"
set +e
SKILLMONGER_LOCK_WAIT=1 "$LOG" example-skill --outcome 3 --prompt "while held" --note "" --source user </dev/null \
  > "$TEST_ROOT/held.out" 2>&1
STATUS=$?
set -e
[ "$STATUS" -ne 0 ]
grep -q "could not lock" "$TEST_ROOT/held.out"
refute grep -q '"prompt":"while held"' "$FEEDBACK"
grep -q '^  iteration_count: 61$' "$CONFIG"
# The holder's lock is not ours to remove.
[ -d "$SKILL_DIR/.lock" ]
rmdir "$SKILL_DIR/.lock/" 2>/dev/null || rm -rf "$SKILL_DIR/.lock"

# The python side honours the same lock: a held lock makes harvest skip the
# skill, not write past it.
mkdir "$SKILL_DIR/.lock"
printf '%s\n' '{"ts":"2026-08-31T09:00:00Z","skill":"example-skill","prompt":"during hold","outcome":4}' \
  >> "$STORE/FEEDBACK.jsonl"
SKILLMONGER_LOCK_WAIT=1 "$HARVEST" example-skill > "$TEST_ROOT/harvest-held.out" 2>&1 || true
grep -q "could not lock" "$TEST_ROOT/harvest-held.out"
refute grep -q '"prompt":"during hold"' "$FEEDBACK"
rm -rf "$SKILL_DIR/.lock"
"$HARVEST" example-skill >/dev/null
grep -q '"prompt":"during hold"' "$FEEDBACK"
grep -q '^  iteration_count: 62$' "$CONFIG"

echo "concurrent-writes tests passed"
