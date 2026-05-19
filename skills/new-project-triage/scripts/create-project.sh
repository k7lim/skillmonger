#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: create-project.sh TARGET_DIR" >&2
  exit 2
fi

target_input="$1"
target_dir="${target_input/#\~/$HOME}"
dev_root="$HOME/Development"

case "$target_dir" in
  "$dev_root"/*) ;;
  *)
    echo "error: target must be under $dev_root" >&2
    exit 2
    ;;
esac

mkdir -p "$target_dir"

notes_path="$target_dir/NOTES.md"
if [[ -e "$notes_path" ]]; then
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  notes_path="$target_dir/NOTES-$stamp.md"
fi

notes="$(cat)"
if [[ -z "${notes//[[:space:]]/}" ]]; then
  notes="_No original notes were provided._"
fi

printf '%s\n' "$notes" > "$notes_path"
printf '%s\n' "$notes_path"
