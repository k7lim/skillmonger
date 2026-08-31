#!/bin/bash
# Everything about the pre-push gate step that does not need a live model:
# stdin parsing (existing branch, new branch with a known default, new
# branch falling back to --not --remotes, delete, multi-line), which skills
# get gated (programmatic/hybrid SKILL.md changes only, deduped once per
# push), and what each of gate-skill.sh's exit codes does (block, block
# with the fixture message, block with the revert line, or report-only).
#
# The gate itself is stubbed via SKILLMONGER_GATE_CMD so no model ever runs;
# the validation loop is exercised for real (against a throwaway skills/
# tree) by symlinking the repo's own scripts/validate-skill.sh into the
# temp repo, rather than adding a test-only bypass to the hook.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REAL_HOOK="$PROJECT_ROOT/hooks/pre-push"
REAL_VALIDATE="$PROJECT_ROOT/scripts/validate-skill.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

REMOTE_DIR="$TEST_ROOT/remote.git"
REPO_DIR="$TEST_ROOT/repo"
FAKE_GATE="$TEST_ROOT/fake-gate.sh"
GATE_LOG="$TEST_ROOT/gate-calls.log"

git init -q --bare "$REMOTE_DIR"

git init -q "$REPO_DIR"
git -C "$REPO_DIR" checkout -q -b main
git -C "$REPO_DIR" config user.email "test@example.com"
git -C "$REPO_DIR" config user.name "Test"
git -C "$REPO_DIR" remote add origin "$REMOTE_DIR"

mkdir -p "$REPO_DIR/scripts"
ln -s "$REAL_VALIDATE" "$REPO_DIR/scripts/validate-skill.sh"

# --- A fake gate-skill.sh: decides purely by which skill dir it was asked ---
# --- about, so the hook's own logic is what's under test, not a model. -----
cat > "$FAKE_GATE" <<'EOF'
#!/bin/bash
echo "$1" >> "$GATE_LOG_FILE"
case "$1" in
  */prog-with-fixtures/)
    echo "gate: prog-with-fixtures 1.0.0 (programmatic, runner claude)"
    exit 0
    ;;
  */prog-no-fixtures/)
    cat <<'MSG'
prog-no-fixtures cannot be gated:
  - prog-no-fixtures has 0 fixture(s); the gate needs at least 3.
    A fixture is a held-out prompt at
      skills/prog-no-fixtures/fixtures/<case>.prompt.md
MSG
    exit 3
    ;;
  */prog-regressed/)
    cat <<'MSG'
prog-regressed 1.0.1 (programmatic, runner claude)
  REGRESSION:
  The gate never reverts. To put the previous SKILL.md back:
    git checkout deadbee5 -- skills/prog-regressed/SKILL.md
MSG
    exit 1
    ;;
  */prog-other-refusal/)
    cat <<'MSG'
prog-other-refusal cannot be gated:
  - prog-other-refusal declares evaluation.script_emits_outcome: false.
    Its evaluate script does not score this skill's own output.
MSG
    exit 3
    ;;
  *)
    echo "fake-gate.sh: unexpected argument: $1" >&2
    exit 9
    ;;
esac
EOF
chmod +x "$FAKE_GATE"

# --- Skills ------------------------------------------------------------

write_skill_md() {
  local dir="$1" name="$2"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: Fixture skill for pre-push hook tests.
---

# ${name}

v1
EOF
}

touch_skill_md() {
  # A real content edit that keeps the frontmatter valid.
  echo "touched at $(date +%s%N)" >> "$1/SKILL.md"
}

write_evaluate_script() {
  # validate-skill.sh requires evaluation.script to exist and be executable
  # for programmatic/hybrid mode; content is never run (the gate is stubbed).
  mkdir -p "$1/scripts"
  cat > "$1/scripts/evaluate.sh" <<'EOF'
#!/bin/bash
cat > /dev/null
echo '{"outcome":4,"note":"","checks":{},"source":"script"}'
EOF
  chmod +x "$1/scripts/evaluate.sh"
}

SKILLS="$REPO_DIR/skills"

