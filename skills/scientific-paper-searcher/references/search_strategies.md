---
name: search-strategies
description: URL patterns and non-obvious quirks for each database
tags: pubmed, arxiv, biorxiv, semantic-scholar
---

# Database URL Patterns

## PubMed

```
https://pubmed.ncbi.nlm.nih.gov/?term=QUERY&size=20
```

**Date filter:** Append `+AND+2020:2024[pdat]`
**Reviews only:** Append `+AND+review[pt]`

## arXiv

```
https://arxiv.org/search/?query=QUERY&searchtype=all&abstracts=show
```

**Useful categories:** `cs.LG` (ML), `cs.CL` (NLP), `cs.CV` (vision), `q-bio` (quant bio)

## bioRxiv / medRxiv

```
https://www.biorxiv.org/search/QUERY
https://www.medrxiv.org/search/QUERY
```

**Note:** Preprints only. Check if published version exists.

## Semantic Scholar

```
https://www.semanticscholar.org/search?q=QUERY&sort=relevance
```

**Sort by citations:** `&sort=total-citations` (for finding seminal papers)

# Non-Obvious Quirks

- **PubMed rate limits** at ~3 requests/second without API key
- **arXiv search** is slow; results may take 5-10s
- **Semantic Scholar** truncates long queries; keep under 10 terms
- **bioRxiv** search doesn't support Boolean operators well
- URL-encode spaces as `+` or `%20`
