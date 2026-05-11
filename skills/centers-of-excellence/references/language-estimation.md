# Language Knowledge Share Estimation

This reference provides methodology for estimating the percentage of online knowledge published in each language for a given value concept.

## Estimation Framework

### Factors to Consider

1. **Academic Publications**
   - Research papers and journal articles
   - University programs and their teaching languages
   - Conference proceedings
   - Preprint servers (arXiv, SSRN, etc.)

2. **Industry Documentation**
   - Technical standards and specifications
   - Trade publications and industry journals
   - Professional association materials
   - Patents and patent applications

3. **Online Presence**
   - Wikipedia article depth and quality
   - Wikipedia article-count scale priors, adjusted for bot-heavy editions
   - Stack Overflow / specialized forums
   - Social media discourse
   - YouTube and video content

4. **Government and NGO Sources**
   - Official reports and statistics
   - Policy documents
   - Regulatory filings
   - International organization publications

## Baseline Estimates (General Knowledge)

Start with these baselines and adjust based on the specific topic:

| Language | Global Share | Notes |
|----------|-------------|-------|
| English | 55-60% | Dominates academic, technical, business |
| Chinese (Mandarin) | 10-15% | Growing rapidly; strong in tech, manufacturing |
| Spanish | 5-8% | Strong in Latin America; arts, culture |
| German | 4-6% | Engineering, philosophy, sciences |
| French | 3-5% | Diplomacy, fashion, gastronomy |
| Japanese | 3-5% | Technology, pop culture, manufacturing |
| Portuguese | 2-4% | Brazil's growing influence |
| Russian | 2-4% | Sciences, aerospace, literature |
| Arabic | 1-3% | Religion, regional policy |
| Korean | 1-3% | Technology, entertainment |
| Others | Variable | Topic-dependent |

For a rough language-scale prior, consult [wikipedia-language-article-counts.md](wikipedia-language-article-counts.md). Treat that file as a visibility prior only. It should never override center-specific language use, publication language, or topic-specific expertise.

## Adjustment Factors

### By Topic Type

**STEM / Technical:**
- English share often 70-80%
- Chinese rapidly increasing
- German strong in engineering

**Arts / Culture:**
- Local languages much higher
- English share drops to 30-40%
- Regional languages critical

**Policy / Governance:**
- UN languages more balanced
- Regional policy in local language
- International policy skews English

**Sports:**
- Depends heavily on sport origin
- Soccer: Spanish, Portuguese, German significant
- Cricket: English, Hindi dominant

### By Region Concentration

If all top centers are in one language region:
- That language may represent 60-80%
- Example: Anime → Japanese 60%+
- Example: K-pop → Korean 50%+

### By Recency

For rapidly evolving fields:
- Check publication dates
- Recent Chinese output growing fast in AI, biotech
- Historical knowledge may skew differently than current

### By Wikipedia Article Count

Use article counts to keep estimates grounded in the relative online footprint of major language communities, especially when the selected centers span many regions. Do not convert article-count percentages directly into knowledge-share percentages.

Recommended adjustment:

- Use article counts as a weak prior for broad web visibility.
- Apply a strong topic/center relevance multiplier before assigning share.
- Downweight known bot-heavy editions unless they are locally relevant.
- Collapse long-tail languages below 1% into `Other`.

## Output Requirements

1. **Sum to 100%** - All percentages must total exactly 100%
2. **Minimum threshold: 1%** - Omit languages below 1%
3. **Round to whole numbers** - No decimals
4. **Order descending** - Highest percentage first
5. **Include "Other" category** - For small contributors

## Example Calculation

**Topic: Renewable Energy**

1. Identify top centers: Germany, China, USA, Denmark, Japan, UK...
2. Map to languages: German, Chinese, English, Danish, Japanese...
3. Weight by publication output:
   - Academic papers: ~60% English
   - Industry reports: Mixed
   - Government policy: Local languages
4. Aggregate and round:

**Result:** English (55%), Chinese (20%), German (10%), Japanese (5%), Danish (3%), Other (7%)
