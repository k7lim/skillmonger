#!/bin/bash
# evaluate.sh - Score an explainer built from this skill.
#
# Wraps the upstream smoke test (scripts/smoke.mjs, verbatim) in the skillmonger
# evaluate contract: takes a project directory, emits {outcome, note, checks,
# source} on stdout, exits 0 even when the outcome is low.
#
# Usage: scripts/evaluate.sh [project-dir]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${1:-$PWD}"
PROJECT="$(cd "$PROJECT" 2> /dev/null && pwd)" || {
  printf '{"outcome":1,"note":"no such project directory: %s","checks":{},"source":"script"}\n' "${1:-}"
  exit 0
}

emit() { # outcome note checks_json
  printf '{"outcome":%s,"note":"%s","checks":%s,"source":"script"}\n' \
    "$1" "$(printf '%s' "$2" | sed 's/"/\\"/g')" "$3"
}

# --- structure ---
missing=""
for f in index.html js/iso.js js/model.js js/world.js js/sim.js js/render.js js/ui.js js/main.js; do
  [ -f "$PROJECT/$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
  emit 1 "missing required files:$missing" \
    '{"structure":false,"syntax":null,"smoke":null}'
  exit 0
fi

# --- syntax: one file at a time, node --check takes exactly one ---
syntax_fail=""
for f in "$PROJECT"/js/*.js; do
  node --check "$f" > /dev/null 2>&1 || syntax_fail="$syntax_fail $(basename "$f")"
done
if [ -n "$syntax_fail" ]; then
  emit 1 "syntax errors in:$syntax_fail" \
    '{"structure":true,"syntax":false,"smoke":null}'
  exit 0
fi

# --- fidelity ledger: rule 3 of the skill, and cheap to check ---
ledger=false
grep -qi 'computed\|scaled\|assumed\|faked' "$PROJECT/index.html" 2> /dev/null && ledger=true

# --- smoke test, if Playwright can actually launch ---
# The package resolving is not enough: an upgraded playwright often wants a
# chromium build that was never downloaded, and that only fails at launch.
pw_state=$(node -e '
  const dir = process.argv[1];
  let p;
  try { p = require.resolve("playwright", {paths:[dir]}); }
  catch { console.log("missing-package"); process.exit(0); }
  const {chromium} = require(p);
  console.log(require("fs").existsSync(chromium.executablePath())
    ? "ok" : "missing-browser");
' "$PROJECT" 2> /dev/null)

if [ "$pw_state" != "ok" ]; then
  case "$pw_state" in
    missing-browser) why="playwright is installed but its chromium build is not — run: npx playwright install chromium" ;;
    *)               why="playwright not installed in the project — run: npm i -D playwright && npx playwright install chromium" ;;
  esac
  emit 3 "syntax clean but UNVERIFIED: $why. No station walk and no screenshot, so this explainer has NOT been shown to work." \
    "{\"structure\":true,\"syntax\":true,\"smoke\":null,\"playwright\":\"$pw_state\",\"fidelity_ledger\":$ledger}"
  exit 0
fi

PORT=$(node -e 'const s=require("net").createServer();s.listen(0,()=>{console.log(s.address().port);s.close()})')
( cd "$PROJECT" && python3 -m http.server "$PORT" > /dev/null 2>&1 ) &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS "http://localhost:$PORT/" -o /dev/null 2> /dev/null && break
  sleep 0.3
done

SHOT="$PROJECT/smoke.png"
# Run from the project: smoke.mjs resolves playwright out of process.cwd(), so
# invoking it from the skill directory fails even when the project has it.
smoke_out=$(cd "$PROJECT" && node "$SCRIPT_DIR/smoke.mjs" "http://localhost:$PORT/" --out "$SHOT" 2>&1)
smoke_rc=$?
kill $SERVER_PID 2> /dev/null

stations=$(printf '%s' "$smoke_out" | sed -n 's/^stations visited (\([0-9]*\)).*/\1/p' | head -1)
finished=$(printf '%s' "$smoke_out" | sed -n 's/^run finished: //p' | head -1)

if [ "$smoke_rc" -ne 0 ]; then
  # Prefer the structured FAIL block; fall back to raw output so a thrown
  # exception never degrades to an unactionable "see output".
  reason=$(printf '%s' "$smoke_out" | sed -n '/^FAIL/,$p' | tail -n +2 | tr -s ' \n' ' ')
  [ -n "$reason" ] || reason=$(printf '%s' "$smoke_out" | grep -v '^\s*$' | tail -5 | tr -s ' \n' ' ')
  reason=$(printf '%s' "$reason" | cut -c1-400)
  emit 2 "smoke test failed: ${reason:-no output}" \
    "{\"structure\":true,\"syntax\":true,\"smoke\":false,\"stations\":${stations:-0},\"finished\":\"${finished:-false}\",\"fidelity_ledger\":$ledger}"
  exit 0
fi

if [ "$ledger" != true ]; then
  emit 4 "smoke test passed (${stations:-0} stations) but no fidelity ledger found in index.html — rule 3. Also: look at $SHOT, occlusion and label collisions do not raise errors." \
    "{\"structure\":true,\"syntax\":true,\"smoke\":true,\"stations\":${stations:-0},\"finished\":\"${finished:-}\",\"fidelity_ledger\":false}"
  exit 0
fi

emit 5 "smoke test passed: ${stations:-0} stations, run finished=${finished:-?}, fidelity ledger present. Still look at $SHOT." \
  "{\"structure\":true,\"syntax\":true,\"smoke\":true,\"stations\":${stations:-0},\"finished\":\"${finished:-}\",\"fidelity_ledger\":true}"
exit 0
