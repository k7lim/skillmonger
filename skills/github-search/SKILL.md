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

**Hybrid feedback:** Run `scripts/evaluate` on your results JSON, then ask user:

> "Did these results help you decide whether to build or use an existing project?"

Final score = min(script score, user score). Log to `FEEDBACK.jsonl`:

```json
{"ts":"<ISO>","skill":"github-search","version":"<CONFIG.yaml>","prompt":"<request>","outcome":<1-5>,"source":"hybrid","schema_version":1}
```

Increment `iteration_count` in `CONFIG.yaml`.
