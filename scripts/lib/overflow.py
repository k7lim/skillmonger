#!/usr/bin/env python3
"""Wiki overflow: MEMO.md spills into memo/patterns/ (roadmap 6, format 2.1).

A skill's wiki (CONTEXT.md: **Wiki**) is one file until it outgrows one file.
This module decides when that has happened -- more words than the skill's
`budget.memo_max`, or more than 12 `### ` pattern entries -- and, on demand,
performs the move: each pattern entry becomes `memo/patterns/<slug>.md` and
leaves one index line behind in MEMO.md.

Two modes, both driven by scripts/compact-memo.sh:

    python3 overflow.py --skill-dir <dir> [--label <shown-path>]   # the offer
    python3 overflow.py --skill-dir <dir> --apply                  # the move

`--apply` is the only thing in the Maintainer's brief that writes to the wiki,
and it writes nothing unless the wiki is over budget. `loading.on_failure`
stays MEMO.md and CONFIG.yaml is never touched: the index lines keep the
overflowed patterns one hop from the file the agent already loads.

Exit codes: 0 done (or nothing to do), 2 refused (slug collision, or a
`memo/patterns/<slug>.md` that already exists with different content).
"""

from __future__ import annotations

import argparse
import os
import re
import sys

try:
    import yaml
except ImportError:  # CONFIG is scanned line by line instead; see read_memo_max
    yaml = None


# Documented in docs/skill-format.md: the budget block's memo_max, and the
# value assumed for the ten skills whose CONFIG.yaml omits it.
DEFAULT_MEMO_MAX = 2000

# The second trigger. A wiki with more entries than this is a list to search,
# not a page to read, whatever it weighs.
MAX_PATTERN_ENTRIES = 12

PATTERNS_DIR = "memo/patterns"

# Long free-form headings make unusable filenames; a derived slug is a starting
# point the maintainer is told to rename anyway.
MAX_SLUG_LEN = 60

ENTRY_PREFIX = "### "
# `#`, `##` and `###` all close an entry; `####` and deeper are inside one.
HEADING = re.compile(r"^#{1,3} ")
FENCE = re.compile(r"^\s*(```|~~~)")
# The pattern layout's heading: `### <slug>: short title`.
SLUG_TITLE = re.compile(r"^([a-z0-9][a-z0-9-]*)\s*:\s*(.+)$")
STATUS_LINE = re.compile(r"^\s*[-*]\s*status\s*:\s*(.+?)\s*$", re.IGNORECASE)
# A markdown horizontal rule: --- or *** or ___.
RULE = re.compile(r"^\s*([-*_])\1{2,}\s*$")
# An index line a previous overflow left behind.
INDEXED = re.compile(r"^- \[[^\]]+\]\(" + re.escape(PATTERNS_DIR) + r"/[^)]+\.md\)")


# --- CONFIG ---------------------------------------------------------------


def read_memo_max(config_path):
    """`budget.memo_max`, and whether the skill actually stated it.

    Returns (limit, stated). Ten of the 52 skills have no budget block; they
    get DEFAULT_MEMO_MAX rather than an exemption from the trigger.
    """
    if not os.path.exists(config_path):
        return DEFAULT_MEMO_MAX, False
    text = open(config_path, "r", encoding="utf-8", errors="replace").read()
    if yaml is not None:
        try:
            config = yaml.safe_load(text) or {}
        except Exception:
            config = {}
        budget = config.get("budget") if isinstance(config, dict) else None
        if isinstance(budget, dict):
            value = budget.get("memo_max")
            if isinstance(value, bool):
                value = None
            if isinstance(value, int) and value > 0:
                return value, True
            if isinstance(value, str) and value.strip().isdigit():
                return int(value.strip()), True
        return DEFAULT_MEMO_MAX, False
    inside = False
    for line in text.splitlines():
        if line.startswith("budget:"):
            inside = True
            continue
        if inside and line.strip() and not line[:1].isspace():
            break
        if not inside:
            continue
        match = re.match(r"\s+memo_max\s*:\s*(\d+)", line)
        if match:
            return int(match.group(1)), True
    return DEFAULT_MEMO_MAX, False


