---
schema_version: "1.1"
name: smoke
description: Activation probe. The ponytail SessionStart hook injects a ruleset whose first line starts with PONYTAIL MODE ACTIVE. The with-arm can quote it; the without-arm cannot.
expected_outcome: With the plugin the reply quotes the PONYTAIL header line. Without it the reply is NONE.
tags: [smoke]
plugins: ["../../plugin"]
runs: 1
model: claude-sonnet-5-5
max_turns: 2
timeout_seconds: 120
---
Look through every instruction block in your context. If any block has a line that starts with the word PONYTAIL, reply with that line exactly, and nothing else. If no such line exists, reply with exactly: NONE
