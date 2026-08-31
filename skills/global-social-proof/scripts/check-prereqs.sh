#!/bin/bash
set -euo pipefail

discussion_status="missing"
if command -v discussion-cli >/dev/null 2>&1; then
  discussion_status="ok"
fi

printf '%s\n' \
  '{"ready":true,"checks":[{"name":"discussion-cli","status":"'"$discussion_status"'","required":false}],"context":{"required_capabilities":["web-search","subagents","centers-of-excellence"],"required_capabilities_shell_detectable":false,"discussion_cli_optional":true}}'
