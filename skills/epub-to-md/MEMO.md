# Edge Cases and Notes

This file tracks edge cases, gotchas, and learnings from using the epub-to-md skill.

## Known Issues

### Images
- Remote images are preserved as URLs by default; use `--localize` to download them
- `--localize` requires Node.js 18+ due to fetch API usage
- Some EPUBs have broken image references that epub2md cannot fix

### Character Encoding
- Chinese/English mixed text may have spacing issues; use `-M` flag for autocorrection
- Some older EPUBs use non-standard encodings that may cause issues

### Large Files
- Very large EPUBs (>100MB) may be slow to process
- Batch processing with wildcards runs sequentially

## Learnings

<!-- Add notes from actual usage here -->
