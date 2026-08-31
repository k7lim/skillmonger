# skill-lock.sh - One writer at a time per skill directory (bash 3.2, no flock)
#
# Every script that does a read-modify-write on skills/<name>/ -- appending
# to FEEDBACK.jsonl and then rewriting CONFIG.yaml -- takes the skill's lock
# first, so a gate run logging traces cannot interleave with a harvest or a
# sync-back rewriting the same two files. `flock` is not on macOS, so the lock
# is a directory: `mkdir` is atomic on every POSIX filesystem and fails when
# the directory exists, which is the whole primitive.
#
#   . "$SCRIPT_DIR/lib/skill-lock.sh"
#   skill_lock "$SKILL_DIR" || exit 1
#   trap skill_unlock EXIT
#   ... read, modify, write ...
#   skill_unlock
#
# The lock is `<skill-dir>/.lock/` and holds the owner's pid for diagnostics.
# Waiting is a poll every 50 ms for up to SKILLMONGER_LOCK_WAIT seconds
# (default 60); past that skill_lock returns 1 and says whose lock it was.
# A lock whose directory is older than SKILLMONGER_LOCK_STALE seconds
# (default 120) was left by a killed process: no holder does more than a few
# hundred milliseconds of work. It is stolen by renaming it away first, so
# two waiters that both see it stale cannot both remove it and both acquire.
#
# scripts/lib/skill_lock.py is the same lock for the python side
# (harvest.py); the two must agree on the path and the two settings.

SKILLMONGER_LOCK_WAIT="${SKILLMONGER_LOCK_WAIT:-60}"
SKILLMONGER_LOCK_STALE="${SKILLMONGER_LOCK_STALE:-120}"

# The lock this shell holds, if any; skill_unlock removes exactly this one.
_SKILL_LOCK_HELD=""

# Seconds since the epoch of a path's mtime, on BSD or GNU stat.
_skill_lock_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

_skill_lock_is_stale() {
  local lock="$1" mtime now
  mtime=$(_skill_lock_mtime "$lock")
  now=$(date +%s)
  [ $((now - mtime)) -ge "$SKILLMONGER_LOCK_STALE" ]
}

# skill_lock DIR: acquire DIR/.lock, waiting; 0 when held, 1 on timeout.
skill_lock() {
  local dir="$1"
  local lock="$dir/.lock"
  local ticks=0
  local max_ticks=$((SKILLMONGER_LOCK_WAIT * 20))
  local stale

  while ! mkdir "$lock" 2>/dev/null; do
    if [ -d "$lock" ] && _skill_lock_is_stale "$lock"; then
      # Rename first: only one waiter wins the rename, so only one removes.
      stale="$lock.stale.$$"
      if mv "$lock" "$stale" 2>/dev/null; then
        echo "  warning: removed stale lock $lock (pid $(cat "$stale/pid" 2>/dev/null || echo '?'))" >&2
        rm -rf "$stale"
      fi
      continue
    fi
    if [ "$ticks" -ge "$max_ticks" ]; then
      echo "Error: could not lock $dir after ${SKILLMONGER_LOCK_WAIT}s;" >&2
      echo "       held by pid $(cat "$lock/pid" 2>/dev/null || echo '?') at $lock" >&2
      return 1
    fi
    sleep 0.05
    ticks=$((ticks + 1))
  done

  echo "$$" > "$lock/pid"
  _SKILL_LOCK_HELD="$lock"
  return 0
}

# skill_unlock: release the lock this shell holds. Safe to call twice.
skill_unlock() {
  if [ -n "$_SKILL_LOCK_HELD" ]; then
    rm -rf "$_SKILL_LOCK_HELD"
    _SKILL_LOCK_HELD=""
  fi
}
