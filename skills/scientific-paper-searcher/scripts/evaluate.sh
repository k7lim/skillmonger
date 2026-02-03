#!/bin/bash
# evaluate.sh - Evaluate quality of scientific paper search output
# Reads skill output from stdin or a file argument.
# Outputs JSON with outcome (1-5), note, and checks.
#
# Usage:
#   echo "$OUTPUT" | scripts/evaluate.sh
#   scripts/evaluate.sh output.md
set -uo pipefail

# Read input from file arg or stdin
if [ $# -ge 1 ] && [ -f "$1" ]; then
  INPUT=$(cat "$1")
else
  INPUT=$(cat)
fi

# Initialize checks
has_papers=false
has_title=false
has_authors=false
has_year=false
has_doi_or_url=false
has_multiple_sources=false
paper_count=0

# Check for paper entries (looking for markdown headers with paper info)
if echo "$INPUT" | grep -qiE "^#{1,4}.*\. .*|^\*\*Authors:\*\*|^- \*\*Authors:\*\*"; then
  has_papers=true
fi

# Count papers (by counting Author entries or numbered headers)
paper_count=$(echo "$INPUT" | grep -ciE "^\*\*Authors:\*\*|^- \*\*Authors:\*\*|^#{1,4} [0-9]+\." || echo "0")

# Check for required fields
if echo "$INPUT" | grep -qiE "\*\*Authors:\*\*|Authors:"; then
  has_authors=true
fi

if echo "$INPUT" | grep -qiE "\*\*Year:\*\*|Year:|[0-9]{4}"; then
  has_year=true
fi

if echo "$INPUT" | grep -qiE "doi\.org|arxiv\.org/abs|pubmed\.ncbi|semanticscholar\.org|biorxiv\.org|\*\*DOI:\*\*|\*\*URL:\*\*|\*\*arXiv:\*\*"; then
  has_doi_or_url=true
fi

# Check for multiple databases mentioned
db_count=0
echo "$INPUT" | grep -qi "pubmed" && ((db_count++)) || true
echo "$INPUT" | grep -qi "arxiv" && ((db_count++)) || true
echo "$INPUT" | grep -qi "biorxiv\|medrxiv" && ((db_count++)) || true
echo "$INPUT" | grep -qi "semantic scholar" && ((db_count++)) || true

if [ "$db_count" -ge 2 ]; then
  has_multiple_sources=true
fi

# Calculate outcome score
outcome=1
note=""

if [ "$has_papers" = false ] || [ "$paper_count" -eq 0 ]; then
  outcome=1
  note="No papers found in output"
elif [ "$has_authors" = false ] || [ "$has_year" = false ]; then
  outcome=2
  note="Missing required fields (authors or year)"
elif [ "$has_doi_or_url" = false ]; then
  outcome=3
  note="Papers found but no DOIs or URLs"
elif [ "$has_multiple_sources" = false ]; then
  outcome=4
  note="Good results but only one database searched"
else
  outcome=5
  note="Complete results with multiple sources"
fi

# Build checks JSON
checks_json=$(cat << CHECKS
{
  "papers_found": $has_papers,
  "paper_count": $paper_count,
  "has_authors": $has_authors,
  "has_year": $has_year,
  "has_doi_or_url": $has_doi_or_url,
  "databases_searched": $db_count,
  "multiple_sources": $has_multiple_sources
}
CHECKS
)

# Output JSON result
cat << EOF
{"outcome":$outcome,"note":"$note","checks":$checks_json,"source":"script"}
EOF
