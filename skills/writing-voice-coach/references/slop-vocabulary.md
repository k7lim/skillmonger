---
name: slop-vocabulary
description: Complete word lists and pattern catalogs for detecting AI-generated writing
tags: slop, vocabulary, patterns, detection, formatting, structure
---

# AI Writing Patterns Reference

## Category 1: Slop Words

Words that almost never appear in natural human writing but saturate AI output.

| Word | Why it's a tell |
|------|-----------------|
| delve | Humans say "dig into" or "explore" |
| utilize | Always means "use" |
| leverage | Corporate-speak for "use" |
| facilitate | "Help" or "enable" |
| underscore | "Show" or "highlight" |
| showcase | "Show" |
| foster | "Encourage" or "build" |
| pivotal | "Key" or "important" |
| crucial | Overused; try "important" or be specific |
| vibrant | Vague positive adjective |
| robust | Meaningless tech buzzword |
| holistic | Almost never needed |
| synergy | Never needed |
| paradigm | Never needed |
| groundbreaking | Show don't tell |
| cutting-edge | Show don't tell |
| game-changer | Show don't tell |
| best-in-class | Marketing speak |
| multifaceted | "Complex" or just describe the facets |
| spearhead | "Lead" |
| streamline | "Simplify" or be specific |
| tapestry | Almost always pretentious |
| landscape | Usually vague ("the tech landscape") |
| testament | "Proof" or "evidence" |
| renowned | Show credentials instead |

## Category 2: Hedging Words

Qualifiers that weaken claims and hide the writer's actual opinion.

| Word/Phrase | The problem |
|-------------|-------------|
| somewhat | Commit to the claim or cut it |
| arguably | Who's arguing? Say it or don't |
| perhaps | Be definite or explain uncertainty |
| rather | Filler |
| quite | Vague intensifier |
| fairly | Vague qualifier |
| relatively | Relative to what? |
| potentially | Everything is potential |
| seemingly | You saw it or you didn't |
| apparently | Cite the source |
| in certain respects | Which respects? |
| to some extent | What extent? |
| in some ways | Which ways? |

## Category 3: Over-Explanation Markers

Words that tell the reader how to feel instead of letting facts speak.

| Word | Why it fails |
|------|--------------|
| remarkably | If it's remarkable, the reader will notice |
| surprisingly | Same—let the surprise land |
| crucially | State the importance, don't label it |
| importantly | Cut it; importance should be evident |
| notably | Usually unnecessary |
| interestingly | If it's interesting, show why |
| significantly | Quantify instead |
| essentially | Often masks vagueness |
| fundamentally | Often empty emphasis |

## Category 4: Bloat Phrases

Multi-word phrases that should be shorter.

| Bloated | Concise |
|---------|---------|
| in order to | to |
| a wide variety of | various / many |
| it is important to note | (cut entirely, or state the thing) |
| serves as | is |
| due to the fact that | because |
| at this point in time | now |
| in the event that | if |
| has the ability to | can |
| is able to | can |
| make a decision | decide |
| take into consideration | consider |
| with regard to | about |
| in spite of the fact that | although |
| for the purpose of | to / for |
| in the near future | soon |
| at the present time | now |
| on a daily basis | daily |
| a large number of | many |
| the vast majority of | most |
| in close proximity to | near |

## Category 5: Vagueness Indicators

Phrases that could describe anything and therefore say nothing.

**Patterns to flag:**
- "significant growth" → What numbers?
- "various factors" → Name them
- "multiple stakeholders" → Who?
- "innovative solutions" → What did it actually do?
- "enhanced capabilities" → Specifics?
- "improved performance" → By how much?
- "strategic initiatives" → What initiatives?
- "key insights" → State the insights
- "best practices" → Which practices?
- "industry-leading" → Prove it

**Test:** If the sentence works for any company/product/situation, it says nothing about this one.

## Category 6: Formatting Tells

Visual patterns AI produces mechanically.

| Pattern | The problem | Fix |
|---------|-------------|-----|
| Em dash overuse | AI uses em dashes to sound punchy. More than one per page is suspicious. | Replace most with commas or periods |
| Emoji decoration | AI decorates headings/bullets with emojis. Unprofessional in formal writing. | Cut all emojis from body text |
| Boldface overuse | AI mechanically bolds key terms. If every other phrase is bold, none stand out. | Bold sparingly or not at all |
| Inline-header lists | Every item starts with **Bold Label:** followed by a sentence. | Rewrite as paragraph or simpler list |
| Curly quotes | ChatGPT outputs " " instead of " ". A tell in typed text. | Replace with straight quotes |

## Category 7: Structural Tells

Patterns in how AI organizes text.

| Pattern | The problem | Fix |
|---------|-------------|-----|
| Rule of three | AI forces ideas into groups of exactly three. Every list, every enumeration. | Vary list lengths—two or five items read more natural |
| Staccato sentences | Four+ short declarative sentences in a row reads robotic. | Connect ideas with "because," "so," "which means" |
| Generic section headings | "Why This Matters," "Key Takeaways," "The Bottom Line," "Challenges and Future Prospects" | Write headings that tell the reader something specific |
| Title Case In Every Heading | AI capitalizes all main words. | Use sentence case: "Strategic negotiations" not "Strategic Negotiations" |

## Category 8: Fake Depth

Constructions that sound profound but say nothing.

| Pattern | Example | Fix |
|---------|---------|-----|
| Negative parallelism | "It's not just about X; it's about Y" | Say what you mean directly |
| False ranges | "From problem-solving to artistic expression" (not a real range) | Drop the construction |
| Synonym cycling | protagonist → main character → central figure → hero | Just repeat the word |
| Significance inflation | "marking a pivotal moment in the evolution of..." | State what happened |
| Superficial -ing endings | "highlighting the importance of," "underscoring the need for" | Cut the -ing clause; give the point its own sentence |

## Category 9: Copula Avoidance

AI avoids "is" and "has" by substituting fancier verbs.

| AI version | Plain version |
|------------|--------------|
| serves as | is |
| stands as | is |
| marks | is |
| represents | is |
| boasts | has |
| features | has |
| offers | has |

**Test:** If "is," "are," or "has" works, use it.

## Category 10: Chatbot Artifacts

Residue from chatbot interaction patterns that leak into output.

| Pattern | Examples |
|---------|---------|
| Preamble | "Here is an overview of..." "Great question!" "Certainly!" |
| Sign-off | "I hope this helps!" "Let me know if you'd like me to expand on any section." |
| Enthusiasm | "Of course!" "You're absolutely right!" "Absolutely!" |
| Knowledge disclaimers | "As of [date]," "While specific details are limited," "Based on available information" |

**Fix:** Strip all of these. Either include the info or omit the claim.

## Category 11: Generic Endings

AI defaults to vague, optimistic conclusions.

**Patterns to flag:**
- "The future looks bright" / "Exciting times lie ahead"
- "...continue their journey toward excellence"
- Formulaic challenges sections: "Despite challenges, X continues to thrive"
- Fortune cookie conclusions that could end any article

**Fix:** End with a concrete fact, not a sentiment.

## Category 12: Conversational Preference

AI defaults to formal, corporate tone when plain language works better.

**Rules:**
- Active voice over passive: "We built this" not "This was constructed by our team"
- Short words over long: "use" not "utilize," "help" not "facilitate"
- First person where it fits: "I think" not "It could be argued"
- If it sounds like a press release or corporate memo, rewrite it plainer

**Orwell's escape hatch:** Break any rule sooner than say anything outright barbarous.
