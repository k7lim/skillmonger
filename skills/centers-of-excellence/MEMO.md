# Centers of Excellence - MEMO

> **Loading Trigger:** This file is loaded when the skill encounters issues or requires historical context on edge cases. Do not load proactively.

## Edge Cases Log

### Ambiguous Scope Levels

**Issue:** Some concepts span multiple scope levels simultaneously.

**Example:** "Machine learning" has:
- Country-level leaders: USA, China, UK
- Institution-level leaders: Google DeepMind, OpenAI, Stanford, MIT

**Resolution:**
- Default to institution-level for academic/tech topics
- Ask user to clarify if scope is critical to their use case
- Consider providing both levels if context allows

---

### Multi-Language Regions

**Issue:** Some centers use multiple official languages, making language share estimation complex.

**Examples:**
- Switzerland: German, French, Italian, Romansh
- Belgium: Dutch, French, German
- Singapore: English, Mandarin, Malay, Tamil

**Resolution:**
- Weight by actual research/publication output in each language, not just official status
- For academic topics, English often dominates even in non-English regions
- Check industry-specific publications for vernacular usage

---

### English Dominance Over-Estimation

**Issue:** English knowledge share is frequently overestimated because:
- Researchers default to English for visibility
- Search engines surface English content more readily
- Academic databases skew toward English publications

**Mitigation:**
- Cross-check with regional academic databases
- Consider government/policy documents (often in local language)
- Account for vernacular expertise in cultural topics

---

### Emerging vs. Established Centers

**Issue:** Rankings can be biased toward established Western institutions.

**Examples:**
- China's rapid rise in AI research
- India's growing pharma industry
- African centers for tropical disease research

**Resolution:**
- Use recent data (within 2-3 years) for fast-moving fields
- Explicitly check for emerging centers in non-traditional regions
- Note velocity of growth, not just current position

---

## Learnings (Graduated from Past Iterations)

_Empty - patterns will graduate from iterations_

---

## Known Failure Patterns

_None logged yet_

---

## Iteration Log

| Date | Version | Change Type | Description |
|------|---------|-------------|-------------|
| 2026-01-14 | 1.0.0 | Initial | Skill created with seeded edge cases |

---

## Compaction Queue

_Items pending review for graduation to SKILL.md:_

- (none)
