---
name: github-search
description: Search GitHub for existing projects matching a software idea. Helps with "build or borrow" decisions.
---

# GitHub Search

Find existing projects on GitHub that match a user's software concept. Assess quality and recommend build vs borrow.

## Prerequisites

Run `scripts/check-prereqs`. If `gh-cli` or `gh-auth` missing, install/auth gh CLI first.

## Workflow

### 1. Brainstorm Queries (LLM)

From the user's description, generate 3-5 search strategies using different angles:
- Direct terms (what it's called)
- Problem-focused (what it solves)
- Domain jargon / synonyms
- Related tool names

For each strategy, decide which `scripts/search` flags would narrow results:
- `--language` for language-specific searches
- `--topic` for domain filtering
- `--stars ">50"` to skip toy projects
- `--updated ">2024-01-01"` to find actively maintained repos

### 2. Execute Searches (Script)

```bash
scripts/search "markdown parser" --limit 10 --language python
scripts/search "md to html converter" --limit 10 --sort stars
scripts/search "commonmark" --limit 10 --topic markdown --stars ">20"
```

The script handles correct `--json` field names and outputs valid JSON.

### 3. Filter Results (LLM)

From combined search results, skip: archived repos, trivial forks, off-topic matches, obvious toy projects.

Pick 2-5 candidates worth investigating.

### 4. Deep Dive Top Candidates (Script)

```bash
scripts/deep-dive owner/repo
```

The script returns a combined JSON snapshot with:
- Repo metadata (stars, forks, license, topics, languages, latest release)
- Recent merged PRs (contribution health)
- Recent closed issues (maintainer responsiveness)
- Top forks by stars (succession candidates for stale repos)

### 5. Supplemental Investigation (LLM, as needed)

For specific questions the deep-dive doesn't answer:

```bash
# Is this library actually used? Search for imports in other repos.
gh search code "import toml" --language python --limit 5

# Find related projects from the same author
gh repo list owner --limit 20 --source --json name,description,stargazerCount,pushedAt

# Check if a topic has an established ecosystem
gh search repos --topic toml --sort stars --limit 5 --json fullName,stargazersCount,description
```

### 6. Recommend (LLM)

Present 2-3 top options with:
- Name, stars, last update, license
- Why it fits (features, language, ecosystem)
- Caveats (stale, license, complexity, missing features)

Then recommend: **Borrow** (use existing), **Build** (nothing fits), or **Fork** (good base, needs changes).

## Example

**User:** "Python library to parse TOML"

1. Brainstorm: "toml parser", "toml python", "config file parser toml"
2. Run searches with `scripts/search`
3. Filter to top candidates: tomli, toml, tomllib
4. Deep-dive each with `scripts/deep-dive`
5. Notice uiri/toml is stale — check deep-dive's `top_forks` for active successors

**Response:**
```
### 1. Built-in tomllib (Python 3.11+)
Standard library. No dependency needed.

### 2. hukkin/tomli (554 stars, active, MIT)
Maintained successor for older Python. Same API as tomllib.

### 3. uiri/toml — Abandonware
Original library, stale with ignored issues. Use tomli instead.

**Recommendation:** Borrow — use tomllib (3.11+) or tomli.
```

---

## After Execution

Two things are worth recording about this run: what the evaluator can check,
and what only a person can judge.

**1. Run the evaluator.**

Run this skill's evaluator on the output you just produced:

```bash
scripts/evaluate   # takes the output on stdin, or as its first argument
```

It prints `{"outcome":1-5,"note":"...","checks":{...},"source":"script"}`.

**2. Ask, then judge.**

**Hybrid feedback:** Run `scripts/evaluate` on your results JSON, then ask user:

> "Did these results help you decide whether to build or use an existing project?"

Final score = min(script score, user score).

Score it on the standard scale: 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent.

**3. Record both.** Append one JSON line per source to `FEEDBACK.jsonl` in this
skill directory — the copy you are running from, not the skillmonger repo:

```json
{"ts":"<UTC ISO 8601>","skill":"github-search","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<the evaluator's outcome>,"note":"<the evaluator's note>","checks":<the evaluator's checks object>,"source":"script","session":"<this session's id>","schema_version":1}
{"ts":"<UTC ISO 8601>","skill":"github-search","version":"<skill.version from CONFIG.yaml>","prompt":"<the user's original request>","outcome":<1-5>,"note":"<one line, especially when the outcome is not 4>","source":"user","session":"<this session's id>","schema_version":1}
```

Use `"source":"llm"` on the second line when you judged the run yourself
instead of asking. Drop `session` if you do not know this session's id. Those
lines are the whole record: nothing in `CONFIG.yaml` is edited by a run.
