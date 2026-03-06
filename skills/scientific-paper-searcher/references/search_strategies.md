---
name: search-strategies
description: API endpoint reference, query parameters, response formats, and rate limits for each database
tags: pubmed, arxiv, biorxiv, semantic-scholar, crossref
---

# API Reference

## Semantic Scholar Graph API

**Base:** `https://api.semanticscholar.org/graph/v1`

### Paper Search
```
GET /paper/search?query=QUERY&fields=FIELDS&limit=20
```

| Param | Example | Notes |
|-------|---------|-------|
| `query` | `transformer+attention` | URL-encode spaces as `+` |
| `fields` | `title,authors,year,citationCount,abstract,url,externalIds,openAccessPdf,publicationDate` | Comma-separated |
| `limit` | `20` | 1–100 |
| `offset` | `0` | Max offset+limit = 1000 |
| `year` | `2020-2025` | Range or single year |
| `minCitationCount` | `10` | Integer |
| `fieldsOfStudy` | `Computer Science` | Single field |
| `openAccessPdf` | (no value) | Presence = filter |
| `publicationTypes` | `JournalArticle,Review,Conference` | Comma-separated |
| `publicationDateOrYear` | `2020-01-01:2025-12-31` | Colon-separated range |
| `venue` | `Nature,bioRxiv` | Comma-separated |

**Response:** `{"total": N, "offset": 0, "next": 20, "data": [{paperId, title, authors: [{authorId, name}], year, citationCount, abstract, url, externalIds: {DOI, ArXiv, PubMed}, openAccessPdf: {url, status}, publicationDate}]}`

### Bulk Search (for seminal/highly-cited papers)
```
GET /paper/search/bulk?query=QUERY&fields=FIELDS&sort=citationCount:desc
```
- Returns up to 1000 per request, 10M total via continuation tokens
- Supports `sort` param: `citationCount:desc`, `publicationDate:desc`, `paperId`

### Paper Lookup (by ID)
```
GET /paper/{id}?fields=FIELDS
```
Accepts: `DOI:10.1234/...`, `ArXiv:2301.00001`, `PMID:12345678`, `CorpusId:12345`, S2 paper ID, or full URL.

### Citations & References
```
GET /paper/{id}/citations?fields=title,authors,year,citationCount&limit=50
GET /paper/{id}/references?fields=title,authors,year,citationCount&limit=50
```

### Title Match (find exact paper)
```
GET /paper/search/match?query=EXACT+TITLE&fields=FIELDS
```
**Warning:** Returns 404 on non-exact titles. Use `/paper/search` for fuzzy matching instead.

### Author Search
```
GET /author/search?query=NAME&fields=name,citationCount,hIndex,paperCount
GET /author/{id}/papers?fields=title,year,citationCount&limit=100
```

### Rate Limits
- **Unauthenticated:** 5,000 requests per 5 minutes (shared pool) — but in practice, the shared pool 429s after just 2-3 rapid requests. Treat the real limit as ~1 request per 3 seconds.
- **Authenticated (with API key):** 1 RPS for search/batch/recommendations; 10 RPS for other endpoints
- **Auth header:** `x-api-key: YOUR_KEY` (env var: `SEMANTIC_SCHOLAR_API_KEY`)
- **On 429:** Exponential backoff — wait 30s, retry; wait 60s, retry; then stop and switch databases
- **Prevention:** Always space requests by 3s (unauth) or 1s (auth). Query other databases first.
- **Gotcha:** Springer abstracts are NOT returned (licensing restriction)
- **Tier note:** Unauthenticated pool is shared across all users. In practice, 2-3 rapid requests trigger 429. Use `./scripts/search-s2` which enforces delays automatically.

---

## PubMed E-utilities API

**Base:** `https://eutils.ncbi.nlm.nih.gov/entrez/eutils`

### Step 1: Search (get PMIDs)
```
GET /esearch.fcgi?db=pubmed&term=QUERY&retmax=20&retmode=json
```

| Param | Example | Notes |
|-------|---------|-------|
| `term` | `CRISPR+gene+editing` | URL-encode, use `+` for spaces |
| `retmax` | `20` | Max results |
| `retmode` | `json` | Also supports `xml` |
| `mindate` | `2020` | Requires `datetype` |
| `maxdate` | `2025` | Requires `datetype` |
| `datetype` | `pdat` | Publication date |

**PubMed search modifiers** (append to `term`):
- `+AND+review[pt]` — reviews only
- `+AND+2020:2025[pdat]` — date range (alternative to mindate/maxdate)
- `+AND+humans[mesh]` — MeSH term filter
- `+AND+free+full+text[filter]` — open access only

**Response:**
```json
{"esearchresult": {"count": "1234", "idlist": ["12345", "67890"]}}
```

