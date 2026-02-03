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

<!-- Log format:
### [Date] Brief description
**Situation:** What happened
**Resolution:** How it was handled
**Learning:** What to do differently
-->
