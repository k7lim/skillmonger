#!/bin/bash
# migrate-format-2.sh - Move a skill from skill format 1 to format 2
#
# Usage:
#   scripts/migrate-format-2.sh [--dry-run] skills/<name>/ [skills/<other>/ ...]
#   scripts/migrate-format-2.sh [--dry-run] --all
#
# For each skill it:
#   1. lifts the skill-specific question out of the existing epilogue (the text
#      between "## After Execution" and the first ```json fence), dropping the
#      logging plumbing that format 2 renders itself
#   2. replaces everything from "## After Execution" to end of file with the
#      output of render-epilogue.sh
#   3. sets skill.format: 2 and an evaluation: block in CONFIG.yaml, preserving
#      any evaluation keys already there
#
# Idempotent: a skill already at format 2 is left untouched, so hand fixes made
# after a migration survive a re-run.
#
# Fails loudly (non-zero, skill named) when a skill has no "## After Execution"
# heading rather than appending a second epilogue. Skills with no CONFIG.yaml
# are skipped with a warning; there is nowhere to record the format.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDER="$SCRIPT_DIR/render-epilogue.sh"

DRY_RUN=0
ALL=0
DIRS=()

usage() {
  echo "Usage: migrate-format-2.sh [--dry-run] (--all | <skill-dir> [<skill-dir> ...])" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --all) ALL=1; shift ;;
    -h|--help) usage ;;
    -*) echo "migrate-format-2.sh: unknown option: $1" >&2; usage ;;
    *) DIRS+=("$1"); shift ;;
  esac
done

