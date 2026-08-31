#!/bin/bash
# ship-skill.sh must never block on a prompt when it has no terminal, and a
# run that stops early (closed stdin, killed at a prompt, declined
# overwrite) must leave nothing under skills/: a half-shipped skill passes
# validate-skill.sh and breaks on first use (skillmonger-j9f).
#
# The extras under test are the ones every adoption carries, assets/ and
# SOURCE.md. The sandbox's check-prereqs.sh reads stdin on purpose: ship
# must not let it eat the piped answers.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SHIP="$PROJECT_ROOT/scripts/ship-skill.sh"
VALIDATE="$PROJECT_ROOT/scripts/validate-skill.sh"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_HOME="$TEST_ROOT/home"
FAKE_REPO="$TEST_ROOT/repo"
FAKE_SKILLS="$FAKE_REPO/skills"
SANDBOX="$TEST_ROOT/sandbox/skills"
export SKILLMONGER_SKILLS_DIR="$FAKE_SKILLS"
export HOME="$FAKE_HOME"
mkdir -p "$FAKE_HOME" "$FAKE_SKILLS" "$SANDBOX"

# A hung ship-skill.sh is the bug; cap every run so a regression fails
# instead of blocking the suite. Bash 3.2 has no builtin timeout, so a
# missing coreutils timeout only skips the kill test.
TIMEOUT=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT="gtimeout"
fi
run_ship() {
  if [ -n "$TIMEOUT" ]; then
    "$TIMEOUT" 30 "$SHIP" "$@"
  else
    "$SHIP" "$@"
  fi
}

# make_sandbox NAME: a sandbox skill with the standard files plus assets/
# (two files) and SOURCE.md.
make_sandbox() {
  local dir="$SANDBOX/$1"
  rm -rf "$dir"
  mkdir -p "$dir/scripts" "$dir/assets/template"
  cat > "$dir/SKILL.md" <<EOF
---
name: $1
description: Fixture for ship-skill tests.
---

# $1

Copy assets/template into the project.
EOF
  cat > "$dir/CONFIG.yaml" <<EOF
skill:
  name: $1
  version: 1.0.0
triggers:
  phrases:
    - "ship it"
EOF
  cat > "$dir/scripts/check-prereqs.sh" <<'EOF'
#!/bin/bash
# Swallows stdin, like a prereq script that shells out to something chatty.
cat >/dev/null
echo '{"ready": true, "checks": [], "context": {}}'
EOF
  chmod +x "$dir/scripts/check-prereqs.sh"
  echo "index" > "$dir/assets/template/index.html"
  echo "app" > "$dir/assets/template/app.js"
  echo "# Source" > "$dir/SOURCE.md"
  echo "$dir"
}

# no_leftovers: nothing under skills/ except what a test expects, and no
# staging directory survives a run.
assert_no_staging() {
  [ ! -e "$FAKE_REPO/.skill-staging" ] || [ -z "$(ls -A "$FAKE_REPO/.skill-staging")" ]
}

# --- 1. Non-interactive, no flags: ships every extra, does not block -------

SB="$(make_sandbox alpha)"
OUT="$(run_ship "$SB" --keep-sandbox </dev/null)"
echo "$OUT" | grep -q "non-interactive"
echo "$OUT" | grep -q "Skill promoted successfully"
[ -f "$FAKE_SKILLS/alpha/SKILL.md" ]
[ -f "$FAKE_SKILLS/alpha/CONFIG.yaml" ]
[ -f "$FAKE_SKILLS/alpha/MEMO.md" ]
[ -f "$FAKE_SKILLS/alpha/assets/template/index.html" ]
[ -f "$FAKE_SKILLS/alpha/assets/template/app.js" ]
[ -f "$FAKE_SKILLS/alpha/SOURCE.md" ]
# --keep-sandbox: the sandbox copy is still there.
[ -f "$SB/SKILL.md" ]
assert_no_staging
"$VALIDATE" "$FAKE_SKILLS/alpha" >/dev/null

