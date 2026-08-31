#!/bin/bash
# A skill name becomes a path: skills/<name>, ~/.claude/skills/<name>, the
# store, the sandbox homes. Every script that takes one used to splice it
# straight in, so `..`, a slash or an encoded dot-dot reached rm -rf, cp and
# FEEDBACK.jsonl appends. These tests prove lib/skill-name.sh is in front of
# all of them: a bad name is refused with one line on stderr and exit 2, and
# nothing is created anywhere -- not under the fake root, not in the repo.
#
# The scripts under test fall in two groups. Bare-name scripts (undeploy,
# analyze --skill, log-feedback, harvest, sync-skill-back) get the full
# input matrix. Path-taking scripts (deploy, ship, compact-memo, gate) reduce
# the path to its last component; they are fed a directory whose name is bad.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$PROJECT_ROOT/scripts"
TEST_ROOT="$(mktemp -d)"
# Captured output lives outside TEST_ROOT so the "nothing was created"
# snapshot below never sees the test's own log files change.
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT" "$LOG_DIR"' EXIT
OUT="$LOG_DIR/out"
ERR="$LOG_DIR/err"

FAKE_HOME="$TEST_ROOT/home"
FAKE_REPO="$TEST_ROOT/repo"
FAKE_SKILLS="$FAKE_REPO/skills"
SANDBOX="$TEST_ROOT/sandbox/skills"
WORK="$TEST_ROOT/work"
export SKILLMONGER_SKILLS_DIR="$FAKE_SKILLS"
export HOME="$FAKE_HOME"
mkdir -p "$FAKE_HOME" "$FAKE_SKILLS" "$SANDBOX" "$WORK"

# Relative traversal names are resolved against the cwd; run from a scratch
# directory so `../seeds` and `a/b` name nothing that exists.
cd "$WORK"

# make_skill DIR NAME: a skill with the standard files at DIR.
make_skill() {
  mkdir -p "$1"
  cat > "$1/SKILL.md" <<EOF
---
name: $2
description: Fixture for skill-name tests.
---

# $2
EOF
  cat > "$1/CONFIG.yaml" <<EOF
skill:
  name: $2
  version: 1.0.0
compaction:
  cycle_threshold: 15
  last_compaction: null
  iteration_count: 0
EOF
  printf '# %s - MEMO\n' "$2" > "$1/MEMO.md"
  : > "$1/FEEDBACK.jsonl"
}

make_skill "$FAKE_SKILLS/good-skill" good-skill
# Directories whose names break the contract, for the path-taking scripts.
make_skill "$SANDBOX/bad--name" bad--name
make_skill "$SANDBOX/%2e%2e" '%2e%2e'

# Everything a script could write into: the fake root with contents, and the
# names under the real repo's skills/ and seeds/ (a bare-name script that
# does not honour SKILLMONGER_SKILLS_DIR derives its paths there).
tree_state() {
  find "$TEST_ROOT" \( -type f -o -type l -o -type d \) -print | LC_ALL=C sort
  find "$TEST_ROOT" -type f -print0 | LC_ALL=C sort -z | xargs -0 cksum
  ls -1 "$PROJECT_ROOT/skills" "$PROJECT_ROOT/seeds"
  ls -d "$PROJECT_ROOT/.skill-staging" "$PROJECT_ROOT/.skill-backups" 2>/dev/null || true
}
BEFORE_STATE="$(tree_state)"

RULE='(expected lowercase letters, digits and hyphens)'
LONG_NAME="$(printf 'a%.0s' $(seq 1 65))"
OK_NAME="$(printf 'a%.0s' $(seq 1 64))"

run() {
  set +e
  "$@" >"$OUT" 2>"$ERR" </dev/null
  RC=$?
  set -e
}

fail() {
  echo "FAIL: $1" >&2
  echo "--- command: $2" >&2
  echo "--- exit: $RC" >&2
  echo "--- stdout:" >&2; cat "$OUT" >&2
  echo "--- stderr:" >&2; cat "$ERR" >&2
  exit 1
}

# expect_rejected NAME CMD...: CMD exits 2, stderr is exactly the one ERROR
# line naming NAME, stdout is empty, and nothing was created.
expect_rejected() {
  local name="$1"; shift
  run "$@"
  [ "$RC" -eq 2 ] || fail "expected exit 2" "$*"
  [ "$(cat "$ERR")" = "ERROR: invalid skill name '$name' $RULE" ] \
    || fail "expected the one-line rejection" "$*"
  [ ! -s "$OUT" ] || fail "rejection must print nothing on stdout" "$*"
  [ "$(tree_state)" = "$BEFORE_STATE" ] || fail "something was created" "$*"
}

