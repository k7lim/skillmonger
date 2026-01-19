#!/bin/bash
# install-hooks.sh - Install git hooks for skills framework
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_SOURCE="$PROJECT_ROOT/hooks"
HOOKS_TARGET="$PROJECT_ROOT/.git/hooks"

echo "Installing git hooks..."
echo ""

if [ ! -d "$PROJECT_ROOT/.git" ]; then
  echo "ERROR: Not a git repository"
  echo "Run 'git init' first."
  exit 1
fi

if [ ! -d "$HOOKS_SOURCE" ]; then
  echo "ERROR: Hooks source directory not found: $HOOKS_SOURCE"
  exit 1
fi

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_TARGET"

# Install each hook
for hook in "$HOOKS_SOURCE"/*; do
  if [ -f "$hook" ]; then
    hook_name=$(basename "$hook")
    target="$HOOKS_TARGET/$hook_name"

    # Backup existing hook if present
    if [ -f "$target" ] && [ ! -L "$target" ]; then
      echo "  Backing up existing $hook_name to $hook_name.backup"
      mv "$target" "$target.backup"
    fi

    # Create symlink to our hook
    ln -sf "$hook" "$target"
    chmod +x "$target"
    echo "  ✓ Installed: $hook_name"
  fi
done

echo ""
echo "Done. Hooks installed:"
ls -la "$HOOKS_TARGET" | grep -E "pre-|post-|commit-" || echo "  (none found)"
