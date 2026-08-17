#!/bin/bash
# Report whether the lazy npx runner can operate.
set -euo pipefail

checks=()
ready=true

add_missing() {
  checks+=("{\"name\":\"$1\",\"status\":\"missing\",\"note\":\"$2\"}")
  ready=false
}

if command -v npx >/dev/null 2>&1; then
  checks+=("{\"name\":\"npx\",\"status\":\"ok\",\"version\":\"$(npx --version 2>&1)\"}")
else
  add_missing "npx" "install Node.js 18 or newer"
fi

python_version=""
for candidate in python3 python3.14 python3.13 python3.12 python3.11 python3.10 /opt/homebrew/bin/python3; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 10))' 2>/dev/null; then
    python_version=$("$candidate" --version 2>&1 | awk '{print $2}')
    break
  fi
done

if [[ -n "$python_version" ]]; then
  checks+=("{\"name\":\"python3\",\"status\":\"ok\",\"version\":\"$python_version\"}")
else
  add_missing "python3" "Python 3.10 or newer required"
fi

if command -v ffmpeg >/dev/null 2>&1; then
  checks+=("{\"name\":\"ffmpeg\",\"status\":\"ok\"}")
else
  checks+=("{\"name\":\"ffmpeg\",\"status\":\"missing\",\"note\":\"optional; needed for merging, conversion, and clips\"}")
fi

checks_json=""
for i in "${!checks[@]}"; do
  [[ "$i" -gt 0 ]] && checks_json+=","
  checks_json+="${checks[$i]}"
done

printf '{"ready":%s,"checks":[%s],"context":{"runner":"scripts/run","acquisition":"npx-on-use","channel":"stable"}}\n' "$ready" "$checks_json"