# expect_unknown_option CMD...: an option-shaped name never reaches the name
# slot in a script with an option parser; it is refused there instead, and
# still creates nothing.
expect_unknown_option() {
  run "$@"
  [ "$RC" -ne 0 ] || fail "expected a non-zero exit" "$*"
  grep -q 'Unknown option' "$OUT" "$ERR" \
    || fail "expected the option parser to refuse it" "$*"
  [ "$(tree_state)" = "$BEFORE_STATE" ] || fail "something was created" "$*"
}

# expect_accepted CMD...: the name passed validation -- no ERROR line, and an
# exit that is not the validator's.
expect_accepted() {
  run "$@"
  [ "$RC" -ne 2 ] || fail "valid name was rejected" "$*"
  ! grep -q 'invalid skill name' "$ERR" || fail "valid name was rejected" "$*"
}

# --- The library on its own ---

# shellcheck source=../scripts/lib/skill-name.sh
. "$SCRIPTS/lib/skill-name.sh"

for name in "../seeds" "a/b" "%2e%2e" "" "--flag-shaped" "$LONG_NAME" \
  "-a" "a-" "a--b" "Upper" "a b" "." ".." "$(printf 'a\tb')"; do
  if skill_name_valid "$name"; then
    echo "FAIL: lib accepted '$name'" >&2; exit 1
  fi
done
for name in "good-skill" "a" "a1" "1a" "$OK_NAME"; do
  skill_name_valid "$name" || { echo "FAIL: lib refused '$name'" >&2; exit 1; }
done
[ "$(skill_name_from_path 'skills/foo///')" = "foo" ]
[ "$(skill_name_from_path '--x')" = "--x" ]

# A control character in the name still yields one line on stderr.
run bash -c ". '$SCRIPTS/lib/skill-name.sh'; skill_name_require \"\$(printf 'a\\nb')\""
[ "$RC" -eq 2 ]
[ "$(wc -l < "$ERR" | tr -d ' ')" -eq 1 ]
grep -q "^ERROR: invalid skill name 'a?b' " "$ERR"

# skill_dir_require: skills/<name> that is a symlink out of skills/ is refused
# even though its name is fine; a real directory under the root passes.
mkdir -p "$TEST_ROOT/outside"
ln -s "$TEST_ROOT/outside" "$FAKE_SKILLS/escape-hatch"
run bash -c ". '$SCRIPTS/lib/skill-name.sh'; skill_dir_require '$FAKE_SKILLS/escape-hatch' '$FAKE_SKILLS'"
[ "$RC" -eq 2 ]
[ "$(cat "$ERR")" = "ERROR: skill path '$FAKE_SKILLS/escape-hatch' resolves outside '$FAKE_SKILLS'" ]
run bash -c ". '$SCRIPTS/lib/skill-name.sh'; skill_dir_require '$FAKE_SKILLS/good-skill' '$FAKE_SKILLS'"
[ "$RC" -eq 0 ]
rm "$FAKE_SKILLS/escape-hatch"
BEFORE_STATE="$(tree_state)"

# --- Bare-name scripts: the full matrix ---

for name in "../seeds" "a/b" "%2e%2e" "" "--flag-shaped" "$LONG_NAME"; do
  expect_rejected "$name" "$SCRIPTS/undeploy-skill.sh" "$name" --global --dry-run
  expect_rejected "$name" "$SCRIPTS/analyze-feedback.sh" --skill "$name" --no-harvest
done
expect_accepted "$SCRIPTS/undeploy-skill.sh" good-skill --global --dry-run
expect_accepted "$SCRIPTS/analyze-feedback.sh" --skill good-skill --no-harvest
expect_accepted "$SCRIPTS/analyze-feedback.sh" --skill "$OK_NAME" --no-harvest

# undeploy takes skills/<name>/ too; the name is still checked after the
# path is reduced, so `.` and `..` (whose basename is the root) are refused.
expect_accepted "$SCRIPTS/undeploy-skill.sh" "$FAKE_SKILLS/good-skill/" --global --dry-run
grep -q 'Undeploying skill: good-skill' "$OUT"
expect_rejected "." "$SCRIPTS/undeploy-skill.sh" . --global --dry-run
expect_rejected ".." "$SCRIPTS/undeploy-skill.sh" .. --global --dry-run

