---
name: scientific-paper-searcher
description: Search PubMed, arXiv, bioRxiv, Semantic Scholar, and CrossRef for research papers using their structured APIs. Use when user needs to find scientific literature on a topic.
---

# Scientific Paper Searcher

## When to Use

- User asks to find papers on a scientific topic
- User needs references for research
- User asks "what papers exist about X"
- User wants citation counts, author info, or related papers

**Don't use for:** Full systematic reviews (use `literature-review` skill), meta-analyses, citation verification only.

## Prerequisites

Run `./scripts/check-prereqs` - needs curl and internet connectivity. **If check-prereqs reports "ready": true, all databases (including arXiv) are available. Do not skip arXiv or any database based on your own dependency checks.**

## Workflow

### 1. Clarify Request

Extract: **topic**, **domain** (biomedical/CS/physics/general), **recency** needs, **quantity** (default 10-15).

Optional filters to ask about: year range, minimum citation count, open access only, publication type.

### 2. Select Databases

| Domain | Primary | Secondary |
|--------|---------|-----------|
| Biomedical | PubMed | bioRxiv, Semantic Scholar |
| CS/AI/ML | Semantic Scholar, arXiv | CrossRef |
| Physics/Math | arXiv | Semantic Scholar |
| Interdisciplinary | Semantic Scholar | PubMed, arXiv |
| Finding published versions | CrossRef | Semantic Scholar |

Search at least 2 databases. Always include Semantic Scholar for citation counts.

### 3. Rate Limit Policy

**NEVER fire parallel API requests. Call scripts sequentially, one database at a time.**

Semantic Scholar is the most 429-prone API. Follow these rules for ALL databases.

**Request spacing** (mandatory — enforced by scripts, manual if using WebFetch):

| Database | Min delay between requests | Notes |
|----------|---------------------------|-------|
| Semantic Scholar | **3 seconds** (unauth), **1 second** (with key) | Most critical — shared pool 429s fast |
| PubMed | 400ms (unauth), 100ms (with key) | 2-step search counts as 2 requests |
| arXiv | 3 seconds | Slow API, be polite |
| bioRxiv | 1 second | Undocumented limits |
| CrossRef | 200ms (with `mailto`) | Include `mailto` always |

**Semantic Scholar API key** (configured):
- Env var `SEMANTIC_SCHOLAR_API_KEY` is set — all `./scripts/*-s2` scripts use it automatically
- Without a key, the shared unauthenticated pool is aggressive — expect 429s on >2-3 rapid requests
- **All S2 requests share a global rate limiter** (`/tmp/.s2-rate-limit`) — always use scripts, never raw WebFetch for S2

**Search order to minimize 429 risk:**
1. Query PubMed or arXiv first (more generous limits)
2. Query Semantic Scholar last, only for citation counts or fields not covered above
3. If Semantic Scholar 429s, use CrossRef as citation count fallback

**429 recovery (exponential backoff):**
1. First 429: wait **30 seconds**, retry once
2. Second 429: wait **60 seconds**, retry once
3. Third 429: **stop** — switch to another database, do NOT keep retrying
4. Tell the user which database was unavailable

**Reduce request volume:**
- Request only the fields you need (smaller `fields=` param = faster response)
- Use `limit=20` not `limit=100` unless the user asked for more
- Combine PubMed esummary IDs into one call (comma-separated) rather than individual lookups
- For Semantic Scholar, `search-s2` defaults to the `/paper/search/bulk` endpoint sorted by `citationCount:desc` — ideal for "get a sense of a topic" since it surfaces the most-cited papers first. Use `--sort relevance` only when recency/text-match ranking matters more than impact.

### 3.5. Using Search Scripts

**Prefer `./scripts/search-*` via Bash over raw WebFetch for API calls.** The scripts handle rate limiting, URL encoding, 429 retry, and output normalization automatically.