if [ "$ALL" -eq 1 ]; then
  for d in "$PROJECT_ROOT"/skills/*/; do DIRS+=("$d"); done
fi
[ "${#DIRS[@]}" -gt 0 ] || usage

command -v python3 &> /dev/null || { echo "migrate-format-2.sh: python3 is required" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

migrated=0
skipped=0
failed=0
FAILED_SKILLS=()

# Print the skill's current format (empty when absent).
read_format() {
  python3 - "$1" <<'PY'
import re, sys
try:
    text = open(sys.argv[1]).read()
except OSError:
    sys.exit(0)
block = re.search(r'^skill:\n((?:[ \t].*\n|\n)*)', text, re.M)
if not block:
    sys.exit(0)
m = re.search(r'^[ \t]+format:[ \t]*([^\s#]+)', block.group(1), re.M)
if m:
    print(m.group(1).strip('"\''))
PY
}

# Extract the skill-specific question from a format-1 epilogue.
# stdout: the question (may be empty). stderr: WARN lines for hand review.
extract_question() {
  python3 - "$1" "$2" <<'PY'
import re, sys

path, name = sys.argv[1], sys.argv[2]
lines = open(path).read().split("\n")

start = next((i for i, l in enumerate(lines) if l.strip() == "## After Execution"), None)
if start is None:
    sys.exit(3)

# The epilogue is the section: from its heading to the next "## " heading (not
# counting headings inside a fence) or end of file. camoufox-stealth keeps a
# "## Remote mode" section after its epilogue.
end, fence = len(lines), False
for i in range(start + 1, len(lines)):
    if lines[i].lstrip().startswith("```"):
        fence = not fence
        continue
    if not fence and lines[i].startswith("## "):
        end = i
        break

# The question runs from the heading to the first ```json fence in the section.
body = []
for line in lines[start + 1:end]:
    if line.lstrip().startswith("```json"):
        break
    body.append(line)

PLUMBING = re.compile(r"FEEDBACK\.jsonl|iteration_count|log-feedback", re.I)

# Drop fenced blocks that are logging plumbing; keep other fences verbatim.
kept, fence, buf = [], None, []
for line in body:
    stripped = line.lstrip()
    if fence is None and stripped.startswith("```"):
        fence, buf = line, [line]
        continue
    if fence is not None:
        buf.append(line)
        if stripped.startswith("```"):
            blob = "\n".join(buf)
            if not PLUMBING.search(blob):
                kept.extend(buf)
            fence, buf = None, []
        continue
    kept.append(line)
if fence is not None:            # unterminated fence: keep what we saw
    kept.extend(buf)

DROP_LINE = [
    r"^After completing the skill output,",
    r"^\*\*Priority cascade:\*\*$",
    r"^\d+\.\s+If .?scripts/evaluate.*\b(exists|run it)\b",
    r"^\d+\.\s+Otherwise, self-assess using the scale below\.?$",
    r"^\*\*Self-assessment scale:\*\*\s*1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent\.?$",
    r"^\*\*Scale:\*\*\s*1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent\.?$",
    r"^#{2,6}\s*(Step\s*\d+[:.]?\s*)?Log(\s*Feedback)?\s*$",
    r"^#{2,6}\s*\d+\.\s*Log\s*$",
    r"^\*{0,2}(To\s+)?Log\s+(feedback|both|the\s+result)\b[^.?]*:\s*\*{0,2}$",
]
DROP_LINE = [re.compile(p, re.I) for p in DROP_LINE]
INCREMENT = re.compile(r"increment", re.I)

out, warnings = [], []
for line in kept:
    if any(p.search(line.strip()) for p in DROP_LINE):
        continue
    if line.strip() == "" or line.startswith("    ") or line.startswith("\t"):
        out.append(line)          # blank lines and indented code survive as-is
        continue
    # Sentence-level scrub: a line can carry a real instruction and a logging
    # instruction (e.g. "Final score = min(...). Log to `FEEDBACK.jsonl`:").
    parts = re.split(r"(?<=[.:!?])\s+", line)
    keep_parts = []
    for part in parts:
        if PLUMBING.search(part):
            if "?" in part:
                warnings.append("dropped a question that mentioned the log: %r" % part.strip())
            elif re.search(r"iteration_count", part) and not INCREMENT.search(part):
                warnings.append("dropped a non-increment iteration_count mention: %r" % part.strip())
            continue
        keep_parts.append(part)
    joined = " ".join(p for p in keep_parts if p.strip())
    if joined.strip():
        out.append(joined.rstrip())

# Collapse runs of blank lines, trim the ends.
collapsed = []
for line in out:
    if not line.strip() and (not collapsed or not collapsed[-1].strip()):
        continue
    collapsed.append(line)
while collapsed and not collapsed[-1].strip():
    collapsed.pop()

for w in warnings:
    sys.stderr.write("  WARN %s: %s\n" % (name, w))
sys.stdout.write("\n".join(collapsed))
if collapsed:
    sys.stdout.write("\n")
PY
}

# Cut the epilogue section out and append the rendered one at end of file, so
# every SKILL.md ends with its epilogue whatever followed the old one.
splice_epilogue() { # <skill.md> <rendered-epilogue> <out>
  python3 - "$1" "$2" "$3" <<'PY'
import sys
src, epilogue, dest = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(src).read().split("\n")
start = next(i for i, l in enumerate(lines) if l.strip() == "## After Execution")

# Section bound: the next "## " heading outside a fence, else end of file.
end, fence = len(lines), False
for i in range(start + 1, len(lines)):
    if lines[i].lstrip().startswith("```"):
        fence = not fence
        continue
    if not fence and lines[i].startswith("## "):
        end = i
        break

head, tail = lines[:start], lines[end:]

# The "---" rule before the old epilogue was its separator, so it travels with
# the epilogue rather than being left behind pointing at whatever follows.
while head and not head[-1].strip():
    head.pop()
had_rule = bool(head) and head[-1].strip() == "---"
if had_rule:
    head.pop()
    while head and not head[-1].strip():
        head.pop()

body = head + ([""] + tail if any(l.strip() for l in tail) else [])
while body and not body[-1].strip():
    body.pop()

separator = "\n\n---\n\n" if had_rule else "\n\n"
rendered = open(epilogue).read().rstrip("\n")
open(dest, "w").write("\n".join(body) + separator + rendered + "\n")
PY
}

# Set skill.format: 2 and merge the evaluation: block, keeping comments intact.
rewrite_config() { # <config.yaml> <mode> <script-or-empty> <out>
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import re, sys

src, mode, script, dest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(src).read()

# 1. skill.format: 2 - after skill.name when present, else right under skill:
block = re.search(r'^skill:\n((?:[ \t].*\n|\n)*)', text, re.M)
if not block:
    sys.stderr.write("no skill: block\n")
    sys.exit(4)
body = block.group(1)
if re.search(r'^[ \t]+format:', body, re.M):
    new_body = re.sub(r'^([ \t]+)format:[ \t]*[^\n]*$', r'\g<1>format: 2', body,
                      count=1, flags=re.M)
else:
    name = re.search(r'^([ \t]+)name:[^\n]*\n', body, re.M)
    if name:
        indent = name.group(1)
        new_body = body[:name.end()] + indent + "format: 2\n" + body[name.end():]
    else:
        indent = re.match(r'^([ \t]+)', body).group(1) if re.match(r'^[ \t]', body) else "  "
        new_body = indent + "format: 2\n" + body
text = text[:block.start(1)] + new_body + text[block.end(1):]

# 2. evaluation: block - merge into an existing one, else insert after skill:
DEFAULTS = [("mode", mode)]
if script:
    DEFAULTS.append(("script", script))
DEFAULTS += [("blind", "true"), ("tolerance", "0.5"), ("runner", "claude")]

existing = re.search(r'^evaluation:\n((?:[ \t].*\n|\n)*)', text, re.M)
if existing:
    body = existing.group(1)
    additions = ""
    for key, value in DEFAULTS:
        if not re.search(r'^[ \t]+%s:' % re.escape(key), body, re.M):
            additions += "  %s: %s\n" % (key, value)
    body = body.rstrip("\n") + "\n" + additions
    text = text[:existing.start(1)] + body + text[existing.end(1):]
else:
    lines = ["evaluation:"] + ["  %s: %s" % kv for kv in DEFAULTS]
    rendered = "\n".join(lines) + "\n"
    skill_block = re.search(r'^skill:\n(?:[ \t].*\n|\n)*', text, re.M)
    insert_at = skill_block.end()
    prefix, suffix = text[:insert_at], text[insert_at:]
    if not prefix.endswith("\n\n"):
        rendered = "\n" + rendered
    if suffix.strip() and not suffix.startswith("\n"):
        rendered = rendered + "\n"
    text = prefix + rendered + suffix

open(dest, "w").write(text)
PY
}

show_diff() { # <label> <old> <new>
  if ! diff -q "$2" "$3" >/dev/null 2>&1; then
    diff -u --label "a/$1" --label "b/$1" "$2" "$3" || true
    return 0
  fi
  return 1
}

for raw_dir in "${DIRS[@]}"; do
  dir="${raw_dir%/}"
  if [ ! -d "$dir" ]; then
    echo "ERROR $(basename "$dir"): not a directory" >&2
    failed=$((failed + 1)); FAILED_SKILLS+=("$(basename "$dir")"); continue
  fi
  dir="$(cd "$dir" && pwd)"
  name="$(basename "$dir")"
  skill_md="$dir/SKILL.md"
  config="$dir/CONFIG.yaml"

  if [ ! -f "$skill_md" ]; then
    echo "ERROR $name: no SKILL.md" >&2
    failed=$((failed + 1)); FAILED_SKILLS+=("$name"); continue
  fi
  if [ ! -f "$config" ]; then
    echo "SKIP  $name: no CONFIG.yaml (nowhere to record skill.format)" >&2
    skipped=$((skipped + 1)); continue
  fi

  current_format="$(read_format "$config")"
  if [ "$current_format" = "2" ]; then
    echo "SKIP  $name: already format 2" >&2
    skipped=$((skipped + 1)); continue
  fi

  if ! grep -q '^## After Execution[[:space:]]*$' "$skill_md"; then
    echo "ERROR $name: no '## After Execution' heading in SKILL.md; refusing to append a second epilogue" >&2
    failed=$((failed + 1)); FAILED_SKILLS+=("$name"); continue
  fi

  question="$TMP/$name.question"
  if ! extract_question "$skill_md" "$name" > "$question"; then
    echo "ERROR $name: could not read the existing epilogue" >&2
    failed=$((failed + 1)); FAILED_SKILLS+=("$name"); continue
  fi
  has_question=0
  [ -s "$question" ] && has_question=1

  # Mode: keep what CONFIG already declares, else derive it. A skill with an
  # evaluate script AND a question of its own is hybrid, not programmatic --
  # flattening it to programmatic would drop the question the migration is
  # supposed to preserve.
  mode="$(sed -n '/^evaluation:/,/^[^[:space:]#]/p' "$config" \
    | sed -n 's/^[[:space:]]\{1,\}mode:[[:space:]]*\([^[:space:]#]*\).*/\1/p' | head -1)"
  script="$(sed -n '/^evaluation:/,/^[^[:space:]#]/p' "$config" \
    | sed -n 's/^[[:space:]]\{1,\}script:[[:space:]]*\([^[:space:]#]*\).*/\1/p' | head -1)"
  if [ -z "$script" ]; then
    for candidate in "$dir"/scripts/evaluate*; do
      [ -f "$candidate" ] || continue
      script="scripts/$(basename "$candidate")"
      break
    done
  fi
  if [ -z "$mode" ]; then
    if [ -n "$script" ] && [ "$has_question" -eq 1 ]; then
      mode="hybrid"
    elif [ -n "$script" ]; then
      mode="programmatic"
    else
      mode="qualitative"
    fi
  fi
  case "$mode" in programmatic|hybrid) ;; *) script="" ;; esac

  new_config="$TMP/$name.CONFIG.yaml"
  if ! rewrite_config "$config" "$mode" "$script" "$new_config"; then
    echo "ERROR $name: could not rewrite CONFIG.yaml" >&2
    failed=$((failed + 1)); FAILED_SKILLS+=("$name"); continue
  fi

  # Render from the rewritten CONFIG so the epilogue matches what will land.
  staged="$TMP/$name.skilldir"
  rm -rf "$staged"; mkdir -p "$staged"
  cp "$new_config" "$staged/CONFIG.yaml"
  [ -d "$dir/scripts" ] && cp -R "$dir/scripts" "$staged/scripts"

  epilogue="$TMP/$name.epilogue"
  if ! "$RENDER" "$staged" --question-file "$question" > "$epilogue"; then
    echo "ERROR $name: render-epilogue.sh failed" >&2
    failed=$((failed + 1)); FAILED_SKILLS+=("$name"); continue
  fi

  new_skill_md="$TMP/$name.SKILL.md"
  if ! splice_epilogue "$skill_md" "$epilogue" "$new_skill_md"; then
    echo "ERROR $name: could not splice the epilogue" >&2
    failed=$((failed + 1)); FAILED_SKILLS+=("$name"); continue
  fi

  rel="skills/$name"
  if [ "$DRY_RUN" -eq 1 ]; then
    changed=1
    show_diff "$rel/SKILL.md" "$skill_md" "$new_skill_md" && changed=0
    show_diff "$rel/CONFIG.yaml" "$config" "$new_config" && changed=0
    if [ "$changed" -eq 0 ]; then
      echo "DRY   $name: format 2, mode $mode" >&2
      migrated=$((migrated + 1))
    else
      skipped=$((skipped + 1))
    fi
  else
    cp "$new_skill_md" "$skill_md"
    cp "$new_config" "$config"
    echo "OK    $name: format 2, mode $mode" >&2
    migrated=$((migrated + 1))
  fi
done

if [ "$DRY_RUN" -eq 1 ]; then
  echo "" >&2
  echo "dry run: $migrated would change, $skipped unchanged, $failed failed" >&2
else
  echo "" >&2
  echo "migrated: $migrated, unchanged: $skipped, failed: $failed" >&2
fi

if [ "$failed" -gt 0 ]; then
  echo "failed skills: ${FAILED_SKILLS[*]}" >&2
  exit 1
fi
exit 0
