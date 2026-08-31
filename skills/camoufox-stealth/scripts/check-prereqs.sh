#!/bin/bash
# check-prereqs.sh — readiness probe for the camoufox-stealth skill.
# Exit 0 always. Emits {"ready":bool,"checks":[...],"context":{}}.
# Delegates to `sm-stealth doctor`; falls back to a minimal report if that fails.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if out="$("$DIR/sm-stealth" doctor 2>/dev/null)" && [ -n "$out" ]; then
  printf '%s\n' "$out"
  exit 0
fi

# Fallback: sm-stealth itself could not run (e.g. no usable python3).
if command -v python3 >/dev/null 2>&1; then
  pyver="$(python3 -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])' 2>/dev/null || echo unknown)"
  pystatus="ok"
else
  pyver="unknown"
  pystatus="missing"
fi

cat <<EOF
{"ready":false,"checks":[{"name":"python3","status":"$pystatus","version":"$pyver"},{"name":"sm-stealth","status":"missing","hint":"scripts/sm-stealth failed to run; check python3 and camoufox install"}],"context":{}}
EOF
exit 0
