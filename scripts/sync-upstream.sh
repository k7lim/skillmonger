#!/bin/bash
# sync-upstream.sh - Pull upstream changes into an adopted skill
#
# The zone policy is what makes this safe:
#   verbatim  provably unmodified by us -> fast-forwarded automatically
#   adapted   we rewrote it             -> never touched; you get a diff to read
#   ours      no upstream counterpart   -> ignored
#
# Re-pinning is the claim "this skill is reconciled with upstream at REF". The
# script only makes that claim when it is true: if an adapted file changed
# upstream, the pin stays put until you review and pass --accept.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=lib/skill-name.sh
. "$SCRIPT_DIR/lib/skill-name.sh"

usage() {
  cat << EOF
Usage: $(basename "$0") <skill> [options]

Syncs one adopted skill to a newer upstream ref.

Options:
  --to <ref>    Target tag/branch/SHA. Default: latest upstream release tag
  --dry-run     Show what would change; write nothing
  --accept      Re-pin even though adapted files changed upstream, because you
                have reviewed them. Records the review in SOURCE.md.
  --help        Show this help

Examples:
  $(basename "$0") grill-me --dry-run
  $(basename "$0") grill-me --to v1.2.3
  $(basename "$0") tdd --to v1.2.3 --accept
EOF
}

SKILL=""; TO=""; DRY_RUN=false; ACCEPT=false
while [ $# -gt 0 ]; do
  case "$1" in
    --to) TO="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --accept) ACCEPT=true; shift ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) SKILL="$1"; shift ;;
  esac
done

[ -n "$SKILL" ] || { usage >&2; exit 1; }
skill_name_require "$SKILL"
SKILL_DIR="$PROJECT_ROOT/skills/$SKILL"
[ -d "$SKILL_DIR" ] || { echo "ERROR: no such skill: $SKILL" >&2; exit 1; }

PYTHONPATH="$SCRIPT_DIR/lib" python3 - \
  "$PROJECT_ROOT" "$SKILL" "$TO" "$DRY_RUN" "$ACCEPT" << 'PY'
import datetime
import subprocess
import sys
from pathlib import Path

import upstream as up

root = Path(sys.argv[1])
name = sys.argv[2]
target_ref = sys.argv[3]
dry_run = sys.argv[4] == "true"
accept = sys.argv[5] == "true"

skill_dir = root / "skills" / name
block = up.upstream_block(skill_dir)
if not block:
    sys.exit(f"error: {name} has no CONFIG.yaml upstream: block — not an adopted skill")

status = str(block.get("status", "tracked"))
if status == "orphaned":
    sys.exit(f"{name} is orphaned upstream — deleted after "
             f"{block.get('last_seen_ref', '?')}. There is nothing to sync.")

if isinstance(block.get("path_map"), dict):
    sys.exit(
        f"error: {name} declares a path_map, which this script does not follow yet.\n"
        f"       Applying upstream files without translating paths would write them\n"
        f"       to the wrong place. Sync it by hand — see skills/{name}/SOURCE.md."
    )

vendor = root / str(block.get("vendor", ""))
if not (vendor / ".git").is_dir():
    sys.exit(f"error: vendor checkout missing: {block.get('vendor')}")

pinned = str(block["commit"])
old_path = str(block["path"]).rstrip("/")
new_path = str(block.get("head_path") or old_path).rstrip("/")


