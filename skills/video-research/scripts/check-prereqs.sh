#!/bin/bash
set -euo pipefail

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g'
}

command_path() {
  command -v "$1" 2>/dev/null || true
}

yt_dlp_path="$(command_path yt-dlp)"
ffmpeg_path="$(command_path ffmpeg)"

ready=true
if [ -z "$yt_dlp_path" ]; then
  ready=false
fi

yt_dlp_json_path="$(printf '%s' "$yt_dlp_path" | json_escape)"
ffmpeg_json_path="$(printf '%s' "$ffmpeg_path" | json_escape)"

cat <<JSON
{
  "ready": $ready,
  "checks": [
    {
      "name": "yt-dlp",
      "required": true,
      "ok": $([ -n "$yt_dlp_path" ] && printf true || printf false),
      "path": "$yt_dlp_json_path",
      "required_for": ["search", "probe", "transcript", "comments", "sites", "download", "clip", "explore"]
    },
    {
      "name": "ffmpeg",
      "required": false,
      "ok": $([ -n "$ffmpeg_path" ] && printf true || printf false),
      "path": "$ffmpeg_json_path",
      "required_for": ["clip", "download:audio", "download:video", "download:subtitles", "merge", "remux", "recode", "embed_metadata", "embed_thumbnail", "split_chapters"]
    }
  ],
  "context": {
    "contract": "sm-video",
    "source": "yt-dlp",
    "schema_version": 1
  }
}
JSON

exit 0
