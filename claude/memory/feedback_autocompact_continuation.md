---
name: feedback-autocompact-continuation
description: At 85% context, /compact immediately then resume work from the handoff -- never stop and wait
metadata:
  type: feedback
  originSessionId: b8c5f831-e474-4e2f-b871-fbb34dcf76eb
---

When context reaches ~85%, trigger /compact and immediately resume from where work was interrupted.

**Why:** The pre-compact hook writes a timestamped handoff file; the post-compact hook restores it as a system message. The restored message contains: active branch, files edited, git state, open tasks, and the in-progress item. No re-orientation or user question is needed.

**How to apply:** Do not ask "where were we?" Do not summarize the prior session. Read the restored systemMessage, identify the item marked IN PROGRESS, and execute it. The user expects the work loop to be fully autonomous across this boundary. Threshold is 85%; do not wait for auto-compact to fire at 100%.
