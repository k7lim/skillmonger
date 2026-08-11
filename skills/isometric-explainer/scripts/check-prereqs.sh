#!/bin/bash
# check-prereqs.sh - Report what this skill needs and what is actually present.
# Readiness lives in the JSON, not the exit code. Always exits 0.
set -uo pipefail

have() { command -v "$1" > /dev/null 2>&1; }

node_ok=false; node_ver=""
if have node; then node_ok=true; node_ver=$(node -v 2>/dev/null); fi

server_cmd=""
if have python3; then server_cmd="python3 -m http.server"
elif have python; then server_cmd="python -m http.server"
elif have npx; then server_cmd="npx --yes serve"
fi

# Playwright resolves from the project, not from the skill directory. The
# package resolving is not enough — an upgraded playwright routinely wants a
# browser build that was never downloaded, and that fails only at launch.
pw_pkg=false; pw_ok=false; pw_detail="not resolvable from \$PWD"
if [ "$node_ok" = true ]; then
  if node -e "require.resolve('playwright',{paths:[process.cwd()]})" > /dev/null 2>&1; then
    pw_pkg=true
    if node -e "
      const {chromium} = require(require.resolve('playwright',{paths:[process.cwd()]}));
      process.exit(require('fs').existsSync(chromium.executablePath()) ? 0 : 1);
    " > /dev/null 2>&1; then
      pw_ok=true
      pw_detail="package and chromium binary present"
    else
      pw_detail="package present but chromium binary missing (run: npx playwright install chromium)"
    fi
  fi
fi

ready=false
[ "$node_ok" = true ] && [ -n "$server_cmd" ] && ready=true

cat << EOF
{
  "ready": $ready,
  "checks": [
    {"name": "node", "ok": $node_ok, "detail": "${node_ver:-not found}",
     "required": true,
     "remedy": "Install Node 18+. Needed for \`node --check\` and the smoke test."},
    {"name": "static-server", "ok": $([ -n "$server_cmd" ] && echo true || echo false),
     "detail": "${server_cmd:-none}", "required": true,
     "remedy": "Install python3, or use any static file server."},
    {"name": "playwright", "ok": $pw_ok,
     "detail": "$pw_detail",
     "package_resolves": $pw_pkg,
     "required": false,
     "remedy": "npm i -D playwright && npx playwright install chromium — from the PROJECT dir, not the skill dir. Without it the explainer cannot be verified; say so rather than claiming it works."}
  ],
  "context": {
    "server_cmd": "${server_cmd:-}",
    "can_verify": $pw_ok
  }
}
EOF
