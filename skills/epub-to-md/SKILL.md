---
name: epub-to-md
description: Converts EPUB ebooks to Markdown using epub2md CLI. Handles single files or batch wildcards.
---

# EPUB to Markdown

## When to Use

User wants to convert EPUB file(s) to Markdown.

## Prerequisites

Run `./scripts/check-prereqs.sh`. If `"ready": false`:

| Missing | Action |
|---------|--------|
| node | Direct user to install Node.js 18+ from nodejs.org |
| epub2md | Offer to run `npm install -g epub2md` (requires user confirmation) |

If epub2md is the only missing dependency, ask: "epub2md is not installed. Install it now?" If yes, run the install command and re-run check-prereqs.sh to confirm.

## Workflow

### 1. Validate Input

```bash
ls -la "<epub_path>"  # or: ls <wildcard_pattern>
```

### 2. Create Output Directory

Derive from EPUB filename to avoid overwrites:

```bash
output_dir="${epub_path%.epub}_md"
[ -d "$output_dir" ] && output_dir="${output_dir}_$(date +%s)"
mkdir -p "$output_dir"
```

### 3. Convert

```bash
cd "$output_dir" && epub2md "../<epub_file>"
```

**Options** (ask user preference if not specified):
- `--merge` - Single file instead of per-chapter files
- `--localize` - Download remote images locally (Node 18+)
- `-M` - Fix Chinese/English spacing

**Batch:**
```bash
for f in <pattern>; do d="${f%.epub}_md"; mkdir -p "$d"; (cd "$d" && epub2md "$f" --merge); done
```

### 4. Report

Show file count and location. If issues: `epub2md -S <file>` shows structure, `-i` shows metadata.

## Errors

| Error | Cause |
|-------|-------|
| "Cannot find module" | epub2md not installed globally |
| Empty output | DRM-protected or corrupted EPUB |

---

## After Execution

Two things are worth recording about this run: what the evaluator can check,
and what only a person can judge.

**1. Run the evaluator.**

Run this skill's evaluator on the output you just produced:

```bash
scripts/evaluate.sh   # takes the output on stdin, or as its first argument
```

It prints `{"outcome":1-5,"note":"...","checks":{...},"source":"script"}`.

**2. Ask, then judge.**

**Hybrid**: script + qualitative.

### 1. Run Evaluator

```bash
./scripts/evaluate.sh "<epub_path>" "<output_dir>"
```

Checks size sanity (output ≤ input) and structure (has .md files).

### 2. Ask User

"Does the Markdown preserve the content you expected?"

Map: great→5, good→4, minor issues→3, problems→2, broken→1

Score it on the standard scale: 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent.

**3. Record both.** Append one JSON line per source to `FEEDBACK.jsonl` in this
skill directory — the copy you are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"epub-to-md","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
{"ts":"<UTC ISO 8601>","skill":"epub-to-md","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"user","session":"<this session's id>","schema_version":1}
```

Use `"source":"llm"` on the second line when you judged the run yourself
instead of asking. Drop `session` if you do not know this session's id. Those
lines are the whole record: nothing in `CONFIG.yaml` is edited by a run.
