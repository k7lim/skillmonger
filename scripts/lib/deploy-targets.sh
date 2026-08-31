# deploy-targets.sh - the single definition of where a deployed copy can live.
#
# Sourced, never executed. deploy-skill.sh reads it to install skills;
# harvest-feedback.sh reads it to collect the traces those copies accumulated
# (ADR 0002). Keeping one definition is the point: a target the harvester does
# not know about is a target whose traces deploy destroys.
#
# $HOME is read at source time, so a caller can redirect every target by
# overriding HOME (the tests do) or just the sandbox home via
# YOLOBOX_SANDBOX_HOME.

SKILLMONGER_DIR="$HOME/.local/share/skillmonger/skills"

# Tool directory mappings
# Format: tool:global_path:local_path:global_mode
TOOL_PATHS=(
  "claude:$HOME/.claude/skills:.claude/skills:symlink"
  "codex:$HOME/.codex/skills:.codex/skills:symlink"
  "opencode:$HOME/.config/opencode/skills:.opencode/skills:symlink"
  "pi:$HOME/.pi/agent/skills:.pi/skills:copy"
)

# Protected workspaces run every agent under one redirected HOME (the sandbox
# home, see yolobox-pattern example/seed-sandbox-home.sh). Skills must be
# copied there because the sandbox denies the shared ~/.local store that backs
# the host symlinks. The pre-2026-08-25 per-tool homes (~/.claude-yolobox,
# ~/.codex-yolobox) are retired.
YOLOBOX_SANDBOX_HOME="${YOLOBOX_SANDBOX_HOME:-$HOME/.local/share/yolobox/home}"
SANDBOX_TOOL_PATHS=(
  "claude:$YOLOBOX_SANDBOX_HOME/.claude/skills"
  "codex:$YOLOBOX_SANDBOX_HOME/.codex/skills"
)

# Every directory that holds deployed copies, one per line: the store, the
# per-tool global directories (some of which symlink back into the store), and
# the sandbox homes. Project-local deployments (--local <dir>) are per project
# and cannot be enumerated here; the caller adds those with --target.
deploy_target_roots() {
  local entry tool global_path local_path global_mode sandbox_path
  printf '%s\n' "$SKILLMONGER_DIR"
  for entry in "${TOOL_PATHS[@]}"; do
    IFS=':' read -r tool global_path local_path global_mode <<< "$entry"
    printf '%s\n' "$global_path"
  done
  for entry in "${SANDBOX_TOOL_PATHS[@]}"; do
    IFS=':' read -r tool sandbox_path <<< "$entry"
    printf '%s\n' "$sandbox_path"
  done
}
