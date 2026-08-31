#!/bin/bash
# The state file at ~/.skillmonger-state is mutable shared state. scripts/skill
# used to `source` it, which ran whatever it contained. These tests prove the
# replacement parser reads it as data: nothing in the file executes, bad
# content is refused with a clear message, and the writer/reader round-trip
# still works.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_HOME="$TEST_ROOT/home"
STATE_FILE="$FAKE_HOME/.skillmonger-state"
SKILL_DIR="$TEST_ROOT/sandbox/skills/happy-skill"
mkdir -p "$FAKE_HOME" "$SKILL_DIR"

SKILL_CMD="$PROJECT_ROOT/scripts/skill"
LIB="$PROJECT_ROOT/scripts/lib/skill-state.sh"

# Run `skill status` with HOME redirected, capturing exit code and output.
run_status() {
  set +e
  OUT="$(HOME="$FAKE_HOME" "$SKILL_CMD" status 2>&1)"
  RC=$?
  set -e
}

# expect_rejected <reason-substring> — the file at STATE_FILE must be refused
# with a message naming the reason, nothing may have executed, and the caller's
# canary must be absent.
expect_rejected() {
  run_status
  [ "$RC" -ne 0 ] || { echo "expected rejection, got exit 0:"; echo "$OUT"; exit 1; }
  case "$OUT" in
    *"$1"*) ;;
    *) echo "expected message containing '$1', got:"; echo "$OUT"; exit 1 ;;
  esac
  case "$OUT" in
    *"skill clear"*) ;;
    *) echo "rejection must tell the user how to reset, got:"; echo "$OUT"; exit 1 ;;
  esac
  [ ! -e "$TEST_ROOT/pwned" ] || { echo "state file content was executed"; exit 1; }
}

# The parser never executes: the same function must not exist in the caller's
# shell either, so `source`-style leakage cannot pass through.
# shellcheck source=../scripts/lib/skill-state.sh
. "$LIB"

# --- Happy path: writer -> reader round-trip through `skill status` ---

skill_state_save "$STATE_FILE" \
  "SKILL_NAME=happy-skill" \
  "SKILL_DIR=$SKILL_DIR" \
  "LAST_ACTION=scaffolded" \
  "TIMESTAMP=2026-08-31 09:00" \
  "NEXT_STEP=cd $SKILL_DIR && claude \"Read BRIEF.md and build the skill\"" \
  "AFTER_THAT=scripts/ship-skill.sh $SKILL_DIR"

# The on-disk format is plain KEY=VALUE, nothing quoted for a shell.
grep -q '^SKILL_NAME=happy-skill$' "$STATE_FILE"
grep -q "^SKILL_DIR=$SKILL_DIR\$" "$STATE_FILE"
grep -q '^NEXT_STEP=cd .* && claude "Read BRIEF.md and build the skill"$' "$STATE_FILE"
[ "$(wc -l < "$STATE_FILE" | tr -d ' ')" -eq 6 ]

run_status
[ "$RC" -eq 0 ] || { echo "happy path failed:"; echo "$OUT"; exit 1; }
case "$OUT" in *"Current skill: happy-skill"*) ;; *) echo "$OUT"; exit 1 ;; esac
case "$OUT" in *"State: scaffolded (2026-08-31 09:00)"*) ;; *) echo "$OUT"; exit 1 ;; esac
case "$OUT" in *"Location: $SKILL_DIR"*) ;; *) echo "$OUT"; exit 1 ;; esac
case "$OUT" in *'claude "Read BRIEF.md and build the skill"'*) ;; *) echo "$OUT"; exit 1 ;; esac
case "$OUT" in *"scripts/ship-skill.sh $SKILL_DIR"*) ;; *) echo "$OUT"; exit 1 ;; esac

# The loader exposes STATE_* so a caller's own SKILL_NAME is never clobbered.
SKILL_NAME="caller-owned"
skill_state_load "$STATE_FILE"
[ "$SKILL_NAME" = "caller-owned" ]
[ "$STATE_SKILL_NAME" = "happy-skill" ]
[ "$STATE_SKILL_DIR" = "$SKILL_DIR" ]
[ "$STATE_AFTER_THAT" = "scripts/ship-skill.sh $SKILL_DIR" ]

# AFTER_THAT is optional; a reload must not carry a stale value over.
skill_state_save "$STATE_FILE" \
  "SKILL_NAME=happy-skill" "SKILL_DIR=$SKILL_DIR" "LAST_ACTION=scaffolded" \
  "TIMESTAMP=2026-08-31 09:00" "NEXT_STEP=do the thing"
skill_state_load "$STATE_FILE"
[ -z "$STATE_AFTER_THAT" ]
run_status
[ "$RC" -eq 0 ]
case "$OUT" in *"Then from host"*) echo "stale AFTER_THAT shown"; exit 1 ;; esac

# A stale directory is still reported as such, not as corrupt state.
rm -rf "$SKILL_DIR"
run_status
[ "$RC" -ne 0 ]
case "$OUT" in *"Stale state"*) ;; *) echo "$OUT"; exit 1 ;; esac
mkdir -p "$SKILL_DIR"

# --- Malicious content: nothing executes, everything is refused ---

# 1. A trailing command after a valid-looking assignment. Under `source`
#    this ran `touch`. Now the name fails the skill-name shape.
cat > "$STATE_FILE" <<EOF
SKILL_NAME=x; touch $TEST_ROOT/pwned
SKILL_DIR=$SKILL_DIR
LAST_ACTION=scaffolded
TIMESTAMP=now
NEXT_STEP=n
EOF
expect_rejected "SKILL_NAME"

