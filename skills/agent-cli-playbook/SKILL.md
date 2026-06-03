---
name: agent-cli-playbook
description: "Use for agent-friendly shell, terminal, Bash, and CLI command selection: search with rg --json or bounded rg -n -C, read with bat --plain --color=never, inspect raw git diff --no-ext-diff instead of delta, validate JSON with jq -e, query SQLite with sqlite3 -json, find listeners/processes with lsof and ps, and check HTTP with curl status/content-type/body validation."
metadata:
  short-description: Agent-friendly CLI command defaults
---

# Agent CLI Playbook

Use these command shapes when shell output is feeding agent reasoning. Prefer bounded, parseable, plain-text output over pager-oriented or decorative output.

## Defaults

- Search: use `rg --json` when a script or structured pass will consume matches.
- Search for human reading: use bounded context, for example `rg -n -C 2 'pattern' path/`.
- Read files: use `bat --plain --color=never path` so output has no theme, paging, or decoration.
- Inspect diffs: use plain `git diff --no-ext-diff`. Do not use `delta` for agent reasoning; it adds presentation that can obscure raw diff semantics.
- Validate JSON: use `jq -e 'filter' file.json` so failures produce a non-zero exit.
- Query SQLite: use `sqlite3 -json database.sqlite 'select ...;'` for structured rows.
- Find a TCP listener: use `lsof -nP -iTCP:$PORT -sTCP:LISTEN`.
- Inspect a process: use `ps -o pid,ppid,user,command -p $PID`.

## Command Shapes

### Search

Use JSON when downstream logic needs exact paths, lines, or match spans:

```bash
rg --json 'pattern' path/
```

Use bounded text when a person or agent needs surrounding code:

```bash
rg -n -C 2 'pattern' path/
```

Keep scope explicit (`path/`, file globs, or known directories) when the repo is large.

### Read

```bash
bat --plain --color=never path/to/file
```

For slices, use the local approved reader shape if available:

```bash
sed -n '40,120p' path/to/file
```

### Diff

```bash
git diff --no-ext-diff
git diff --no-ext-diff -- path/to/file
```

Avoid `delta`, color-only formatting, and pager-specific views when the purpose is reasoning about exact changes.

### JSON Validation

```bash
jq -e '.required_key and (.items | type == "array")' file.json
```

Use `jq -e` when success/failure matters. Add `-r` only when intentionally extracting scalar text.

### SQLite

```bash
sqlite3 -json app.db 'select id, status, created_at from jobs limit 20;'
```

Prefer narrow projections and limits. Use JSON output for follow-up filtering or summaries.

### Ports And Processes

Find the listener for a port:

```bash
lsof -nP -iTCP:$PORT -sTCP:LISTEN
```

Inspect the owning process:

```bash
ps -o pid,ppid,user,command -p $PID
```

### HTTP Checks

Use `curl` in a shape that captures status, content type, and body separately:

```bash
tmp_headers="$(mktemp)"
tmp_body="$(mktemp)"
status="$(curl -sS -L -D "$tmp_headers" -o "$tmp_body" -w '%{http_code}' "$URL")"
content_type="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {print $0; exit}' "$tmp_headers")"
test "$status" -ge 200 && test "$status" -lt 300
printf '%s\n' "$content_type"
bat --plain --color=never "$tmp_body"
```

For APIs, validate the body too:

```bash
jq -e '.ok == true' "$tmp_body"
```

Check all three before drawing conclusions: HTTP status, content type, and body shape/content.

## Gotchas

- `grep`, unbounded `rg`, and full-file dumps can flood context. Bound the scope unless full output is necessary.
- Pretty output is for humans at a terminal. Agent reasoning works better with raw diffs, JSON, and plain text.
- HTTP 200 alone is not enough. A proxy, HTML error page, or wrong content type can still mean the request failed for the task.
- `jq` without `-e` can print `false` or `null` and still exit zero; use `jq -e` for validation.

---

## After Execution

Self-assess: Did the selected commands use bounded, parseable, plain output and validate success conditions directly?

Map: 5=used ideal command shapes, 4=minor deviation with no reasoning risk, 3=usable but noisier than needed, 2=missed key validation or used presentation output, 1=command choice likely misled reasoning.

Append to `FEEDBACK.jsonl` and increment `iteration_count` in `CONFIG.yaml`.
