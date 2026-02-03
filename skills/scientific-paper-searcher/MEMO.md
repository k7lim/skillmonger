# Edge Cases & Learnings

## Known Quirks

- **Rate limiting:** Semantic Scholar and PubMed may throttle. Wait and retry.
- **JS rendering:** Some results render via JavaScript; WebFetch may miss them.
- **Preprint→published:** bioRxiv papers may have published versions. Check CrossRef.

## Encountered Issues

| Issue | Resolution |
|-------|------------|
| Special chars in query | URL-encode or remove |
| Very long queries | Truncate to 10 terms |
| Non-English papers | Most DBs prioritize English |

## Feedback Log

(Populated via FEEDBACK.jsonl)
