---
name: scientific-paper-searcher
description: Search PubMed, arXiv, bioRxiv, and Semantic Scholar for research papers. Use when user needs to find scientific literature on a topic.
---

# Scientific Paper Searcher

## When to Use

- User asks to find papers on a scientific topic
- User needs references for research
- User asks "what papers exist about X"

**Don't use for:** Full systematic reviews (use `literature-review` skill), meta-analyses, citation verification only.

## Prerequisites

Run `./scripts/check-prereqs` - needs curl and internet connectivity.

## Workflow

### 1. Clarify Request

Extract: **topic**, **domain** (biomedical/CS/physics/general), **recency** needs, **quantity** (default 10-15).

### 2. Select Databases

| Domain | Primary | Secondary |
|--------|---------|-----------|
| Biomedical | PubMed, bioRxiv | Semantic Scholar |
| CS/AI/ML | arXiv | Semantic Scholar |
| Physics/Math | arXiv | Semantic Scholar |
| Interdisciplinary | Semantic Scholar | PubMed, arXiv |

Search at least 2 databases.

### 3. Search

Use WebFetch with these URL patterns:

```
PubMed:    https://pubmed.ncbi.nlm.nih.gov/?term=QUERY&size=20
arXiv:     https://arxiv.org/search/?query=QUERY&searchtype=all
bioRxiv:   https://www.biorxiv.org/search/QUERY
Semantic:  https://www.semanticscholar.org/search?q=QUERY
```

### 4. Output Format

```markdown
## Search Results: [Topic]

**Databases:** PubMed, arXiv | **Papers found:** X

### Key Papers

#### 1. [Title]
- **Authors:** First A, Second B, et al. (Year)
- **Source:** Journal/arXiv
- **Link:** https://doi.org/...
- **Why relevant:** [1 sentence]

[repeat for top 10-15 papers, ranked by relevance + citations]

### Synthesis
[2-3 sentences on what the literature shows]

### Recommended Reading Order
1. Start with...
```

### 5. Edge Cases

| Issue | Action |
|-------|--------|
| No results | Broaden terms, try synonyms |
| Too many (>100) | Add date filter, narrow terms |
| Database down | Note limitation, use others |
| Wants seminal papers | Sort by citations, no date filter |

## Feedback

Run `echo "$OUTPUT" | ./scripts/evaluate.sh` then ask user: "Were these papers relevant to your research question?"

Log to `FEEDBACK.jsonl`:
```json
{"ts":"<ISO8601>","skill":"scientific-paper-searcher","version":"1.0.0","prompt":"<query>","outcome":<1-5>,"note":"","source":"script|user","schema_version":1}
```