# --- 2. Non-interactive overwrite without --yes: aborts, existing untouched -

echo "original" > "$FAKE_SKILLS/alpha/MARKER"
SB="$(make_sandbox alpha)"
set +e
OUT="$(run_ship "$SB" --keep-sandbox </dev/null)"
RC=$?
set -e
[ "$RC" -eq 1 ]
echo "$OUT" | grep -q "already exists"
echo "$OUT" | grep -q -- "--yes"
[ "$(cat "$FAKE_SKILLS/alpha/MARKER")" = "original" ]
assert_no_staging

# --- 3. --yes: overwrites after a backup, deletes the sandbox copy ---------

OUT="$(run_ship "$SB" --yes </dev/null)"
echo "$OUT" | grep -q "Skill promoted successfully"
[ ! -e "$FAKE_SKILLS/alpha/MARKER" ]
[ -f "$FAKE_SKILLS/alpha/assets/template/index.html" ]
[ -f "$FAKE_SKILLS/alpha/SOURCE.md" ]
[ ! -e "$SB" ]
BACKUP="$(ls -d "$FAKE_REPO"/.skill-backups/alpha-* | head -1)"
[ -f "$BACKUP/MARKER" ]
assert_no_staging

# --- 4. --no-extras: standard files only, skipped extras named ------------

SB="$(make_sandbox beta)"
OUT="$(run_ship "$SB" --no-extras --keep-sandbox </dev/null)"
echo "$OUT" | grep -q "Skill promoted successfully"
[ -f "$FAKE_SKILLS/beta/SKILL.md" ]
[ ! -e "$FAKE_SKILLS/beta/assets" ]
[ ! -e "$FAKE_SKILLS/beta/SOURCE.md" ]
echo "$OUT" | grep -q "⊘ assets (not shipped: --no-extras)"
echo "$OUT" | grep -q "⊘ SOURCE.md (not shipped: --no-extras)"
echo "$OUT" | grep -q "Not shipped"
assert_no_staging

# --- 5. --ask with piped answers: the interactive path still asks ---------

# Enter on every prompt: the interactive default (Y) ships the extras.
SB="$(make_sandbox gamma)"
OUT="$(printf '\n' | run_ship "$SB" --ask --keep-sandbox)"
echo "$OUT" | grep -q "Copy these to the skill?"
echo "$OUT" | grep -q "Skill promoted successfully"
[ -f "$FAKE_SKILLS/gamma/assets/template/index.html" ]
[ -f "$FAKE_SKILLS/gamma/SOURCE.md" ]
assert_no_staging

# "n" declines them, and they are listed by name.
SB="$(make_sandbox delta)"
OUT="$(printf 'n\n' | run_ship "$SB" --ask --keep-sandbox)"
echo "$OUT" | grep -q "Skill promoted successfully"
[ -f "$FAKE_SKILLS/delta/SKILL.md" ]
[ ! -e "$FAKE_SKILLS/delta/assets" ]
[ ! -e "$FAKE_SKILLS/delta/SOURCE.md" ]
echo "$OUT" | grep -q "⊘ assets (not shipped: declined)"
echo "$OUT" | grep -q "⊘ SOURCE.md (not shipped: declined)"
assert_no_staging

# "i" asks per item. Glob order is locale-dependent, so only the split is
# asserted: one of the two ships, the other is named as not shipped.
SB="$(make_sandbox epsilon)"
OUT="$(printf 'i\ny\nn\n' | run_ship "$SB" --ask --keep-sandbox)"
echo "$OUT" | grep -q "Skill promoted successfully"
shipped=0
[ -e "$FAKE_SKILLS/epsilon/assets" ] && shipped=$((shipped + 1))
[ -e "$FAKE_SKILLS/epsilon/SOURCE.md" ] && shipped=$((shipped + 1))
[ "$shipped" -eq 1 ]
echo "$OUT" | grep -q "(not shipped: declined)"
assert_no_staging

