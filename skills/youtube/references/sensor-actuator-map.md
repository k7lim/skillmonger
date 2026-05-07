---
name: sensor-actuator-map
description: Classification of all sub-skill commands as sensors or actuators
tags: sensor, actuator, commands
---

# Sensor / Actuator Map

| Command | Skill | Type | Side effects |
|---------|-------|------|-------------|
| `scripts/search` | youtube-search | **sensor** | none |
| `scripts/deep-dive` | youtube-search | **sensor** | none |
| `scripts/evaluate` | youtube-search | **sensor** | none |
| `scripts/get-transcript` | youtube-clip | **sensor** | none (temp files cleaned) |
| `scripts/search-transcript` | youtube-clip | **sensor** | none |
| `scripts/explore` | youtube-clip | **actuator** | writes HTML file |
| `python3 -m yt_dlp` | yt-dlp | **actuator** | writes media files |

## Rule

- **Sensors** are safe to call speculatively. No user approval needed.
- **Actuators** require user approval before execution. ALWAYS confirm before running.