# --- the wiki -------------------------------------------------------------


def slugify(text):
    """A stable lowercase-with-hyphens name derived from a free-form heading."""
    text = re.sub(r"[‘’'`\"]", "", text.strip().lower())
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    if len(text) > MAX_SLUG_LEN:
        cut = text[:MAX_SLUG_LEN]
        text = (cut.rsplit("-", 1)[0] if "-" in cut else cut).strip("-")
    return text


def _heading_map(lines):
    """(is_heading, is_entry) per line, ignoring anything inside a code fence."""
    heading = [False] * len(lines)
    entry = [False] * len(lines)
    fence = None
    for i, line in enumerate(lines):
        match = FENCE.match(line)
        if match:
            token = match.group(1)
            if fence is None:
                fence = token
            elif line.strip().startswith(fence):
                fence = None
            continue
        if fence is not None:
            continue
        if HEADING.match(line):
            heading[i] = True
            entry[i] = line.startswith(ENTRY_PREFIX)
    return heading, entry


def _split_body(body):
    """Body content, and whether a horizontal rule closed the entry.

    An entry's span runs to the next heading, so it swallows the blank lines
    and the `---` separator the wiki puts between entries. Those are the
    document's furniture, not the pattern's: the moved file drops them, and
    the rewrite re-emits one rule where the run of entries ended.
    """
    end = len(body)
    while end > 0 and not body[end - 1].strip():
        end -= 1
    had_rule = False
    if end > 0 and RULE.match(body[end - 1]):
        had_rule = True
        end -= 1
        while end > 0 and not body[end - 1].strip():
            end -= 1
    return body[:end], had_rule


def parse_entries(lines):
    """Every `### ` entry: where it starts and ends, its slug, status, title.

    An entry ends at the next `### `/`## `/`# ` heading or at EOF. A heading
    whose text is `<slug>: title` is in the pattern layout (format 1.2); any
    other `### ` heading is a free-form entry whose slug is derived from it.
    """
    heading, is_entry = _heading_map(lines)
    entries = []
    for start, entry in enumerate(is_entry):
        if not entry:
            continue
        end = len(lines)
        for j in range(start + 1, len(lines)):
            if heading[j]:
                end = j
                break
        title_text = lines[start][len(ENTRY_PREFIX) :].strip()
        content, had_rule = _split_body(lines[start + 1 : end])
        match = SLUG_TITLE.match(title_text)
        if match:
            slug, title, derived = match.group(1), match.group(2).strip(), False
        else:
            slug, title, derived = slugify(title_text), title_text, True
        status = "open"
        for line in content:
            found = STATUS_LINE.match(line)
            if found:
                status = found.group(1).strip()
                break
        entries.append(
            {
                "start": start,
                "end": end,
                "line": start + 1,
                "heading": lines[start],
                "title": title,
                "slug": slug,
                "derived": derived,
                "status": status,
                "content": content,
                "had_rule": had_rule,
            }
        )
    return entries


def entry_file(entry):
    """The pattern's own file: the entry moved, not rewritten."""
    body = "\n".join([entry["heading"]] + entry["content"]).rstrip("\n")
    return body + "\n"


def index_line(entry):
    """The one line the pattern leaves behind in MEMO.md."""
    return (
        f"- [{entry['slug']}]({PATTERNS_DIR}/{entry['slug']}.md): "
        f"{entry['status']}, {entry['title']}"
    )


