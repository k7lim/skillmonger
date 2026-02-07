# Edge Cases & Learnings

## Known Quirks

- **Semantic Scholar Springer gap:** S2 API does NOT return abstracts for Springer-published papers (licensing). Fall back to PubMed `esummary` for those.
- **bioRxiv API is date-browse only:** `api.biorxiv.org/details/` takes date ranges, not keywords. For keyword search on preprints, use Semantic Scholar with `&venue=bioRxiv`.
- **arXiv API is slow:** 5-10s per request is normal. The Atom XML response needs careful parsing — `<summary>` is the abstract, not `<description>`.
- **PubMed two-step flow:** Must call `esearch` first to get PMIDs, then `esummary` with those IDs. Cannot get paper details in a single call.
- **CrossRef polite pool:** Without `mailto` param, responses are much slower and 429s are common. Always include it.

## Rate Limits (actual values from official docs)

| Database | Unauthenticated | Authenticated | On 429 |
|----------|----------------|---------------|--------|
| Semantic Scholar | 5,000 req/5 min (shared) | 1-10 RPS (varies by endpoint) | Exponential backoff: 30s → 60s → 120s |
| PubMed | 3 req/sec | 10 req/sec (free NCBI key) | Wait and retry |
| arXiv | ~1 req/3 sec (be polite) | N/A | Wait 10s |
| bioRxiv | ~1 req/sec | N/A | Retry up to 3× with 30s timeout |
| CrossRef | Slow | ~50 req/sec (polite pool via `mailto`) | Wait 2s |

## Encountered Issues

| Issue | Resolution |
|-------|------------|
| Special chars in query | URL-encode or remove |
| Very long queries | Keep under 200 chars for S2; under 10 terms generally |
| Non-English papers | Most DBs prioritize English |
| JS-rendered search pages | Use structured APIs (not web UIs) — all databases have them |
| Springer papers missing abstracts | Known S2 limitation; fetch from PubMed instead |
| bioRxiv keyword search fails | Use S2 with `&venue=bioRxiv` instead of bioRxiv API |
| PubMed web UI scraping unreliable | Use E-utilities API (`esearch` + `esummary`) — returns clean JSON |
| S2 relevance search >1000 results | Use bulk endpoint (`/paper/search/bulk`) with continuation tokens |
| Preprint→published mapping | bioRxiv `/publisher/` endpoint or CrossRef DOI lookup |

## Feedback Log

(Populated via FEEDBACK.jsonl)
