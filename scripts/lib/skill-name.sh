# skill-name.sh - the one check a skill name passes before it becomes a path.
#
# Sourced, never executed. Every framework script that takes a skill name (or
# a skills/<name>/ path it reduces to a name) and then reads or writes under
# <root>/<name> calls skill_name_require first, so `..`, a slash, an encoded
# `%2e%2e`, an option-shaped `--x`, a control character or an empty string
# never reaches rm -rf, cp, mkdir or a FEEDBACK.jsonl append.
#
# The contract is the one validate-skill.sh enforces on SKILL.md frontmatter
# and AGENTS.md documents under Validation Constraints: lowercase letters,
# digits and hyphens; no leading, trailing or consecutive hyphens; at most 64
# characters. A name that passes cannot leave its root by construction.
#
# Interface:
#   skill_name_valid NAME           0 when NAME meets the contract, 1 otherwise;
#                                   prints nothing
#   skill_name_require NAME         exits 2 with one line on stderr when NAME
#                                   is rejected; silent otherwise
#   skill_dir_require DIR ROOT      DIR must exist and canonicalise (pwd -P) to
#                                   ROOT/<valid name>; exits 2 with one line on
#                                   stderr otherwise. Catches a skills/<name>
#                                   that is a symlink pointing out of skills/.
#   skill_name_from_path PATH       prints the last path component with any
#                                   trailing slashes removed; never runs
#                                   basename, so `--x` needs no `--` guard
#
# Rejections are one line so an agent can match them:
#   ERROR: invalid skill name '<name>' (expected lowercase letters, digits and hyphens)
#   ERROR: skill path '<dir>' resolves outside '<root>'
#
# Targets /bin/bash 3.2: no associative arrays, no mapfile.

SKILL_NAME_RULE="lowercase letters, digits and hyphens"
SKILL_NAME_MAX=64

skill_name_valid() {
  local name="$1"
  [ -n "$name" ] || return 1
  [ "${#name}" -le "$SKILL_NAME_MAX" ] || return 1
  # Spelled out rather than a-z so no locale's collation widens the range.
  case "$name" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
    -*|*-|*--*) return 1 ;;
  esac
  return 0
}

# The name is echoed back in the error so the caller sees what was refused,
# with control characters replaced so the line stays one line.
_skill_name_display() {
  printf '%s' "$1" | tr '[:cntrl:]' '?'
}

skill_name_require() {
  if ! skill_name_valid "$1"; then
    echo "ERROR: invalid skill name '$(_skill_name_display "$1")' (expected $SKILL_NAME_RULE)" >&2
    exit 2
  fi
}

skill_name_from_path() {
  local path="$1"
  while [ "${#path}" -gt 1 ] && [ "${path%/}" != "$path" ]; do
    path="${path%/}"
  done
  printf '%s\n' "${path##*/}"
}

skill_dir_require() {
  local dir="$1" root="$2" real_dir real_root
  real_root="$(cd "$root" 2>/dev/null && pwd -P)" || {
    echo "ERROR: skill path '$dir' resolves outside '$root'" >&2
    exit 2
  }
  real_dir="$(cd "$dir" 2>/dev/null && pwd -P)" || {
    echo "ERROR: skill path '$dir' resolves outside '$root'" >&2
    exit 2
  }
  if [ "${real_dir%/*}" != "$real_root" ] || ! skill_name_valid "${real_dir##*/}"; then
    echo "ERROR: skill path '$dir' resolves outside '$root'" >&2
    exit 2
  fi
}
