#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_HOME="$TEST_ROOT/home"
SANDBOX_HOME="$FAKE_HOME/.local/share/yolobox/home"
# The harvester writes traces back into the repo's skills/; point it at a
# throwaway tree so the tests never touch the real one.
FAKE_SKILLS="$TEST_ROOT/repo/skills"
SKILL_DIR="$FAKE_SKILLS/example-skill"
export SKILLMONGER_SKILLS_DIR="$FAKE_SKILLS"
mkdir -p \
  "$SANDBOX_HOME/.claude" \
  "$SANDBOX_HOME/.codex" \
  "$SKILL_DIR"

cat > "$SKILL_DIR/SKILL.md" <<'EOF'
---
name: example-skill
description: Fixture for deployment tests.
---

# Example Skill
EOF

cat > "$SKILL_DIR/CONFIG.yaml" <<'EOF'
skill:
  name: example-skill
  version: 1.0.0
compaction:
  cycle_threshold: 15
  last_compaction: null
  iteration_count: 0
EOF

# One trace already in the repo. Harvest must never rewrite it.
ORIGINAL_TRACE='{"ts":"2026-01-01T00:00:00Z","skill":"example-skill","version":"1.0.0","prompt":"already home","outcome":5,"note":"","source":"user","schema_version":1}'
printf '%s\n' "$ORIGINAL_TRACE" > "$SKILL_DIR/FEEDBACK.jsonl"

HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/deploy-skill.sh" \
  "$SKILL_DIR" --global --tools claude,codex,pi >/dev/null

STORE="$FAKE_HOME/.local/share/skillmonger/skills/example-skill"
[ -d "$STORE" ]
[ -L "$FAKE_HOME/.claude/skills/example-skill" ]
[ -L "$FAKE_HOME/.codex/skills/example-skill" ]
[ ! -e "$FAKE_HOME/.config/opencode/skills/example-skill" ]
[ -d "$FAKE_HOME/.pi/agent/skills/example-skill" ]
[ ! -L "$FAKE_HOME/.pi/agent/skills/example-skill" ]
cmp "$STORE/SKILL.md" "$FAKE_HOME/.pi/agent/skills/example-skill/SKILL.md"

for target in \
  "$SANDBOX_HOME/.claude/skills/example-skill" \
  "$SANDBOX_HOME/.codex/skills/example-skill"
do
  [ -d "$target" ]
  [ ! -L "$target" ]
  cmp "$STORE/SKILL.md" "$target/SKILL.md"
done

# --- Traces written into a deployed copy survive a redeploy (ADR 0002) ---

# Each deployed copy accumulates its own traces; deploy used to rm -rf them.
printf '%s\n' \
  '{"ts":"2026-08-30T01:00:00Z","skill":"example-skill","version":"1.0.0","prompt":"from the store","outcome":4,"note":"","source":"llm","schema_version":1}' \
  >> "$STORE/FEEDBACK.jsonl"
printf '%s\n' \
  '{"ts":"2026-08-30T02:00:00Z","skill":"example-skill","version":"1.0.0","prompt":"from pi","outcome":5,"note":"","source":"self","schema_version":1}' \
  >> "$FAKE_HOME/.pi/agent/skills/example-skill/FEEDBACK.jsonl"
printf '%s\n' \
  '{"ts":"2026-08-30T03:00:00Z","skill":"example-skill","version":"1.0.0","prompt":"from the sandbox","outcome":3,"note":"","source":"hybrid","checks":{"ok":true},"schema_version":1}' \
  >> "$SANDBOX_HOME/.codex/skills/example-skill/FEEDBACK.jsonl"
# Two traces sharing a date-only ts are two traces, not one.
printf '%s\n' \
  '{"ts":"2026-08-29T00:00:00Z","skill":"example-skill","prompt":"date-only one","outcome":5}' \
  '{"ts":"2026-08-29T00:00:00Z","skill":"example-skill","prompt":"date-only two","outcome":4}' \
  'not json at all' \
  >> "$SANDBOX_HOME/.claude/skills/example-skill/FEEDBACK.jsonl"

HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/deploy-skill.sh" \
  "$SKILL_DIR" --global --tools claude,codex,pi >/dev/null

REPO_FEEDBACK="$SKILL_DIR/FEEDBACK.jsonl"
grep -q '"prompt":"from the store"' "$REPO_FEEDBACK"
grep -q '"prompt":"from pi"' "$REPO_FEEDBACK"
grep -q '"prompt":"from the sandbox"' "$REPO_FEEDBACK"
grep -q '"prompt":"date-only one"' "$REPO_FEEDBACK"
grep -q '"prompt":"date-only two"' "$REPO_FEEDBACK"
# Unparseable lines are skipped, not appended.
! grep -q 'not json at all' "$REPO_FEEDBACK"

# source is normalised on the way in: self -> llm, hybrid+checks -> script.
python3 - "$REPO_FEEDBACK" <<'PYEOF'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
by_prompt = {r.get("prompt"): r for r in rows}
assert by_prompt["from pi"]["source"] == "llm", by_prompt["from pi"]
assert by_prompt["from the sandbox"]["source"] == "script", by_prompt["from the sandbox"]
assert by_prompt["date-only one"]["source"] == "llm", by_prompt["date-only one"]
assert by_prompt["already home"]["source"] == "user"
PYEOF

