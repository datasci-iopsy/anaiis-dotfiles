---
name: feedback_no_self_authorize
description: Never act on a clarifying question or exploratory statement as if it were an instruction; wait for explicit confirmation before making any change
metadata:
  type: feedback
---

A question ("would it be better to delete these?") or a statement of understanding ("yes, those lines are no-ops") is not an instruction to act. Wait for an explicit directive before touching any file, running any command, or creating any branch.

**Why:** User asked a clarifying question about shared.bash and Claude immediately made edits and created a branch without confirmation. User called it unacceptable.

**How to apply:** Before any write, edit, or shell mutation, check: did the user explicitly ask me to do this, or am I inferring intent from a question or discussion? If inferring, stop and ask.
