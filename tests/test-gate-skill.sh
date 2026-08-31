#!/bin/bash
# Everything about a gate run that does not need a live model: the refusals,
# the blind copy, fixture discovery, the baseline lookup, the regression
# arithmetic and the expect.json floor. The live half (the runner invocation
# and log-feedback.sh) is exercised by running the gate on
# centers-of-excellence for real.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$PROJECT_ROOT/scripts/gate-skill.sh"
GATE_PY="$PROJECT_ROOT/scripts/lib/gate.py"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

SKILLS="$TEST_ROOT/skills"
SKILL_DIR="$SKILLS/example-skill"
mkdir -p "$SKILL_DIR/scripts" "$SKILL_DIR/fixtures" "$SKILL_DIR/memo/patterns"

cat > "$SKILL_DIR/SKILL.md" <<'EOF'
---
name: example-skill
description: Fixture for gate tests.
---

# Example Skill
EOF

cat > "$SKILL_DIR/MEMO.md" <<'EOF'
# example-skill - MEMO
EOF
echo "a pattern" > "$SKILL_DIR/memo/patterns/slug.md"

cat > "$SKILL_DIR/scripts/evaluate.sh" <<'EOF'
#!/bin/bash
cat > /dev/null
echo '{"outcome":4,"note":"","checks":{},"source":"script"}'
EOF
chmod +x "$SKILL_DIR/scripts/evaluate.sh"

write_config() {
  cat > "$SKILL_DIR/CONFIG.yaml" <<EOF
skill:
  name: example-skill
  version: 1.0.0
  format: 2
loading:
  primary: SKILL.md
  on_failure: MEMO.md
  always_load:
    - CONFIG.yaml
evaluation:
  mode: ${1:-programmatic}
  script: scripts/evaluate.sh
  blind: true
  tolerance: 0.5
${2:-}
EOF
}

expect_exit() {
  local want="$1"; shift
  local got=0
  "$@" > "$TEST_ROOT/out" 2> "$TEST_ROOT/err" || got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL: expected exit $want, got $got, from: $*"
    cat "$TEST_ROOT/out" "$TEST_ROOT/err"
    exit 1
  fi
}

says() {
  if ! grep -q -- "$1" "$TEST_ROOT/out" "$TEST_ROOT/err"; then
    echo "FAIL: expected output to mention: $1"
    cat "$TEST_ROOT/out" "$TEST_ROOT/err"
    exit 1
  fi
}

# --- gate.py's own arithmetic ----------------------------------------------

python3 "$GATE_PY" --self-test > /dev/null

# --- Refusals (exit 3) -----------------------------------------------------

# Qualitative: no evaluate script means no oracle.
write_config qualitative
expect_exit 3 "$GATE" "$SKILL_DIR"
says "not programmatic or hybrid"

# No fixtures: the message names the layout so it can be acted on.
write_config programmatic
expect_exit 3 "$GATE" "$SKILL_DIR"
says "fixtures/<case>.prompt.md"
says "0 fixture(s)"

# Two fixtures is still not three.
echo "first prompt" > "$SKILL_DIR/fixtures/alpha.prompt.md"
echo "second prompt" > "$SKILL_DIR/fixtures/beta.prompt.md"
expect_exit 3 "$GATE" "$SKILL_DIR"
says "2 fixture(s)"

echo "third prompt" > "$SKILL_DIR/fixtures/gamma.prompt.md"

# An evaluator that does not score this skill's own output (writing-voice-coach).
write_config programmatic "  script_emits_outcome: false"
expect_exit 3 "$GATE" "$SKILL_DIR"
says "script_emits_outcome"

# runner is reserved: anything but claude is refused, not guessed at.
write_config programmatic "  runner: codex"
expect_exit 3 "$GATE" "$SKILL_DIR"
says "runner is reserved"

# A usage line naming an input the gate cannot produce.
write_config programmatic "  script_usage: scripts/evaluate.sh <project-dir>"
expect_exit 3 "$GATE" "$SKILL_DIR"
says "cannot supply"

write_config programmatic

# --- The plan (--dry-run never invokes the model) --------------------------

expect_exit 0 "$GATE" "$SKILL_DIR" --dry-run
says "the model was not invoked"
says "alpha"
says "MEMO.md"
says "loading.on_failure"
says "no baseline"

# A live run outside the repo's skills/ is refused before anything is logged:
# log-feedback.sh only ever writes into skills/.
expect_exit 2 "$GATE" "$SKILL_DIR"
says "is not under"

# --- The blind copy --------------------------------------------------------