write_skill_md "$SKILLS/prog-with-fixtures" "prog-with-fixtures"
cat > "$SKILLS/prog-with-fixtures/CONFIG.yaml" <<'EOF'
skill:
  name: prog-with-fixtures
  version: 1.0.0
  format: 2
evaluation:
  mode: programmatic
  script: scripts/evaluate.sh
  blind: true
  tolerance: 0.5
EOF
mkdir -p "$SKILLS/prog-with-fixtures/fixtures"
for f in alpha beta gamma; do
  echo "prompt $f" > "$SKILLS/prog-with-fixtures/fixtures/$f.prompt.md"
done
write_evaluate_script "$SKILLS/prog-with-fixtures"

write_skill_md "$SKILLS/prog-no-fixtures" "prog-no-fixtures"
cat > "$SKILLS/prog-no-fixtures/CONFIG.yaml" <<'EOF'
skill:
  name: prog-no-fixtures
  version: 1.0.0
  format: 2
evaluation:
  mode: programmatic
  script: scripts/evaluate.sh
  blind: true
  tolerance: 0.5
EOF
write_evaluate_script "$SKILLS/prog-no-fixtures"

write_skill_md "$SKILLS/prog-regressed" "prog-regressed"
cat > "$SKILLS/prog-regressed/CONFIG.yaml" <<'EOF'
skill:
  name: prog-regressed
  version: 1.0.1
  format: 2
evaluation:
  mode: programmatic
  script: scripts/evaluate.sh
  blind: true
  tolerance: 0.5
EOF
mkdir -p "$SKILLS/prog-regressed/fixtures"
for f in alpha beta gamma; do
  echo "prompt $f" > "$SKILLS/prog-regressed/fixtures/$f.prompt.md"
done
write_evaluate_script "$SKILLS/prog-regressed"

write_skill_md "$SKILLS/prog-other-refusal" "prog-other-refusal"
cat > "$SKILLS/prog-other-refusal/CONFIG.yaml" <<'EOF'
skill:
  name: prog-other-refusal
  version: 1.0.0
  format: 2
evaluation:
  mode: programmatic
  script: scripts/evaluate.sh
  script_emits_outcome: false
EOF
write_evaluate_script "$SKILLS/prog-other-refusal"

write_skill_md "$SKILLS/qual-skill" "qual-skill"
cat > "$SKILLS/qual-skill/CONFIG.yaml" <<'EOF'
skill:
  name: qual-skill
  version: 1.0.0
  format: 2
evaluation:
  mode: qualitative
EOF

# Format 1: no CONFIG.yaml at all.
write_skill_md "$SKILLS/format1-skill" "format1-skill"

git -C "$REPO_DIR" add -A
git -C "$REPO_DIR" commit -q -m "Seed skills"
SEED_SHA="$(git -C "$REPO_DIR" rev-parse HEAD)"
git -C "$REPO_DIR" push -q origin main
git -C "$REPO_DIR" remote set-head origin main
# Tests 1-6 advance local main without pushing again (the "existing branch"
# case gets its remote sha straight from stdin, not from the real remote),
# so refs/remotes/origin/main stays at SEED_SHA. The new-branch tests (7, 8)
# below branch from SEED_SHA rather than from main, so origin/main's stale
# tracking ref stays a true merge-base / --not --remotes boundary instead of
# swallowing every commit main has picked up in between.

# --- Test helpers --------------------------------------------------------

hook() {
  ( cd "$REPO_DIR" \
    && GATE_LOG_FILE="$GATE_LOG" SKILLMONGER_GATE_CMD="$FAKE_GATE" \
       "$REAL_HOOK" origin "https://example.invalid" )
}

