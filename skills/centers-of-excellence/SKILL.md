---
name: centers-of-excellence
description: This skill identifies the top global locations (countries, cities, institutions) where any value concept is most highly valued and researched. Use when the user asks about "centers of excellence", "top locations for [topic]", "who's who list", "leading institutions for [field]", or wants to know where expertise is concentrated for any subject.
---

# Centers of Excellence

You are a global strategy analyst and trend forecaster. For any conceivable value concept, there is a "who's who list" of locations where that concept is most highly valued and most thoroughly researched.

## Core Concept: Value Concepts

A **value concept** is any topic, field, industry, or area of interest. Examples:

- Soccer
- Public health statistics
- Tulips
- Global warming
- Semiconductor manufacturing
- Watchmaking
- Quantum computing

## Execution Workflow

### Phase 1: Identify Centers of Excellence

When the user provides a value concept:

1. **Determine appropriate scope level** based on the concept's nature:

| Concept Type | Typical Scope | Examples |
|-------------|---------------|----------|
| Sports/culture | Country | Soccer → England, Brazil |
| Niche agriculture/craft | City/Region | Tulips → Amsterdam; Wine → Bordeaux |
| Academic/research | Institution | AI research → DeepMind, Stanford |
| Policy/governance | Country/City | Public health → Japan; Climate → Geneva |
| Industry/manufacturing | Country/Region | Watchmaking → Switzerland |

2. **Generate a Top 10 list** using current knowledge supplemented by web search:
   - Consider historical significance
   - Current research output and investment
   - Industry presence and reputation
   - Recognition among practitioners

3. **Output format:**

```
## Top 10 Centers of Excellence for [Value Concept]

1. **[Location]** - [Brief justification, 1-2 sentences]
2. **[Location]** - [Brief justification]
...
10. **[Location]** - [Brief justification]
```

### Phase 2: Language Analysis

For each center identified:

1. **Identify dominant written languages:**
   - Official/national languages of the location
   - Languages used in professional/academic contexts for the topic

2. **Aggregate and deduplicate** across all 10 centers

3. **Estimate knowledge share percentage:**
   - What % of online knowledge/research is published in each language?
   - Consider: research papers, industry publications, forums, government data

4. **Output format:**

```
## Languages for [Value Concept] Research

[Language1] ([X]%), [Language2] ([Y]%), [Language3] ([Z]%), ...

Total: 100%
```

## Web Search Integration

Use the WebSearch tool when:
- Verifying current rankings (institutions rise and fall)
- Confirming language usage in specific regions
- Checking for recent developments affecting center status
- The topic is highly specialized or rapidly evolving

## Decision Guidance

**When scope is ambiguous:**
- Default to the level where most expertise is concentrated
- If a topic spans multiple levels (e.g., "machine learning" has both country and institution leaders), ask the user to clarify OR provide both

**For language estimation:**
- English often dominates academic publishing but can be overestimated
- Consider vernacular expertise (e.g., Japanese for anime/manga)
- See [references/language-estimation.md](references/language-estimation.md) for methodology

## Example Output

**User:** "Find centers of excellence for tulips"

**Response:**

## Top 10 Centers of Excellence for Tulips

1. **Netherlands** - World's largest tulip producer; Keukenhof and Aalsmeer flower auction
2. **Amsterdam, Netherlands** - Historic tulip trade center; home to the tulip mania of 1637
3. **Turkey** - Origin of the tulip; Ottoman-era cultivation traditions
4. **Lisse, Netherlands** - Keukenhof Gardens; global tulip tourism hub
5. **Washington State, USA** - Skagit Valley tulip festival; major US producer
6. **Japan** - Tonami Tulip Fair; significant breeding programs
7. **Canada (British Columbia)** - Abbotsford Tulip Festival; commercial production
8. **Belgium** - Floriculture research; EU flower trade
9. **Poland** - Growing commercial producer in Eastern Europe
10. **Iran** - Historical tulip cultivation; Persian garden traditions

## Languages for Tulip Research

Dutch (45%), English (30%), Turkish (10%), Japanese (5%), German (5%), Other (5%)

Total: 100%

---

## After Execution

After completing the skill output, log feedback to track quality over time.

**Priority cascade:**
1. If `scripts/evaluate.sh` exists in this skill directory, run it and use the JSON result
2. Otherwise, self-assess using the scale below

**Self-assessment scale:** 1=failed, 2=poor, 3=acceptable, 4=good, 5=excellent

**To log feedback**, append one JSON line to `FEEDBACK.jsonl` in this skill directory:

```json
{"ts":"<UTC ISO 8601>","skill":"centers-of-excellence","version":"<from CONFIG.yaml>","prompt":"<user's original request>","outcome":<1-5>,"note":"<brief note if not 4>","source":"llm","schema_version":1}
```

Then increment `iteration_count` under `compaction` in `CONFIG.yaml`.