# The overwrite prompt is answered from the pipe too, and "n" ships nothing.
SB="$(make_sandbox epsilon)"
OUT="$(printf 'n\n' | run_ship "$SB" --ask --keep-sandbox)"
echo "$OUT" | grep -q "Nothing was shipped"
[ "$shipped" -eq 1 ]  # still the previous ship: untouched
assert_no_staging

# --- 6. stdin closed at a prompt: loud abort, nothing under skills/ -------

SB="$(make_sandbox zeta)"
set +e
OUT="$(run_ship "$SB" --ask --keep-sandbox </dev/null)"
RC=$?
set -e
[ "$RC" -eq 1 ]
echo "$OUT" | grep -q "stdin closed at prompt"
echo "$OUT" | grep -q "Nothing was shipped"
[ ! -e "$FAKE_SKILLS/zeta" ]
assert_no_staging

# --- 7. Killed while blocked at the prompt: the original symptom ----------
# stdin is a pipe that never closes, so `read` blocks; timeout sends TERM.
# skills/ must not gain a partial zeta and staging must be cleaned up.

if [ -n "$TIMEOUT" ]; then
  FIFO="$TEST_ROOT/never-closes"
  mkfifo "$FIFO"
  exec 3<>"$FIFO"
  set +e
  "$TIMEOUT" 3 "$SHIP" "$SB" --ask --keep-sandbox <&3 >"$TEST_ROOT/killed.out" 2>&1
  RC=$?
  set -e
  exec 3>&-
  [ "$RC" -ne 0 ]
  grep -q "Copy these to the skill?" "$TEST_ROOT/killed.out"
  [ ! -e "$FAKE_SKILLS/zeta" ]
  assert_no_staging
else
  echo "  (no timeout/gtimeout; skipped the killed-at-prompt case)"
fi

# --- 8. validate-skill.sh warns about the half-shipped shape --------------
# An adopted skill whose upstream has assets/ while the skill does not.

UPSTREAM="$TEST_ROOT/upstream"
mkdir -p "$UPSTREAM/skills/eta/assets"
echo "x" > "$UPSTREAM/skills/eta/assets/t.html"
echo "---" > "$UPSTREAM/skills/eta/SKILL.md"
git -C "$UPSTREAM" init -q
git -C "$UPSTREAM" -c user.email=t@example.com -c user.name=T add -A
git -C "$UPSTREAM" -c user.email=t@example.com -c user.name=T commit -q -m up
UP_SHA="$(git -C "$UPSTREAM" rev-parse HEAD)"

HALF="$FAKE_SKILLS/eta"
mkdir -p "$HALF"
cat > "$HALF/SKILL.md" <<'EOF'
---
name: eta
description: Half-shipped adoption fixture.
---
EOF
cat > "$HALF/CONFIG.yaml" <<EOF
skill:
  name: eta
  version: 1.0.0
upstream:
  vendor: $UPSTREAM
  path: skills/eta
  commit: $UP_SHA
EOF
OUT="$("$VALIDATE" "$HALF")"
echo "$OUT" | grep -q "WARNING: upstream skills/eta has assets/ but this skill does not"
# With assets/ in place the warning goes away.
mkdir -p "$HALF/assets"
OUT="$("$VALIDATE" "$HALF")"
! echo "$OUT" | grep -q "has assets/ but this skill does not"

# --- 9. --help documents the flags and the non-interactive defaults -------

HELP="$("$SHIP" --help)"
echo "$HELP" | grep -q -- "--yes"
echo "$HELP" | grep -q -- "--no-extras"
echo "$HELP" | grep -q -- "--ask"
echo "$HELP" | grep -q "Non-interactive runs"

echo "ship-skill tests passed"