python3 "$GATE_PY" blind "$SKILL_DIR" "$TEST_ROOT/blind" > /dev/null
[ ! -e "$TEST_ROOT/blind/MEMO.md" ] || { echo "FAIL: MEMO.md survived the blind copy"; exit 1; }
[ ! -e "$TEST_ROOT/blind/memo" ] || { echo "FAIL: memo/ survived the blind copy"; exit 1; }
grep -q "on_failure" "$TEST_ROOT/blind/CONFIG.yaml" && { echo "FAIL: loading.on_failure survived"; exit 1; }
grep -q "always_load" "$TEST_ROOT/blind/CONFIG.yaml" || { echo "FAIL: the rest of loading: was dropped"; exit 1; }
grep -q "primary: SKILL.md" "$TEST_ROOT/blind/CONFIG.yaml" || { echo "FAIL: loading.primary was dropped"; exit 1; }
[ -f "$SKILL_DIR/MEMO.md" ] || { echo "FAIL: the deployed source lost its wiki"; exit 1; }

# --- Fixture discovery -----------------------------------------------------

found="$(python3 "$GATE_PY" fixtures "$SKILL_DIR" | paste -sd, -)"
[ "$found" = "alpha,beta,gamma" ] || { echo "FAIL: fixtures: $found"; exit 1; }

# --- The baseline, read out of FEEDBACK.jsonl ------------------------------

cat > "$SKILL_DIR/FEEDBACK.jsonl" <<'EOF'
{"ts":"2026-08-01T00:00:00Z","skill":"example-skill","version":"0.9.0","prompt":"a","outcome":5,"note":"","source":"script","gate":true,"fixture":"alpha","schema_version":1}
{"ts":"2026-08-01T00:01:00Z","skill":"example-skill","version":"0.9.0","prompt":"b","outcome":4,"note":"","source":"script","gate":true,"fixture":"beta","schema_version":1}
{"ts":"2026-08-01T00:02:00Z","skill":"example-skill","version":"0.9.0","prompt":"c","outcome":3,"note":"","source":"script","gate":true,"fixture":"gamma","schema_version":1}
{"ts":"2026-08-02T00:00:00Z","skill":"example-skill","version":"1.0.0","prompt":"real run","outcome":1,"note":"","source":"llm","schema_version":1}
EOF

base="$(python3 "$GATE_PY" baseline "$SKILLS" example-skill \
  --fixtures "alpha beta gamma" --current-version 1.0.0)"
echo "$base" | grep -q '"version": "0.9.0"' || { echo "FAIL: baseline version: $base"; exit 1; }
echo "$base" | grep -q '"alpha": 5' || { echo "FAIL: baseline outcomes: $base"; exit 1; }

expect_exit 0 "$GATE" "$SKILL_DIR" --dry-run
says "version 0.9.0"

# A real trace is never a baseline, however recent.
onlyreal="$(python3 "$GATE_PY" baseline "$SKILLS" example-skill \
  --fixtures "delta" --current-version 1.0.0)"
echo "$onlyreal" | grep -q '"label": "none"' || { echo "FAIL: $onlyreal"; exit 1; }

# --- The verdict -----------------------------------------------------------

verdict() {
  printf '%s' "$1" | python3 "$GATE_PY" compare > "$TEST_ROOT/out" 2>&1
}

# Holding steady against the baseline passes.
verdict '{"current":{"alpha":5,"beta":4,"gamma":3},"baseline":{"alpha":5,"beta":4,"gamma":3},"tolerance":0.5}'

# One fixture two points down is a regression even though the mean rose.
if verdict '{"current":{"alpha":3,"beta":5,"gamma":5},"baseline":{"alpha":5,"beta":4,"gamma":3},"tolerance":0.5,"revert":"git checkout deadbee -- skills/example-skill/SKILL.md"}'; then
  echo "FAIL: a two-point fixture drop should be a regression"; cat "$TEST_ROOT/out"; exit 1
fi
grep -q "git checkout deadbee -- skills/example-skill/SKILL.md" "$TEST_ROOT/out" \
  || { echo "FAIL: the revert line was not printed"; cat "$TEST_ROOT/out"; exit 1; }

# One point down everywhere trips the mean instead.
if verdict '{"current":{"alpha":4,"beta":3,"gamma":2},"baseline":{"alpha":5,"beta":4,"gamma":3},"tolerance":0.5}'; then
  echo "FAIL: a 1.0 mean drop should exceed a 0.5 tolerance"; cat "$TEST_ROOT/out"; exit 1
fi
verdict '{"current":{"alpha":4,"beta":3,"gamma":2},"baseline":{"alpha":5,"beta":4,"gamma":3},"tolerance":1.0}'

# The expect.json floor is a claim about the skill, so it bites with no baseline.
echo '{"min_outcome": 4}' > "$SKILL_DIR/fixtures/alpha.expect.json"
[ "$(python3 "$GATE_PY" expect "$SKILL_DIR")" = '{"alpha": {"min_outcome": 4}}' ] \
  || { echo "FAIL: expect.json not read"; exit 1; }
if verdict '{"current":{"alpha":3},"baseline":{},"expect":{"alpha":{"min_outcome":4}},"tolerance":0.5}'; then
  echo "FAIL: a fixture under its floor should be a regression"; cat "$TEST_ROOT/out"; exit 1
fi

echo "test-gate-skill.sh: ok"
