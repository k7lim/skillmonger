# Edge Cases and Notes

Log unusual situations encountered during skill execution.

## Known Limitations

### Rate Limits
- Unauthenticated: 10 search requests/minute
- Authenticated: 30 search requests/minute
- If rate limited, wait or reduce query count

### Search Quirks
- GitHub search doesn't support wildcards in queries
- Results are limited to 1000 total (pagination won't go beyond)
- Very new repos may not appear in search immediately
- Archived repos appear in results by default (filter with `archived:false`)

### Language Detection
- GitHub's language detection is automatic and sometimes wrong
- Repos with multiple languages show primary language only
- Some repos have no language detected

## Edge Cases Log

### [2026-02-05] gh CLI field names differ between subcommands
**Situation:** `gh repo view --json stargazersCount` fails — field is `stargazerCount` (singular)
**Resolution:** Fixed SKILL.md; added `references/gh-json-fields.md` with complete field map
**Learning:** Field names are inconsistent across `gh` subcommands. Always check `references/gh-json-fields.md` before constructing `--json` flags. Key trap: `stargazersCount` (search) vs `stargazerCount` (view).