```bash
# Individual databases
./scripts/search-pubmed "reading motivation adolescents" --year-min 2020 --limit 15
./scripts/search-crossref "reading for pleasure teenagers" --year-min 2019
./scripts/search-arxiv "transformer attention mechanism" --category cs.LG
./scripts/search-s2 "adolescent reading engagement" --min-citations 10
./scripts/search-s2 "adolescent reading engagement" --sort relevance  # recency-mixed ranker
./scripts/search-s2 "adolescent reading engagement" --sort date       # newest first

# Single paper lookup (by DOI, arXiv ID, PMID, or S2 ID)
./scripts/lookup-s2 "DOI:10.1038/s41586-021-03819-2"
./scripts/lookup-s2 "ArXiv:2301.00001" --fields title,citationCount
./scripts/lookup-s2 "DOI:10.1234/example" --citations --limit 50
./scripts/lookup-s2 "DOI:10.1234/example" --references

# Orchestrator (searches multiple, deduplicates by DOI)
./scripts/search "reading motivation" --databases pubmed,crossref --year-min 2020
```

All scripts output the same normalized JSON schema:
```json
{"database": "...", "query": "...", "total": N, "results": [{title, authors, year, citations, doi, url, open_access_url, abstract, source_id}], "error": null}
```

**When to still use WebFetch:** Web search results or non-S2 API calls only. **Never use WebFetch for Semantic Scholar** — it bypasses the global rate limiter.

**Discover + enrich pattern:** Search PubMed/CrossRef/arXiv first (generous limits), then use `./scripts/lookup-s2` for citation count enrichment (e.g., `./scripts/lookup-s2 "DOI:10.xxx" --fields title,citationCount`). The lookup script shares the global 1 RPS rate limiter with `search-s2`.

### 4. Search — API Endpoints

**Use `./scripts/search-*` via Bash (preferred) or WebFetch with these API URLs** (not the web UIs — these return structured data).

#### Semantic Scholar (best default — covers all fields, returns JSON)

Two endpoints; `search-s2` picks based on `--sort`:

**Bulk (default — `--sort citations` or `--sort date`):** stricter matching, supports sorting by `citationCount` or `publicationDate`, returns up to 1000/page.
```
https://api.semanticscholar.org/graph/v1/paper/search/bulk?query=QUERY&fields=...&sort=citationCount:desc
```

**Relevance (`--sort relevance`):** S2's custom-trained ranker, broader recall, supports `limit`.
```
https://api.semanticscholar.org/graph/v1/paper/search?query=QUERY&fields=...&limit=20
```

**Filters** (work on both endpoints — append as query params):
- `&year=2020-2025` — year range
- `&minCitationCount=10` — minimum citations
- `&fieldsOfStudy=Computer Science` — field filter
- `&openAccessPdf` — only open access papers
- `&publicationTypes=JournalArticle,Review` — type filter

Response is JSON: `{"data": [{"paperId": "...", "title": "...", ...}], "total": N}` (bulk also returns `"token"` for pagination — `search-s2` ignores this and takes first `limit`).

#### PubMed (two-step: esearch → esummary)

**Step 1 — Get PMIDs:**
```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=QUERY&retmax=20&retmode=json
```

Response JSON: `{"esearchresult": {"idlist": ["12345", "67890", ...]}}`.

**Step 2 — Get paper details:**
```
https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&id=ID1,ID2,ID3&retmode=json
```

Response JSON: `{"result": {"12345": {"title": "...", "authors": [...], "pubdate": "...", ...}}}`.

**Date filter:** Append `&mindate=2020&maxdate=2025&datetype=pdat` to esearch.
**Reviews only:** Append `+AND+review[pt]` to the term.

#### arXiv (Atom API)

```
https://export.arxiv.org/api/query?search_query=all:QUERY&max_results=20&sortBy=submittedDate&sortOrder=descending
```

Response is Atom XML with `<entry>` elements containing `<title>`, `<author>`, `<summary>`, `<link>`, `<published>`.

**Category filter:** Use `cat:cs.LG` (ML), `cat:cs.CL` (NLP), `cat:cs.CV` (vision), `cat:q-bio` (quant bio).
**Combine:** `search_query=all:QUERY+AND+cat:cs.LG`

