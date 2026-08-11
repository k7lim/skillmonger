#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

FAKE_HOME="$TEST_ROOT/home"
SKILL_DIR="$TEST_ROOT/example-skill"
mkdir -p \
  "$FAKE_HOME/.claude-yolobox" \
  "$FAKE_HOME/.codex-yolobox" \
  "$SKILL_DIR"

cat > "$SKILL_DIR/SKILL.md" <<'EOF'
---
name: example-skill
description: Fixture for deployment tests.
---

# Example Skill
EOF

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
  "$FAKE_HOME/.claude-yolobox/skills/example-skill" \
  "$FAKE_HOME/.codex-yolobox/skills/example-skill"
do
  [ -d "$target" ]
  [ ! -L "$target" ]
  cmp "$STORE/SKILL.md" "$target/SKILL.md"
done

LOCAL_PROJECT="$TEST_ROOT/project"
mkdir -p "$LOCAL_PROJECT"
HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/deploy-skill.sh" \
  "$SKILL_DIR" --local "$LOCAL_PROJECT" --tools pi >/dev/null
[ -d "$LOCAL_PROJECT/.pi/skills/example-skill" ]
[ ! -e "$LOCAL_PROJECT/.claude/skills/example-skill" ]

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
[ ! -e "$FAKE_HOME/.claude-yolobox/skills/store-only-skill" ]
[ ! -e "$FAKE_HOME/.codex-yolobox/skills/store-only-skill" ]
[ ! -e "$FAKE_HOME/.pi/agent/skills/store-only-skill" ]

HOME="$FAKE_HOME" "$PROJECT_ROOT/scripts/undeploy-skill.sh" \
  example-skill --global --local "$LOCAL_PROJECT" --tools pi >/dev/null
[ ! -e "$FAKE_HOME/.pi/agent/skills/example-skill" ]
[ ! -e "$LOCAL_PROJECT/.pi/skills/example-skill" ]
[ ! -e "$STORE" ]

echo "deploy-skill tests passed"