### Step 2: Fetch Details
```
GET /esummary.fcgi?db=pubmed&id=12345,67890&retmode=json
```

**Response:** `{"result": {"12345": {uid, title, authors: [{name, authtype}], pubdate, source, elocationid, fulljournalname}}}`

Paper URL: `https://pubmed.ncbi.nlm.nih.gov/{PMID}/`

### Rate Limits
- **Without API key:** 3 requests/second
- **With API key:** 10 requests/second (register at NCBI for free)
- **API key param:** `&api_key=YOUR_KEY`

---

## arXiv API

**Base:** `https://export.arxiv.org/api`

### Search
```
GET /query?search_query=all:QUERY&max_results=20&sortBy=submittedDate&sortOrder=descending
```

| Param | Example | Notes |
|-------|---------|-------|
| `search_query` | `all:transformer+attention` | Prefix: `all:`, `ti:`, `au:`, `abs:`, `cat:` |
| `max_results` | `20` | Max 300 |
| `start` | `0` | Pagination offset |
| `sortBy` | `submittedDate` | Also: `relevance`, `lastUpdatedDate` |
| `sortOrder` | `descending` | Or `ascending` |

**Category codes:** `cs.LG` (ML), `cs.CL` (NLP), `cs.CV` (vision), `cs.AI` (AI), `q-bio` (quant bio), `stat.ML` (stats/ML), `physics`, `math`

**Combine query + category:** `search_query=all:QUERY+AND+cat:cs.LG`

**Response:** Atom XML feed. Each `<entry>` contains:
- `<title>` — paper title
- `<summary>` — abstract
- `<author><name>` — author names
- `<published>` — date (ISO 8601)
- `<link href="..." rel="alternate">` — abstract page URL
- `<link href="..." title="pdf">` — PDF URL
- `<arxiv:doi>` — DOI if available
- `<arxiv:primary_category term="cs.LG">` — primary category

Paper URL: `https://arxiv.org/abs/{ID}`
PDF URL: `https://arxiv.org/pdf/{ID}.pdf`

### Rate Limits
- No official limit but be polite — max 1 request/3 seconds
- Responses can be slow (5-10s)

---

## bioRxiv / medRxiv API

**Base:** `https://api.biorxiv.org`

### Browse by Date Range
```
GET /details/biorxiv/{start_date}/{end_date}/{cursor}
GET /details/medrxiv/{start_date}/{end_date}/{cursor}
```

| Param | Example | Notes |
|-------|---------|-------|
| `start_date` | `2024-01-01` | YYYY-MM-DD |
| `end_date` | `2025-12-31` | YYYY-MM-DD |
| `cursor` | `0` | Pagination, increments by 100 |

**Response:** `{"collection": [{doi, title, authors: "Smith, A.; Jones, B.", abstract, date, category, version}]}`

Paper URL: `https://www.biorxiv.org/content/{doi}v{version}`
PDF URL: `https://www.biorxiv.org/content/{doi}v{version}.full.pdf`

**Important:** This is a date-browse API, not keyword search. For keyword search on preprints, use Semantic Scholar with `&venue=bioRxiv` or `&venue=medRxiv`.

### Published Versions
```
GET /publisher/biorxiv/{start_date}/{end_date}/{cursor}
```
Returns preprints that have been published, with the published DOI.

### Rate Limits
- No documented limit, but keep under 1 request/second
- 30s request timeout
- Paginate: if `collection` has 100 items, there are more — increment cursor by 100

---

## CrossRef API

**Base:** `https://api.crossref.org`

### Search
```
GET /works?query=QUERY&rows=20&sort=relevance&order=desc&mailto=user@example.com
```

| Param | Example | Notes |
|-------|---------|-------|
| `query` | `CRISPR+gene+editing` | Keyword search |
| `rows` | `20` | Max 1000 |
| `sort` | `relevance` | Also: `published`, `is-referenced-by-count` |
| `order` | `desc` | Or `asc` |
| `filter` | `type:journal-article,from-pub-date:2020` | Comma-separated filters |
| `mailto` | `user@example.com` | **Required** for polite pool |

**Common filters:**
- `type:journal-article` or `type:book-chapter`
- `from-pub-date:2020,until-pub-date:2025`
- `has-abstract:true`
- `has-full-text:true`

**Response:** `{"message": {"total-results": N, "items": [{DOI, title: [...], author: [{given, family}], published: {date-parts: [[Y,M,D]]}, container-title: [...], is-referenced-by-count, URL}]}}`

### DOI Lookup
```
GET /works/{DOI}
```

### Rate Limits
- **Polite pool** (with `mailto`): ~50 requests/second
- **Without `mailto`**: Much slower, may get 429s
- **On 429:** Wait 2 seconds and retry