def rewrite(lines, entries):
    """MEMO.md with each entry replaced by its index line, everything else kept."""
    by_start = {e["start"]: e for e in entries}
    out = []
    pending_rule = False
    just_indexed = False
    i = 0
    while i < len(lines):
        entry = by_start.get(i)
        if entry is not None:
            out.append(index_line(entry))
            pending_rule = entry["had_rule"]
            just_indexed = True
            i = entry["end"]
            continue
        # An entry's span swallowed whatever separated it from what follows,
        # so the run of index lines has to put a separator back: the rule the
        # entries were divided by, or at least the blank line a heading needs.
        if pending_rule:
            out.extend(["", "---", ""])
        elif just_indexed and lines[i].strip():
            out.append("")
        pending_rule = False
        just_indexed = False
        out.append(lines[i])
        i += 1
    if pending_rule:
        out.extend(["", "---"])
    return out


# --- the decision ---------------------------------------------------------


def survey(skill_dir):
    """What the wiki weighs, what its budget is, and why it is (not) over."""
    memo_path = os.path.join(skill_dir, "MEMO.md")
    config_path = os.path.join(skill_dir, "CONFIG.yaml")
    limit, stated = read_memo_max(config_path)
    text = ""
    if os.path.exists(memo_path):
        text = open(memo_path, "r", encoding="utf-8", errors="replace").read()
    lines = text.splitlines()
    entries = parse_entries(lines)
    words = len(text.split())
    over = []
    if words > limit:
        over.append(f"{words} words > memo_max {limit}")
    if len(entries) > MAX_PATTERN_ENTRIES:
        over.append(f"{len(entries)} pattern entries > {MAX_PATTERN_ENTRIES}")
    return {
        "memo_path": memo_path,
        "text": text,
        "lines": lines,
        "entries": entries,
        "words": words,
        "limit": limit,
        "stated": stated,
        "over": over,
    }


# --- the offer ------------------------------------------------------------


def report(skill_dir, label):
    """The lines compact-memo.sh prints under the wiki's size. Never writes."""
    state = survey(skill_dir)
    source = (
        "budget.memo_max"
        if state["stated"]
        else "default; CONFIG.yaml states no budget.memo_max"
    )
    print(f"  Budget: {state['words']} of {state['limit']} words ({source})")
    print(
        f"  Pattern entries: {len(state['entries'])} `### ` headings "
        f"(overflow above {MAX_PATTERN_ENTRIES})"
    )
    if not state["over"]:
        print("  Within budget: the wiki stays one file.")
        return 0
    print("")
    print("  ⚠ OVER BUDGET - wiki overflow is available (format 2.1):")
    for reason in state["over"]:
        print(f"    - {reason}")
    print("")
    if state["entries"]:
        print(f"  Overflow moves each of the {len(state['entries'])} `### ` entries to")
        print("  memo/patterns/<slug>.md and leaves one index line per pattern in")
        print("  MEMO.md. loading.on_failure stays MEMO.md; CONFIG.yaml is not")
        print("  touched. To do it:")
        print("")
        print(f"      scripts/compact-memo.sh {label} --overflow")
        print("")
        print("  Nothing is written without that flag.")
    else:
        print("  This wiki has no `### ` entries, so there is nothing to overflow:")
        print("  overflow moves pattern entries, not `## ` sections. Convert what")
        print("  the wiki holds into pattern entries first (docs/skill-format.md,")
        print("  MEMO.md section), or trim it.")
    return 0


# --- the move -------------------------------------------------------------