# These three refuse an option-shaped word in their parser, before it can be
# a name; every other bad name reaches the validator.
for name in "../seeds" "a/b" "%2e%2e" "" "$LONG_NAME"; do
  expect_rejected "$name" "$SCRIPTS/log-feedback.sh" "$name" --outcome 4 --prompt "x" --source user
  expect_rejected "$name" "$SCRIPTS/harvest-feedback.sh" "$name"
  expect_rejected "$name" "$SCRIPTS/sync-skill-back.sh" "$name" --from "$WORK" --dry-run
done
expect_unknown_option "$SCRIPTS/log-feedback.sh" --flag-shaped --outcome 4 --prompt "x"
expect_unknown_option "$SCRIPTS/harvest-feedback.sh" --flag-shaped
expect_unknown_option "$SCRIPTS/sync-skill-back.sh" --flag-shaped --from "$WORK"
expect_accepted "$SCRIPTS/harvest-feedback.sh" good-skill
# log-feedback and sync-skill-back derive from the repo's own skills/; a valid
# name that is not there stops at "not found", past the validator.
expect_accepted "$SCRIPTS/log-feedback.sh" "$OK_NAME" --outcome 4 --prompt "x" --source user
grep -q 'Skill directory not found' "$OUT"
expect_accepted "$SCRIPTS/sync-skill-back.sh" "$OK_NAME" --from "$WORK" --dry-run
grep -q 'Source skill not found' "$OUT"
# The accepted harvest wrote inside the fake root (iteration_count); that is
# the happy path. Snapshot again so the rejections below are measured from it.
BEFORE_STATE="$(tree_state)"

# seed-skill normalises first (case, spaces, stray characters), then holds
# the result to the contract. What normalising cannot fix is refused.
expect_rejected "" "$SCRIPTS/seed-skill.sh" ""
expect_rejected "--flag-shaped" "$SCRIPTS/seed-skill.sh" --flag-shaped
expect_rejected "$LONG_NAME" "$SCRIPTS/seed-skill.sh" "$LONG_NAME"

# sync-upstream derives skills/<name> from a bare name.
for name in "../seeds" "a/b" "%2e%2e" "$LONG_NAME"; do
  expect_rejected "$name" "$SCRIPTS/sync-upstream.sh" "$name" --dry-run
done

# --- Path-taking scripts: the name is the last path component ---

for dir in "$SANDBOX/bad--name" "$SANDBOX/%2e%2e"; do
  name="${dir##*/}"
  expect_rejected "$name" "$SCRIPTS/deploy-skill.sh" "$dir" --global
  expect_rejected "$name" "$SCRIPTS/deploy-skill.sh" "$dir/" --global --dry-run
  expect_rejected "$name" "$SCRIPTS/ship-skill.sh" "$dir" --yes
  expect_rejected "$name" "$SCRIPTS/compact-memo.sh" "$dir" --no-harvest
  expect_rejected "$name" "$SCRIPTS/gate-skill.sh" "$dir" --dry-run
done
# deploy checks the name before it enters the path: an option-shaped or
# over-long argument is refused as a name, not reported as a missing directory.
expect_rejected "--flag-shaped" "$SCRIPTS/deploy-skill.sh" --flag-shaped --global
expect_rejected "$LONG_NAME" "$SCRIPTS/deploy-skill.sh" "$LONG_NAME" --global
expect_rejected "%2e%2e" "$SCRIPTS/deploy-skill.sh" "%2e%2e" --global

# The happy path is untouched: a valid skill still deploys and undeploys.
"$SCRIPTS/deploy-skill.sh" "$FAKE_SKILLS/good-skill" --store-only >/dev/null
[ -d "$FAKE_HOME/.local/share/skillmonger/skills/good-skill" ]
"$SCRIPTS/undeploy-skill.sh" good-skill --global --yes </dev/null >/dev/null
[ ! -e "$FAKE_HOME/.local/share/skillmonger/skills/good-skill" ]
expect_accepted "$SCRIPTS/compact-memo.sh" "$FAKE_SKILLS/good-skill" --no-harvest
grep -q 'Compaction Review: good-skill' "$OUT"

echo "skill-name tests passed"