expect_exit_stdin() {
  local stdin_data="$1" want="$2" got=0
  printf '%s' "$stdin_data" | hook > "$TEST_ROOT/out" 2> "$TEST_ROOT/err" || got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL: expected exit $want, got $got"
    echo "--- stdin ---"; printf '%s\n' "$stdin_data"
    echo "--- output ---"; cat "$TEST_ROOT/out" "$TEST_ROOT/err"
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

says_not() {
  if grep -q -- "$1" "$TEST_ROOT/out" "$TEST_ROOT/err"; then
    echo "FAIL: expected output NOT to mention: $1"
    cat "$TEST_ROOT/out" "$TEST_ROOT/err"
    exit 1
  fi
}

gated_count() {
  # How many times fake-gate.sh was asked about skills/$1/.
  grep -c "/skills/$1/\$" "$GATE_LOG" 2>/dev/null || true
}

# --- Test 1: a normal push, pass, and non-programmatic skills never gated --

: > "$GATE_LOG"
before="$(git -C "$REPO_DIR" rev-parse HEAD)"
touch_skill_md "$SKILLS/prog-with-fixtures"
touch_skill_md "$SKILLS/qual-skill"
touch_skill_md "$SKILLS/format1-skill"
git -C "$REPO_DIR" commit -q -am "Edit three skills"
after="$(git -C "$REPO_DIR" rev-parse HEAD)"

expect_exit_stdin "refs/heads/main $after refs/heads/main $before
" 0
says "Gating: prog-with-fixtures"
says "gate passed"
says_not "Gating: qual-skill"
says_not "Gating: format1-skill"
[ "$(gated_count prog-with-fixtures)" = "1" ] \
  || { echo "FAIL: prog-with-fixtures gated $(gated_count prog-with-fixtures) time(s), want 1"; exit 1; }
[ -z "$(gated_count qual-skill)" ] || [ "$(gated_count qual-skill)" = "0" ] \
  || { echo "FAIL: qual-skill was gated"; exit 1; }

# --- Test 2: missing fixtures blocks, naming the fixture layout ------------

: > "$GATE_LOG"
before="$(git -C "$REPO_DIR" rev-parse HEAD)"
touch_skill_md "$SKILLS/prog-no-fixtures"
git -C "$REPO_DIR" commit -q -am "Edit prog-no-fixtures"
after="$(git -C "$REPO_DIR" rev-parse HEAD)"

expect_exit_stdin "refs/heads/main $after refs/heads/main $before
" 1
says "fixture(s); the gate needs at least"
says "fixtures/<case>.prompt.md"
says "push blocked"
says "Pre-push gate FAILED"

# --- Test 3: a regression blocks and relays the gate's revert line --------

: > "$GATE_LOG"
before="$(git -C "$REPO_DIR" rev-parse HEAD)"
touch_skill_md "$SKILLS/prog-regressed"
git -C "$REPO_DIR" commit -q -am "Edit prog-regressed"
after="$(git -C "$REPO_DIR" rev-parse HEAD)"

expect_exit_stdin "refs/heads/main $after refs/heads/main $before
" 1
says "git checkout deadbee5 -- skills/prog-regressed/SKILL.md"
says "push blocked"

# --- Test 4: a refusal that isn't about fixtures reports but never blocks --

: > "$GATE_LOG"
before="$(git -C "$REPO_DIR" rev-parse HEAD)"
touch_skill_md "$SKILLS/prog-other-refusal"
git -C "$REPO_DIR" commit -q -am "Edit prog-other-refusal"
after="$(git -C "$REPO_DIR" rev-parse HEAD)"

expect_exit_stdin "refs/heads/main $after refs/heads/main $before
" 0
says "script_emits_outcome"
says "not blocking"
says "Pre-push gate passed"

# --- Test 5: SKILLMONGER_SKIP_GATE bypasses, naming what it skipped -------

: > "$GATE_LOG"
before="$(git -C "$REPO_DIR" rev-parse HEAD)"
touch_skill_md "$SKILLS/prog-no-fixtures"
git -C "$REPO_DIR" commit -q -am "Edit prog-no-fixtures again"
after="$(git -C "$REPO_DIR" rev-parse HEAD)"

export SKILLMONGER_SKIP_GATE=1
expect_exit_stdin "refs/heads/main $after refs/heads/main $before
" 0
unset SKILLMONGER_SKIP_GATE
says "SKILLMONGER_SKIP_GATE"
says "prog-no-fixtures"
[ "$(gated_count prog-no-fixtures)" = "0" ] || [ -z "$(gated_count prog-no-fixtures)" ] \
  || { echo "FAIL: the gate ran despite SKILLMONGER_SKIP_GATE"; exit 1; }

# --- Test 6: a delete is skipped, no gate call at all ----------------------

: > "$GATE_LOG"
some_sha="$(git -C "$REPO_DIR" rev-parse HEAD)"
expect_exit_stdin "refs/heads/gone 0000000000000000000000000000000000000000 refs/heads/gone $some_sha
" 0
says_not "Gating:"
[ ! -s "$GATE_LOG" ] || { echo "FAIL: gate ran on a delete"; exit 1; }

# --- Test 7: a new branch, with the remote's default branch known ---------
# refs/remotes/origin/HEAD -> origin/main was set right after the seed push.

: > "$GATE_LOG"
git -C "$REPO_DIR" checkout -q -b feature-known "$SEED_SHA"
touch_skill_md "$SKILLS/prog-with-fixtures"
git -C "$REPO_DIR" commit -q -am "New branch, known default"
feature_sha="$(git -C "$REPO_DIR" rev-parse HEAD)"

expect_exit_stdin "refs/heads/feature-known $feature_sha refs/heads/feature-known 0000000000000000000000000000000000000000
" 0
says "Gating: prog-with-fixtures"
[ "$(gated_count prog-with-fixtures)" = "1" ] \
  || { echo "FAIL: new-branch (known default) gated prog-with-fixtures $(gated_count prog-with-fixtures) time(s)"; exit 1; }
git -C "$REPO_DIR" checkout -q main
git -C "$REPO_DIR" branch -q -D feature-known

# --- Test 8: a new branch, falling back to --not --remotes -----------------
# No refs/remotes/origin/HEAD; isolation comes from exclude-what's-already-
# on-a-remote-tracking-ref instead.

git -C "$REPO_DIR" symbolic-ref -q -d refs/remotes/origin/HEAD || true
: > "$GATE_LOG"
git -C "$REPO_DIR" checkout -q -b feature-fallback "$SEED_SHA"
touch_skill_md "$SKILLS/prog-regressed"
git -C "$REPO_DIR" commit -q -am "New branch, fallback isolation"
feature_sha="$(git -C "$REPO_DIR" rev-parse HEAD)"

expect_exit_stdin "refs/heads/feature-fallback $feature_sha refs/heads/feature-fallback 0000000000000000000000000000000000000000
" 1
says "git checkout deadbee5 -- skills/prog-regressed/SKILL.md"
[ "$(gated_count prog-regressed)" = "1" ] \
  || { echo "FAIL: new-branch (fallback) gated prog-regressed $(gated_count prog-regressed) time(s)"; exit 1; }
git -C "$REPO_DIR" checkout -q main
git -C "$REPO_DIR" branch -q -D feature-fallback
git -C "$REPO_DIR" remote set-head origin main

# --- Test 9: multiple stdin lines in one push, each skill gated once ------

: > "$GATE_LOG"
before="$(git -C "$REPO_DIR" rev-parse HEAD)"
touch_skill_md "$SKILLS/prog-with-fixtures"
git -C "$REPO_DIR" commit -q -am "Multi-line push, first line"
mid="$(git -C "$REPO_DIR" rev-parse HEAD)"
touch_skill_md "$SKILLS/prog-with-fixtures"
git -C "$REPO_DIR" commit -q -am "Multi-line push, second line touches the same skill again"
after="$(git -C "$REPO_DIR" rev-parse HEAD)"
deleted_sha="$after"

expect_exit_stdin "refs/heads/main $after refs/heads/main $before
refs/heads/scratch 0000000000000000000000000000000000000000 refs/heads/scratch $deleted_sha
" 0
[ "$(gated_count prog-with-fixtures)" = "1" ] \
  || { echo "FAIL: multi-line push gated prog-with-fixtures $(gated_count prog-with-fixtures) time(s)"; exit 1; }

echo "test-pre-push.sh: ok"