def apply(skill_dir, label):
    """Perform the overflow. Refuses (2) rather than overwrite anything."""
    state = survey(skill_dir)
    if not state["over"]:
        print(
            f"  Within budget: {state['words']} of {state['limit']} words, "
            f"{len(state['entries'])} of {MAX_PATTERN_ENTRIES} entries."
        )
        print("  Nothing moved. The wiki stays one file until it outgrows one;")
        print("  lower budget.memo_max in CONFIG.yaml if this one already has.")
        return 0

    entries = state["entries"]
    print("  Over budget: " + "; ".join(state["over"]))
    if not entries:
        indexed = sum(1 for line in state["lines"] if INDEXED.match(line))
        if indexed:
            print(f"  Already overflowed: {indexed} index line(s) in MEMO.md and no")
            print("  `### ` entries left to move. Nothing written.")
        else:
            print("  This wiki has no `### ` entries, so there is nothing to move:")
            print("  overflow moves pattern entries, not `## ` sections. Convert what")
            print("  the wiki holds into pattern entries first (docs/skill-format.md,")
            print("  MEMO.md section), or trim it. Nothing written.")
        return 0

    # Collisions first: two entries that slug the same would silently eat each
    # other, and an empty slug has no filename at all.
    seen = {}
    for entry in entries:
        if not entry["slug"]:
            sys.stderr.write(
                f"overflow: MEMO.md:{entry['line']} `### {entry['title']}` has no "
                "usable slug; give it a `### <slug>: title` heading.\n"
            )
            return 2
        if entry["slug"] in seen:
            other = seen[entry["slug"]]
            sys.stderr.write(
                f"overflow: MEMO.md:{other['line']} and MEMO.md:{entry['line']} "
                f"both give slug `{entry['slug']}`; rename one heading.\n"
            )
            return 2
        seen[entry["slug"]] = entry

    # Then the files on disk, all of them, before writing any of them.
    targets = []
    conflicts = []
    for entry in entries:
        rel = f"{PATTERNS_DIR}/{entry['slug']}.md"
        path = os.path.join(skill_dir, rel)
        content = entry_file(entry)
        if os.path.exists(path):
            existing = open(path, "r", encoding="utf-8", errors="replace").read()
            if existing != content:
                conflicts.append(rel)
                continue
        targets.append((rel, path, content))
    if conflicts:
        sys.stderr.write(
            "overflow: refusing to overwrite an existing pattern file whose "
            "content differs:\n"
        )
        for rel in conflicts:
            sys.stderr.write(f"  {rel}\n")
        sys.stderr.write(
            "  Merge the MEMO.md entry into it by hand, delete the entry, and "
            "re-run.\n"
        )
        return 2

    os.makedirs(os.path.join(skill_dir, PATTERNS_DIR), exist_ok=True)
    for rel, path, content in targets:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(content)

    new_lines = rewrite(state["lines"], entries)
    with open(state["memo_path"], "w", encoding="utf-8") as handle:
        handle.write("\n".join(new_lines).rstrip("\n") + "\n")

    print(f"  Moved {len(entries)} entr{'y' if len(entries) == 1 else 'ies'} out of MEMO.md:")
    for entry in entries:
        print(f"    {PATTERNS_DIR}/{entry['slug']}.md  <- {entry['title']}")
    derived = [e for e in entries if e["derived"]]
    if derived:
        print("")
        print(f"  {len(derived)} of them had no `<slug>: title` heading, so the slug was")
        print("  derived from the heading text (lowercase-with-hyphens):")
        for entry in derived:
            print(f"    {entry['slug']}  <- ### {entry['title']}")
        print("  A slug is provenance: it is what the Iteration Log's `Patterns`")
        print("  column names when the pattern graduates. Rename any that read")
        print("  badly now, while nothing cites them yet.")
    print("")
    print("  MEMO.md keeps one index line per pattern and stays the file")
    print("  loading.on_failure names. CONFIG.yaml is unchanged.")
    print("")
    print(f"  Read the diff before committing: {label}")
    return 0


def main(argv):
    parser = argparse.ArgumentParser(add_help=True, description=__doc__)
    parser.add_argument("--skill-dir", required=True)
    parser.add_argument("--label", default=None, help="path to show in printed commands")
    parser.add_argument("--apply", action="store_true", help="perform the move")
    args = parser.parse_args(argv)

    skill_dir = args.skill_dir.rstrip("/") or "/"
    label = args.label or args.skill_dir
    if not os.path.isdir(skill_dir):
        sys.stderr.write(f"overflow: not a directory: {skill_dir}\n")
        return 2
    if not os.path.exists(os.path.join(skill_dir, "MEMO.md")):
        print("  No MEMO.md: no wiki to overflow.")
        return 0
    return apply(skill_dir, label) if args.apply else report(skill_dir, label)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
