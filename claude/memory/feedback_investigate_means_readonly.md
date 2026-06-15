---
name: feedback_investigate_means_readonly
description: Investigate/cross-reference/analyze tasks are read-only; never probe unknown endpoints with real data; never execute irreversible actions without explicit user instruction
metadata:
  type: feedback
---

Investigate, cross-reference, analyze, and determine tasks are strictly read-only. Never call a write or mutation endpoint as part of investigation work.

**Why:** During a "cross-reference and determine" task, Claude probed an unknown API endpoint using real participant IDs. The endpoint was live, executed an irreversible payment approval ($4.00) on a CloudResearch participant, and could not be undone. The user had not asked for any action to be taken.

**How to apply:**

1. **Endpoint probing**: Before calling any unknown API endpoint, verify it is safe by using clearly invalid/dummy data (e.g., a UUID that cannot exist), or check the documentation first. Never use real participant IDs, assignment IDs, or project IDs to probe an endpoint whose behavior is unknown.

2. **Investigate = read-only**: When the user says "investigate," "cross-reference," "determine," "analyze," or "find out," the task ends at a written report. No write, mutation, payment, approval, rejection, send, or schedule action is taken.

3. **Irreversible actions require explicit instruction**: Actions that cannot be reversed (payment approvals, participant rejections, messages sent, data deleted) require the user to explicitly say "do it," "execute," "run," or equivalent. Asking "do you want me to proceed?" and interpreting the next message as confirmation is not sufficient -- the user must state the action explicitly.

4. **No self-authorization via API probing**: Discovering that an endpoint exists and works is not authorization to use it in production. Discovery and execution are separate steps, each requiring explicit user intent.
