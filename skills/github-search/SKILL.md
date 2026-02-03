---
name: github-search
description: Search GitHub for existing projects matching a software idea. Helps with "build or borrow" decisions.
---

# GitHub Search

Find existing projects on GitHub that match a user's software concept. Assess quality and recommend build vs borrow.

## Prerequisites

Run `scripts/check-prereqs`. If `gh-cli` or `gh-auth` missing, install/auth gh CLI first.

## Workflow

### 1. Generate Diverse Queries

From the user's description, create 3-5 search queries using different angles (direct terms, problem-focused, domain jargon, synonyms).

```bash
gh search repos "markdown parser" --limit 10 --sort stars --json name,owner,description,stargazersCount,updatedAt,openIssues
```

Include `updatedAt` and `openIssues` for quality evaluation.

### 2. Filter Results

**Stable vs Abandonware:**
- Stable: Old but low open issues — mature, works fine
- Abandonware: Old AND many ignored issues (30+) — avoid

Skip: abandonware, trivial forks, off-topic matches.

### 3. Deep Dive Top Candidates

```bash
gh repo view owner/repo --json name,description,stargazersCount,forksCount,openIssues,pushedAt,licenseInfo
gh pr list --repo owner/repo --state merged --limit 5  # PRs being merged = healthy
```

**For stale repos, check for active forks** — see `references/gh-search-syntax.md` for fork analysis patterns.

### 4. Recommend

Present 2-3 top options with:
- Name, stars, last update
- Why it fits
- Caveats (license, complexity)

Then: **Borrow** (use existing), **Build** (nothing fits), or **Fork** (good base, needs changes).

## Example

**User:** "Python library to parse TOML"

Search finds `uiri/toml` (600 stars, 2yr stale, 45 open issues). Check forks:

```bash
gh api repos/uiri/toml/forks --jq 'sort_by(.pushed_at) | reverse | .[0:5] | .[] | {full_name, pushed_at, stargazers_count}'
```

**Response:**
```
### 1. Built-in tomllib (Python 3.11+)
Standard library. No dependency needed.

### 2. hukkin/tomli (1.2k stars, active)
Maintained successor for older Python. Same API as tomllib.

### 3. uiri/toml — ⚠️ Abandonware
Original library, but stale with 45 ignored issues. Use tomli instead.

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
