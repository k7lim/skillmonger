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

Run `./scripts/check-prereqs` - needs curl and internet connectivity.

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

### 3. Search — API Endpoints

**Use WebFetch with these API URLs** (not the web UIs — these return structured data).

#### Semantic Scholar (best default — covers all fields, returns JSON)

```
https://api.semanticscholar.org/graph/v1/paper/search?query=QUERY&fields=title,authors,year,citationCount,abstract,url,externalIds,openAccessPdf,publicationDate&limit=20
```

**Filters** (append as query params):
- `&year=2020-2025` — year range
- `&minCitationCount=10` — minimum citations
- `&fieldsOfStudy=Computer Science` — field filter
- `&openAccessPdf` — only open access papers
- `&publicationTypes=JournalArticle,Review` — type filter

Response is JSON: `{"data": [{"paperId": "...", "title": "...", ...}], "total": N}`.

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

### 4. Output Format

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

### 5. Advanced Search

#### Find a specific paper by title
```
https://api.semanticscholar.org/graph/v1/paper/search/match?query=EXACT+TITLE&fields=title,authors,year,citationCount,url,externalIds
```

#### Get citations of a paper
```
https://api.semanticscholar.org/graph/v1/paper/PAPER_ID/citations?fields=title,authors,year,citationCount&limit=50
```

#### Get references of a paper
```
https://api.semanticscholar.org/graph/v1/paper/PAPER_ID/references?fields=title,authors,year,citationCount&limit=50
```

#### Look up by DOI, arXiv ID, or PMID
```
https://api.semanticscholar.org/graph/v1/paper/DOI:10.1234/example?fields=title,authors,year,citationCount,abstract
https://api.semanticscholar.org/graph/v1/paper/ArXiv:2301.00001?fields=title,authors,year,citationCount,abstract
https://api.semanticscholar.org/graph/v1/paper/PMID:12345678?fields=title,authors,year,citationCount,abstract
```

#### Search by author
```
https://api.semanticscholar.org/graph/v1/author/search?query=AUTHOR+NAME&fields=name,citationCount,hIndex,paperCount
```

### 6. Edge Cases

| Issue | Action |
|-------|--------|
| No results | Broaden terms, try synonyms, try Semantic Scholar (broadest) |
| Too many (>100) | Add year filter, `minCitationCount`, narrow terms |
| Database down | Note limitation, use others |
| Wants seminal papers | Use Semantic Scholar with `&sort=citationCount:desc` (bulk endpoint) or no date filter |
| Rate limited (429) | Wait 30s and retry, or switch databases |
| bioRxiv keyword search | Use Semantic Scholar with `&venue=bioRxiv` instead of bioRxiv API |
| Springer paper missing abstract | Known S2 limitation — fetch from PubMed instead |

## Feedback

1. Run `echo "$OUTPUT" | ./scripts/evaluate.sh` — logs the programmatic score.
2. Ask user: "Were these papers relevant to your research question?" Map answer to 1-5 (`"source":"user"`).
3. Append both entries to `FEEDBACK.jsonl`:
```json
{"ts":"<ISO8601>","skill":"scientific-paper-searcher","version":"2.0.0","prompt":"<query>","outcome":<1-5>,"note":"","source":"script|user","schema_version":1}
```
4. Increment `iteration_count` in `CONFIG.yaml`.
