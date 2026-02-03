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

## Feedback

**Hybrid**: script + qualitative.

### 1. Run Evaluator

```bash
./scripts/evaluate.sh "<epub_path>" "<output_dir>"
```

Checks size sanity (output ≤ input) and structure (has .md files).

### 2. Ask User

"Does the Markdown preserve the content you expected?"

Map: great→5, good→4, minor issues→3, problems→2, broken→1

### 3. Log

Append to `FEEDBACK.jsonl`:
```json
{"ts":"<ISO8601>","skill":"epub-to-md","version":"0.1.0","prompt":"<request>","outcome":<1-5>,"note":"","source":"hybrid","schema_version":1}
```

Increment `iteration_count` in `CONFIG.yaml`.