# 2. Command substitution inside an otherwise free-form value.
cat > "$STATE_FILE" <<EOF
SKILL_NAME=happy-skill
SKILL_DIR=$SKILL_DIR
LAST_ACTION=scaffolded
TIMESTAMP=now
NEXT_STEP=echo \$(touch $TEST_ROOT/pwned)
EOF
expect_rejected "command substitution"

# 3. Backticks.
cat > "$STATE_FILE" <<EOF
SKILL_NAME=happy-skill
SKILL_DIR=$SKILL_DIR
LAST_ACTION=scaffolded
TIMESTAMP=\`touch $TEST_ROOT/pwned\`
NEXT_STEP=n
EOF
expect_rejected "command substitution"

# 4. Parameter expansion.
cat > "$STATE_FILE" <<EOF
SKILL_NAME=happy-skill
SKILL_DIR=$SKILL_DIR
LAST_ACTION=\${HOME}
TIMESTAMP=now
NEXT_STEP=n
EOF
expect_rejected "command substitution"

# 5. Path traversal in the one path-valued key.
cat > "$STATE_FILE" <<EOF
SKILL_NAME=happy-skill
SKILL_DIR=$SKILL_DIR/../../../etc
LAST_ACTION=scaffolded
TIMESTAMP=now
NEXT_STEP=n
EOF
expect_rejected "path traversal"

# 6. A relative path is not a sandbox skill directory either.
cat > "$STATE_FILE" <<EOF
SKILL_NAME=happy-skill
SKILL_DIR=skills/happy-skill
LAST_ACTION=scaffolded
TIMESTAMP=now
NEXT_STEP=n
EOF
expect_rejected "absolute"

# 7. Control characters (a literal tab, a carriage return).
printf 'SKILL_NAME=happy-skill\nSKILL_DIR=%s\nLAST_ACTION=scaff\tolded\nTIMESTAMP=now\nNEXT_STEP=n\n' \
  "$SKILL_DIR" > "$STATE_FILE"
expect_rejected "control character"
printf 'SKILL_NAME=happy-skill\r\nSKILL_DIR=%s\nLAST_ACTION=scaffolded\nTIMESTAMP=now\nNEXT_STEP=n\n' \
  "$SKILL_DIR" > "$STATE_FILE"
expect_rejected "control character"

# 8. Keys outside the allowlist, malformed lines, duplicates, missing keys.
cat > "$STATE_FILE" <<EOF
SKILL_NAME=happy-skill
SKILL_DIR=$SKILL_DIR
LAST_ACTION=scaffolded
TIMESTAMP=now
NEXT_STEP=n
PATH=/tmp/evil
EOF
expect_rejected "unknown key"

cat > "$STATE_FILE" <<EOF
touch $TEST_ROOT/pwned
SKILL_NAME=happy-skill
EOF
expect_rejected "malformed line"

cat > "$STATE_FILE" <<EOF
SKILL_NAME=happy-skill
SKILL_NAME=other-skill
SKILL_DIR=$SKILL_DIR
LAST_ACTION=scaffolded
TIMESTAMP=now
NEXT_STEP=n
EOF
expect_rejected "duplicate key"

cat > "$STATE_FILE" <<EOF
SKILL_NAME=happy-skill
SKILL_DIR=$SKILL_DIR
EOF
expect_rejected "missing key"

# 9. The pre-fix quoted shell format is refused by name rather than
#    half-interpreted.
cat > "$STATE_FILE" <<EOF
SKILL_NAME="happy-skill"
SKILL_DIR="$SKILL_DIR"
LAST_ACTION="scaffolded"
TIMESTAMP="now"
NEXT_STEP="n"
EOF
expect_rejected "old shell format"

# --- The writer applies the same rules, so it cannot produce a file the
#     reader would refuse ---

set +e
skill_state_save "$STATE_FILE.new" "SKILL_NAME=bad name" "SKILL_DIR=$SKILL_DIR" \
  "LAST_ACTION=a" "TIMESTAMP=b" "NEXT_STEP=c" 2>/dev/null
RC=$?
set -e
[ "$RC" -ne 0 ]
[ ! -e "$STATE_FILE.new" ]

set +e
skill_state_save "$STATE_FILE.new" "SKILL_NAME=ok" "SKILL_DIR=$SKILL_DIR" \
  "LAST_ACTION=a" "TIMESTAMP=b" "NEXT_STEP=$(printf 'two\nlines')" 2>/dev/null
RC=$?
set -e
[ "$RC" -ne 0 ]
[ ! -e "$STATE_FILE.new" ]

set +e
skill_state_save "$STATE_FILE.new" "SKILL_NAME=ok" "SKILL_DIR=$SKILL_DIR" \
  "LAST_ACTION=a" "TIMESTAMP=b" "NEXT_STEP=c" "BOGUS=1" 2>/dev/null
RC=$?
set -e
[ "$RC" -ne 0 ]
[ ! -e "$STATE_FILE.new" ]

# --- `skill clear` still resets a corrupt file ---

OUT="$(HOME="$FAKE_HOME" "$SKILL_CMD" clear 2>&1)"
[ ! -e "$STATE_FILE" ]
[ ! -e "$TEST_ROOT/pwned" ]

echo "skill-state tests passed"
