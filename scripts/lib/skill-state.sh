# skill-state.sh - read and write ~/.skillmonger-state as data, never as code.
#
# Sourced, never executed. `scripts/skill` reads the file to show status,
# `develop-skill.sh` writes it, `ship-skill.sh` clears it. The file is mutable
# shared state that any agent with a home directory can edit, so it is treated
# as untrusted input: it is parsed line by line, never `source`d or `eval`ed.
#
# Format: one `KEY=VALUE` per line, value taken literally to end of line.
# Nothing is quoted, escaped or expanded. Blank lines are ignored.
#
# Keys are a fixed allowlist. A value may not contain control characters,
# `$(`, `${` or backticks; a path-valued key must be absolute and free of `..`
# segments. The writer applies the same rules, so it cannot produce a file the
# reader refuses.
#
# Interface:
#   skill_state_load FILE            sets STATE_<KEY> for every allowed key
#                                    (empty when absent); returns 1 and prints
#                                    a reason to stderr on any rejection
#   skill_state_save FILE KEY=VALUE...
#                                    validates, then writes atomically;
#                                    returns 1 and writes nothing on rejection
#
# Loaded values live under a STATE_ prefix so a caller's own SKILL_NAME is
# never clobbered by whatever the file says.
#
# Targets /bin/bash 3.2: no associative arrays, no mapfile.

SKILL_STATE_KEYS="SKILL_NAME SKILL_DIR LAST_ACTION TIMESTAMP NEXT_STEP AFTER_THAT"
SKILL_STATE_REQUIRED_KEYS="SKILL_NAME SKILL_DIR LAST_ACTION TIMESTAMP NEXT_STEP"
SKILL_STATE_PATH_KEYS="SKILL_DIR"

# _skill_state_in_list WORD "LIST OF WORDS"
_skill_state_in_list() {
  case " $2 " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# _skill_state_check_value KEY VALUE — prints a reason and returns 1 on rejection.
_skill_state_check_value() {
  local key="$1" value="$2"

  if [[ "$value" == *[[:cntrl:]]* ]]; then
    echo "control character in $key"
    return 1
  fi
  # shellcheck disable=SC2016  # literal patterns, expansion is the thing being refused
  case "$value" in
    *'$('*|*'${'*|*'`'*)
      echo "command substitution in $key"
      return 1
      ;;
    '"'*)
      echo "quoted value in $key (old shell format)"
      return 1
      ;;
  esac

  case "$key" in
    SKILL_NAME)
      if [[ ! "$value" =~ ^[a-z0-9-]+$ ]]; then
        echo "SKILL_NAME must be lowercase letters, digits and hyphens"
        return 1
      fi
      ;;
  esac

  if _skill_state_in_list "$key" "$SKILL_STATE_PATH_KEYS"; then
    case "$value" in
      /*) ;;
      *)
        echo "$key must be an absolute path"
        return 1
        ;;
    esac
    case "/$value/" in
      *"/../"*)
        echo "path traversal in $key"
        return 1
        ;;
    esac
  fi
  return 0
}

# _skill_state_check_key KEY — printed reason and 1 on an unknown key.
_skill_state_check_key() {
  if ! _skill_state_in_list "$1" "$SKILL_STATE_KEYS"; then
    echo "unknown key $1"
    return 1
  fi
  return 0
}

skill_state_load() {
  local file="$1" key line lineno=0 reason seen="" value

  for key in $SKILL_STATE_KEYS; do
    printf -v "STATE_$key" '%s' ''
  done

  if [ ! -f "$file" ]; then
    echo "skill state: $file: no such file" >&2
    return 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    [ -z "$line" ] && continue

    case "$line" in
      [A-Z]*=*) ;;
      *)
        echo "skill state: $file line $lineno: malformed line (expected KEY=VALUE)" >&2
        return 1
        ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"

    if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
      echo "skill state: $file line $lineno: malformed key $key" >&2
      return 1
    fi
    if ! reason="$(_skill_state_check_key "$key")"; then
      echo "skill state: $file line $lineno: $reason" >&2
      return 1
    fi
    if _skill_state_in_list "$key" "$seen"; then
      echo "skill state: $file line $lineno: duplicate key $key" >&2
      return 1
    fi
    seen="$seen $key"
    if ! reason="$(_skill_state_check_value "$key" "$value")"; then
      echo "skill state: $file line $lineno: $reason" >&2
      return 1
    fi
    printf -v "STATE_$key" '%s' "$value"
  done < "$file"

  for key in $SKILL_STATE_REQUIRED_KEYS; do
    if ! _skill_state_in_list "$key" "$seen"; then
      echo "skill state: $file: missing key $key" >&2
      return 1
    fi
  done
  return 0
}

skill_state_save() {
  local file="$1" content="" key pair reason seen="" value
  shift

  for pair in "$@"; do
    case "$pair" in
      *=*) ;;
      *)
        echo "skill state: refusing to write malformed pair $pair" >&2
        return 1
        ;;
    esac
    key="${pair%%=*}"
    value="${pair#*=}"
    if ! reason="$(_skill_state_check_key "$key")"; then
      echo "skill state: refusing to write: $reason" >&2
      return 1
    fi
    if _skill_state_in_list "$key" "$seen"; then
      echo "skill state: refusing to write: duplicate key $key" >&2
      return 1
    fi
    seen="$seen $key"
    if ! reason="$(_skill_state_check_value "$key" "$value")"; then
      echo "skill state: refusing to write: $reason" >&2
      return 1
    fi
    content="$content$key=$value
"
  done

  for key in $SKILL_STATE_REQUIRED_KEYS; do
    if ! _skill_state_in_list "$key" "$seen"; then
      echo "skill state: refusing to write: missing key $key" >&2
      return 1
    fi
  done

  printf '%s' "$content" > "$file.tmp.$$" && mv "$file.tmp.$$" "$file"
}
