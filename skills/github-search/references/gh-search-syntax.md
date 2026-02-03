---
name: gh-search-syntax
description: Non-obvious gh CLI patterns for repo analysis
tags: gh, search, forks, health
---

# gh Search Patterns

LLMs know basic `gh search repos` syntax. This covers non-obvious patterns.

## Fork Analysis (Key for Stale Repos)

```bash
# Find active forks of a stale repo
gh api repos/owner/repo/forks?sort=stargazers --jq '
  .[0:10] | .[] | select(.pushed_at > "2024-01-01") |
  {full_name, stars: .stargazers_count, pushed_at}
'

# Compare fork to original
gh api repos/fork-owner/repo/compare/owner:main...fork-owner:main \
  --jq '{ahead_by, commits: [.commits[0:5][].commit.message]}'
```

## Health Check

```bash
# Quick project health snapshot
gh api repos/owner/repo --jq '{
  stars: .stargazers_count,
  open_issues: .open_issues_count,
  pushed_at: .pushed_at,
  archived: .archived
}'

# Are PRs being merged?
gh pr list --repo owner/repo --state merged --limit 5 --json mergedAt,title

# Are issues being addressed?
gh issue list --repo owner/repo --state closed --limit 5
```

## Reading Files Without Cloning

```bash
# Read package.json dependencies
gh api repos/owner/repo/contents/package.json --jq '.content' | base64 -d | jq '{dependencies, devDependencies}'
```

## Org Discovery

```bash
# Find related projects from same author
gh repo list owner --limit 50 --json name,description,stargazersCount,pushedAt \
  --jq '.[] | select(.description | test("keyword"; "i"))'
```