# The repo's own line is untouched, byte for byte, and still first.
[ "$(head -1 "$REPO_FEEDBACK")" = "$ORIGINAL_TRACE" ]

# The redeployed copies carry the harvested traces back out.
grep -q '"prompt":"from pi"' "$STORE/FEEDBACK.jsonl"

# iteration_count is derived from the traces, not incremented by hand.
BEFORE_COUNT=$(grep -c '' "$REPO_FEEDBACK")
grep -q "iteration_count: $BEFORE_COUNT" "$SKILL_DIR/CONFIG.yaml"

# Harvest is idempotent: a second run adds nothing.
HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/harvest-feedback.sh" example-skill >/dev/null
[ "$(grep -c '' "$REPO_FEEDBACK")" -eq "$BEFORE_COUNT" ]

# A skill that is deployed but absent from skills/ is skipped, not created.
ORPHAN="$FAKE_HOME/.local/share/skillmonger/skills/orphan-skill"
mkdir -p "$ORPHAN"
printf '%s\n' '{"ts":"2026-08-30T04:00:00Z","skill":"orphan-skill","outcome":5}' \
  > "$ORPHAN/FEEDBACK.jsonl"
HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/harvest-feedback.sh" >/dev/null
[ ! -e "$FAKE_SKILLS/orphan-skill" ]

LOCAL_PROJECT="$TEST_ROOT/project"
mkdir -p "$LOCAL_PROJECT"
HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/deploy-skill.sh" \
  "$SKILL_DIR" --local "$LOCAL_PROJECT" --tools pi >/dev/null
[ -d "$LOCAL_PROJECT/.pi/skills/example-skill" ]
[ ! -e "$LOCAL_PROJECT/.claude/skills/example-skill" ]

# Local deploy targets get harvested before they are removed too.
printf '%s\n' \
  '{"ts":"2026-08-30T05:00:00Z","skill":"example-skill","version":"1.0.0","prompt":"from the project","outcome":4,"note":"","source":"llm","schema_version":1}' \
  >> "$LOCAL_PROJECT/.pi/skills/example-skill/FEEDBACK.jsonl"
HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/deploy-skill.sh" \
  "$SKILL_DIR" --local "$LOCAL_PROJECT" --tools pi >/dev/null
grep -q '"prompt":"from the project"' "$REPO_FEEDBACK"

STORE_ONLY_SKILL="$TEST_ROOT/store-only-skill"
mkdir -p "$STORE_ONLY_SKILL"
cat > "$STORE_ONLY_SKILL/SKILL.md" <<'EOF'
---
name: store-only-skill
description: Fixture for store-only deployment tests.
---

# Store-only Skill
EOF

HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/deploy-skill.sh" \
  "$STORE_ONLY_SKILL" --store-only >/dev/null

[ -d "$FAKE_HOME/.local/share/skillmonger/skills/store-only-skill" ]
[ ! -e "$SANDBOX_HOME/.claude/skills/store-only-skill" ]
[ ! -e "$SANDBOX_HOME/.codex/skills/store-only-skill" ]
[ ! -e "$FAKE_HOME/.pi/agent/skills/store-only-skill" ]

# Undeploy removes from the same targets deploy writes to, and harvests each
# one first: a trace an agent wrote into a copy must be home before rm -rf.
printf '%s\n' '{"ts":"2026-08-31T12:00:00Z","skill":"example-skill","version":"1.0.0","prompt":"from pi before undeploy","outcome":4,"note":"","source":"llm","schema_version":1}' \
  >> "$FAKE_HOME/.pi/agent/skills/example-skill/FEEDBACK.jsonl"
printf '%s\n' '{"ts":"2026-08-31T12:01:00Z","skill":"example-skill","version":"1.0.0","prompt":"from the local project before undeploy","outcome":3,"note":"","source":"llm","schema_version":1}' \
  >> "$LOCAL_PROJECT/.pi/skills/example-skill/FEEDBACK.jsonl"
printf '%s\n' '{"ts":"2026-08-31T12:02:00Z","skill":"example-skill","version":"1.0.0","prompt":"from the sandbox before undeploy","outcome":5,"note":"","source":"script","schema_version":1}' \
  >> "$SANDBOX_HOME/.claude/skills/example-skill/FEEDBACK.jsonl"

HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/undeploy-skill.sh" \
  example-skill --global --local "$LOCAL_PROJECT" --tools pi >/dev/null
[ ! -e "$FAKE_HOME/.pi/agent/skills/example-skill" ]
[ ! -e "$LOCAL_PROJECT/.pi/skills/example-skill" ]
[ ! -e "$STORE" ]
grep -q '"prompt":"from pi before undeploy"' "$REPO_FEEDBACK"
grep -q '"prompt":"from the local project before undeploy"' "$REPO_FEEDBACK"

# --tools pi left the sandbox-home copies alone; the default tool list
# removes them too, and their traces come home first.
[ -d "$SANDBOX_HOME/.claude/skills/example-skill" ]
HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/undeploy-skill.sh" \
  example-skill --global >/dev/null
[ ! -e "$SANDBOX_HOME/.claude/skills/example-skill" ]
[ ! -e "$SANDBOX_HOME/.codex/skills/example-skill" ]
[ ! -e "$FAKE_HOME/.claude/skills/example-skill" ]
grep -q '"prompt":"from the sandbox before undeploy"' "$REPO_FEEDBACK"

echo "deploy-skill tests passed"
