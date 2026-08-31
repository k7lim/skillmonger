---
status: accepted
date: 2026-08-30
---

# Traces are written into the deployed copy and harvested into the repo

Agents run deployed copies of skills in places that cannot reach this repo
(SRT sandbox homes, Pi, the host tool directories), so the epilogue appends
each trace to the deployed copy's FEEDBACK.jsonl. Until now nothing brought
those traces home and `deploy-skill.sh` deleted the deployed copy before
recopying it, so on 2026-08-30 the repo held 28 traces while the deploy
targets held 373 unique ones, all of them one redeploy from destruction. We
keep the write-in-place epilogue and make the repo the harvest point:
`harvest-feedback.sh` unions every deploy target into `skills/<name>/
FEEDBACK.jsonl`, deduplicating by (skill, ts, content digest) and normalising `source`, and
`deploy-skill.sh` harvests before it removes anything. `iteration_count` is
derived at harvest rather than incremented by the agent.

The dedupe key carries a digest of the normalised trace, not (skill, ts)
alone: the first harvest found 105 traces with no `ts` (they date the run
with `date` or `timestamp`) and 26 distinct runs sharing a date-only `ts`,
which a bare (skill, ts) key would have collapsed to one line each.

## Considered options

- A logger script shipped inside every skill: validates at write time, but
  adds furniture to 53 skills for checks the harvester can do once.
- A central per-machine feedback store: still one store per sandbox home and
  per Pi directory, so still a multi-target harvest.

## Consequences

- The deployed copy is a legitimate write target; "don't edit deployed
  copies" applies to SKILL.md, not FEEDBACK.jsonl.
- Any script that counts or reads traces must read the repo after a harvest,
  never a single deploy target.