def git(*args, check=True):
    result = subprocess.run(
        ["git", "-C", str(vendor), *args], capture_output=True, text=True
    )
    if check and result.returncode != 0:
        sys.exit(f"error: git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


subprocess.run(["git", "-C", str(vendor), "fetch", "--tags", "--quiet", "origin"],
               capture_output=True)

if not target_ref:
    tags = git("tag", "--list", "--sort=-v:refname").split()
    target_ref = tags[0] if tags else (
        git("symbolic-ref", "--short", "refs/remotes/origin/HEAD", check=False).strip()
        or "origin/main")

target_sha = git("rev-parse", f"{target_ref}^{{commit}}").strip()
if target_sha == pinned:
    print(f"{name} is already pinned at {target_ref} ({target_sha[:8]}). Nothing to do.")
    sys.exit(0)

if subprocess.run(["git", "-C", str(vendor), "cat-file", "-e", f"{target_sha}:{new_path}"],
                  capture_output=True).returncode != 0:
    sys.exit(f"error: upstream path '{new_path}' does not exist at {target_ref}.\n"
             f"       It was renamed or deleted — update status/head_path in CONFIG.yaml first.")

# --- what do we have, and what zone is each file in? ---
observed = up.classify(skill_dir, vendor, pinned, old_path)
old_files = set(up.git_ls_tree(vendor, pinned, old_path))
new_files = set(up.git_ls_tree(vendor, target_sha, new_path))

ff, conflicts, added, removed, unchanged = [], [], [], [], []

for rel in sorted(old_files | new_files):
    old_blob = up.git_show(vendor, pinned, f"{old_path}/{rel}") if rel in old_files else None
    new_blob = up.git_show(vendor, target_sha, f"{new_path}/{rel}") if rel in new_files else None
    if old_blob == new_blob:
        unchanged.append(rel)
        continue
    zone = observed.get(rel)
    if zone == "adapted":
        conflicts.append(rel)
    elif zone == "verbatim":
        if new_blob is None:
            removed.append(rel)
        else:
            ff.append(rel)
    elif zone is None:
        # Upstream added a file we have never had.
        if new_blob is not None:
            added.append(rel)
    # zone == "ours": a name collision with skillmonger furniture; leave it.

print(f"{name}: {block.get('ref')} ({pinned[:8]}) -> {target_ref} ({target_sha[:8]})")
if new_path != old_path:
    print(f"  upstream renamed: {old_path} -> {new_path}")
print(f"  {len(unchanged)} unchanged, {len(ff)} to fast-forward, "
      f"{len(added)} new, {len(removed)} removed upstream, "
      f"{len(conflicts)} need review")

for rel in ff:
    print(f"    FF   {rel}")
for rel in added:
    print(f"    NEW  {rel}")
for rel in conflicts:
    print(f"    !!   {rel}  (adapted — upstream changed it too)")

# Deletions are never automatic. Upstream dropping a reference file says nothing
# about whether OUR adapted SKILL.md still links to it — and it usually does.
referenced = {}
for rel in removed:
    hits = []
    for other in up.skill_files(skill_dir):
        if other == rel or observed.get(other) == "verbatim":
            continue
        try:
            if Path(rel).name in (skill_dir / other).read_text(errors="ignore"):
                hits.append(other)
        except (OSError, UnicodeDecodeError):
            pass
    referenced[rel] = hits
    flag = f"  STILL REFERENCED BY {', '.join(hits)}" if hits else ""
    print(f"    DEL? {rel}  (upstream removed it){flag}")

if dry_run:
    print("\n--dry-run: nothing written.")
    sys.exit(0)

# A sync is all-or-nothing. Fast-forwarding verbatim files while the pin stays
# put would leave them matching neither the old pin nor any recorded state, and
# check-upstream.sh would then correctly call that local drift. So when anything
# needs a human, write nothing and let them come back with --accept.
if (conflicts or removed) and not accept:
    review = root / ".upstream-review" / name
    for rel in conflicts:
        for label, ref, path in (("upstream-old", pinned, old_path),
                                 ("upstream-new", target_sha, new_path)):
            blob = up.git_show(vendor, ref, f"{path}/{rel}")
            if blob is None:
                continue
            dest = review / label / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(blob)

    blockers = []
    if conflicts:
        blockers.append(f"{len(conflicts)} adapted file(s) changed upstream")
    if removed:
        blockers.append(f"{len(removed)} file(s) removed upstream")
    print(f"\n{'; '.join(blockers)}. Nothing was written and the pin stays at "
          f"{block.get('ref')}.")
    if conflicts:
        print(f"\n  Upstream's before/after is in: {review.relative_to(root)}")
        print(f"  Port what is worth porting into skills/{name}/ by hand:")
        for rel in conflicts:
            print(f"    diff {review.relative_to(root)}/upstream-old/{rel} \\\n"
                  f"         {review.relative_to(root)}/upstream-new/{rel}")
    if removed:
        print("\n  Removed upstream — decide per file:")
        for rel in removed:
            hits = referenced.get(rel) or []
            if hits:
                print(f"    KEEP {rel} — still referenced by {', '.join(hits)}")
            else:
                print(f"    rm skills/{name}/{rel}   # unreferenced; safe to drop")
    print(f"\nThen re-run to apply the rest and re-pin:")
    print(f"  scripts/sync-upstream.sh {name} --to {target_ref} --accept")
    sys.exit(2)

# --- apply ---
for rel in ff + added:
    blob = up.git_show(vendor, target_sha, f"{new_path}/{rel}")
    dest = skill_dir / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(blob)
    if rel in ff:
        # Preserve the executable bit upstream declares.
        mode = git("ls-tree", target_sha, "--", f"{new_path}/{rel}").split()[0]
        if mode == "100755":
            dest.chmod(dest.stat().st_mode | 0o111)

today = datetime.date.today().isoformat()
review = root / ".upstream-review" / name

# --- re-pin ---
block = dict(block)
block["ref"] = target_ref
block["commit"] = target_sha
block["synced"] = today
if new_path != old_path:
    block["previous_path"] = old_path
    block["path"] = new_path
    block.pop("head_path", None)
    block["status"] = "tracked"
up.write_upstream_block(skill_dir, block)

zones = up.classify(skill_dir, vendor, target_sha, block["path"])
up.write_source_md(skill_dir, name, block, zones)

counts = {}
for zone in zones.values():
    counts[zone] = counts.get(zone, 0) + 1
print(f"\nRe-pinned to {target_ref} ({target_sha[:8]}).")
print("  zones: " + ", ".join(f"{v} {k}" for k, v in sorted(counts.items())))
if accept and conflicts:
    print(f"  {len(conflicts)} adapted file(s) accepted as reviewed — "
          f"record what you ported in SOURCE.md.")
if review and review.exists():
    print(f"  review copies left in {review.relative_to(root)} — delete when done.")
print("\nValidate and redeploy:")
print(f"  scripts/validate-skill.sh skills/{name} && scripts/deploy-skill.sh {name}")
PY