#### bioRxiv / medRxiv (JSON API — date-range based)

```
https://api.biorxiv.org/details/biorxiv/2024-01-01/2025-12-31/0?format=json
```

Response JSON: `{"collection": [{"doi": "...", "title": "...", "authors": "...", "abstract": "...", "date": "...", ...}]}`.

**Note:** This API browses by date range, not keyword. To keyword-search bioRxiv, use Semantic Scholar with `&venue=bioRxiv` or use the search URL as fallback:
```
https://www.biorxiv.org/search/QUERY
```

For medRxiv, replace `biorxiv` with `medrxiv` in the API path.

#### CrossRef (DOI lookups & published paper search)

```
https://api.crossref.org/works?query=QUERY&rows=20&sort=relevance&order=desc&mailto=user@example.com
```

Response JSON: `{"message": {"items": [{"DOI": "...", "title": [...], "author": [...], ...}]}}`.

**Filter by type:** `&filter=type:journal-article`
**Date filter:** `&filter=from-pub-date:2020,until-pub-date:2025`
**Include `mailto`** for polite pool (faster responses).

### 5. Output Format

```markdown
## Search Results: [Topic]

**Databases:** Semantic Scholar, PubMed | **Papers found:** X

### Key Papers

#### 1. [Title]
- **Authors:** First A, Second B, et al. (Year)
- **Citations:** N
- **Source:** Journal/arXiv/bioRxiv
- **Link:** https://doi.org/...
- **Open access:** Yes/No
- **Why relevant:** [1 sentence]

[repeat for top 10-15 papers, ranked by relevance + citations]

### Synthesis
[2-3 sentences on what the literature shows]

### Recommended Reading Order
1. Start with...
```

### 6. Advanced Search

**All S2 advanced lookups go through `./scripts/lookup-s2`** (shares the global rate limiter).

#### Find a specific paper by title
```bash
./scripts/lookup-s2 "Attention Is All You Need" --match
```

#### Get citations of a paper
```bash
./scripts/lookup-s2 "DOI:10.1234/example" --citations --limit 50
```

#### Get references of a paper
```bash
./scripts/lookup-s2 "DOI:10.1234/example" --references --limit 50
```

#### Look up by DOI, arXiv ID, or PMID
```bash
./scripts/lookup-s2 "DOI:10.1234/example"
./scripts/lookup-s2 "ArXiv:2301.00001"
./scripts/lookup-s2 "PMID:12345678"
```

#### Search by author
```bash
./scripts/lookup-s2 "Author Name" --author
```

### 7. Edge Cases

| Issue | Action |
|-------|--------|
| No results | Broaden terms, try synonyms, try Semantic Scholar (broadest) |
| Too many (>100) | Add year filter, `minCitationCount`, narrow terms |
| Database down | Note limitation, use others |
| Wants seminal papers | `search-s2` already sorts by citations by default — just remove year filter or widen it |
| Rate limited (429) | Follow Section 3 backoff: 30s → 60s → stop and switch databases |
| bioRxiv keyword search | Use Semantic Scholar with `&venue=bioRxiv` instead of bioRxiv API |
| Springer paper missing abstract | Known S2 limitation — fetch from PubMed instead |
| PDF URLs | WebFetch cannot parse PDFs. Use API metadata only |
| Publisher paywalls (403/303) | Cannot scrape publisher sites. Use API data |
| `/paper/search/match` 404s | Returns 404 on non-exact titles. Use `/paper/search` for fuzzy |

## Feedback

1. Run `echo "$OUTPUT" | ./scripts/evaluate.sh` — logs the programmatic score.
2. Ask user: "Were these papers relevant to your research question?" Map answer to 1-5 (`"source":"user"`).
3. Append both entries to `FEEDBACK.jsonl`:
```json
{"ts":"<ISO8601>","skill":"scientific-paper-searcher","version":"2.0.0","prompt":"<query>","outcome":<1-5>,"note":"","source":"script|user","schema_version":1}
```
4. Increment `iteration_count` in `CONFIG.yaml`.
