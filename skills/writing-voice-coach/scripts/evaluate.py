#!/usr/bin/env python3
"""
evaluate.py - Score text for AI slop patterns

Reads text from stdin or file argument.
Outputs JSON with slop analysis and score.

Usage:
    echo "text" | python3 scripts/evaluate.py
    python3 scripts/evaluate.py input.txt
"""
import sys
import json
import re
from collections import defaultdict

# Slop vocabulary - words that scream "AI wrote this"
SLOP_WORDS = {
    'delve', 'crucial', 'pivotal', 'showcase', 'foster', 'landscape',
    'tapestry', 'groundbreaking', 'utilize', 'facilitate', 'leverage',
    'underscore', 'vibrant', 'testament', 'renowned', 'multifaceted',
    'synergy', 'paradigm', 'holistic', 'robust', 'streamline',
    'spearhead', 'cutting-edge', 'game-changer', 'best-in-class'
}

# Hedging words - qualifiers that hide opinion
HEDGING_WORDS = {
    'somewhat', 'arguably', 'perhaps', 'rather', 'quite', 'fairly',
    'relatively', 'potentially', 'seemingly', 'apparently',
    'in certain respects', 'to some extent', 'in some ways'
}

# Over-explanation markers - telling reader how to feel
OVER_EXPLAIN = {
    'remarkably', 'surprisingly', 'crucially', 'importantly', 'notably',
    'interestingly', 'significantly', 'essentially', 'fundamentally'
}

# Bloat phrases - more words than needed
BLOAT_PHRASES = {
    'in order to': 'to',
    'a wide variety of': 'various',
    'it is important to note': '',
    'due to the fact that': 'because',
    'at this point in time': 'now',
    'in the event that': 'if',
    'has the ability to': 'can',
    'is able to': 'can',
    'make a decision': 'decide',
    'take into consideration': 'consider',
    'with regard to': 'about',
    'in spite of the fact that': 'although',
    'for the purpose of': 'to',
    'in the near future': 'soon',
    'at the present time': 'now',
    'on a daily basis': 'daily',
    'a large number of': 'many',
    'the vast majority of': 'most',
    'in close proximity to': 'near'
}

# Vagueness - phrases that could describe anything
VAGUENESS_PHRASES = [
    'significant growth', 'various factors', 'multiple stakeholders',
    'innovative solutions', 'enhanced capabilities', 'improved performance',
    'strategic initiatives', 'key insights', 'best practices',
    'industry-leading', 'cutting-edge solutions', 'world-class'
]

# Copula avoidance - fancy verbs where "is"/"has" works
COPULA_AVOIDANCE = ['serves as', 'stands as', 'boasts', 'features', 'offers']

# Chatbot artifacts - residue from chatbot interaction
CHATBOT_ARTIFACTS = [
    'i hope this helps', 'let me know if', 'here is an overview',
    'here is a summary', 'great question', 'certainly!', 'of course!',
    'absolutely!', "you're absolutely right", 'would you like me to',
    'as of my last', 'based on available information',
    'while specific details are limited'
]


def analyze_text(text: str) -> dict:
    """Analyze text for AI slop patterns."""
    text_lower = text.lower()

    findings = defaultdict(list)

    # Check slop vocabulary
    for word in SLOP_WORDS:
        if re.search(r'\b' + re.escape(word) + r'\b', text_lower):
            findings['slop_vocabulary'].append(word)

    # Check hedging
    for word in HEDGING_WORDS:
        if word in text_lower:
            findings['hedging'].append(word)

    # Check over-explanation
    for word in OVER_EXPLAIN:
        if re.search(r'\b' + re.escape(word) + r'\b', text_lower):
            findings['over_explanation'].append(word)

    # Check bloat phrases
    for phrase in BLOAT_PHRASES:
        if phrase in text_lower:
            findings['bloat'].append(phrase)

    # Check vagueness
    for phrase in VAGUENESS_PHRASES:
        if phrase in text_lower:
            findings['vagueness'].append(phrase)

    # Check copula avoidance
    for phrase in COPULA_AVOIDANCE:
        if phrase in text_lower:
            findings['copula_avoidance'].append(phrase)

    # Check chatbot artifacts
    for phrase in CHATBOT_ARTIFACTS:
        if phrase in text_lower:
            findings['chatbot_artifacts'].append(phrase)

    # Check formatting tells
    em_dash_count = text.count('\u2014') + text.count('--')
    if em_dash_count > 2:
        findings['formatting_tells'].append(f'em_dash_overuse ({em_dash_count})')

    curly_quote_count = sum(text.count(c) for c in '\u201c\u201d\u2018\u2019')
    if curly_quote_count > 0:
        findings['formatting_tells'].append(f'curly_quotes ({curly_quote_count})')

    emoji_pattern = re.compile(
        '[\U0001f300-\U0001f9ff\U0001fa00-\U0001fa6f\U0001fa70-\U0001faff'
        '\u2600-\u26ff\u2700-\u27bf]')
    emojis = emoji_pattern.findall(text)
    if emojis:
        findings['formatting_tells'].append(f'emojis ({len(emojis)})')

    return dict(findings)


def calculate_score(findings: dict, word_count: int) -> int:
    """
    Calculate outcome score 1-5.
    5 = clean text, 1 = heavy slop
    """
    if word_count == 0:
        return 3  # Can't evaluate empty text

    total_issues = sum(len(v) for v in findings.values())

    # Normalize by text length (issues per 100 words)
    density = (total_issues / word_count) * 100

    if density == 0:
        return 5  # Clean
    elif density < 1:
        return 4  # Minor issues
    elif density < 3:
        return 3  # Moderate issues
    elif density < 5:
        return 2  # Significant issues
    else:
        return 1  # Heavy slop


def main():
    # Read input
    if len(sys.argv) > 1 and sys.argv[1] != '-':
        with open(sys.argv[1], 'r') as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    if not text.strip():
        result = {
            "outcome": 3,
            "note": "No text provided",
            "checks": {},
            "source": "script"
        }
        print(json.dumps(result))
        return

    words = re.findall(r'\b\w+\b', text.lower())
    word_count = len(words)

    findings = analyze_text(text)
    score = calculate_score(findings, word_count)

    total_issues = sum(len(v) for v in findings.values())
    categories_hit = len(findings)

    if total_issues == 0:
        note = "Clean - no AI patterns detected"
    else:
        note = f"{total_issues} issues across {categories_hit} categories"

    result = {
        "outcome": score,
        "note": note,
        "checks": {
            "word_count": word_count,
            "slop_count": total_issues,
            "categories": categories_hit,
            "findings": findings
        },
        "source": "script"
    }

    print(json.dumps(result))


if __name__ == "__main__":
    main()
