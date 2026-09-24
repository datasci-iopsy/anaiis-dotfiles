---
name: style-rule-document-voice
description: Blanket output-style rules (ASD-STE100 register) never rewrite the voice of a user-owned document; carve out the exception, flag it, and let the user remove it
metadata:
  type: feedback
---

When a global style rule ("all prose follows X") would also apply to text Claude writes in
the voice of a user-owned document (manuscript copyedits, peer-review quotes, APA prose the
user requested), carve out that text as an exception and flag the carve-out in the response.

**Why:** the user adopted ASD-STE100 as the default register "regardless of the activity"
(2026-09-24). A literal reading would have rewritten authors' academic prose during
anaiis-copyedit and anaiis-peerreview runs. Claude added the exception and named it; the
user confirmed: "precisely the type of distinction you should make."

**How to apply:** before a blanket output rule reaches a writing skill (copyedit, peerreview,
litreview) or any user-owned document, ask whether the rule governs Claude's own prose or
the document's prose. Apply it to Claude's own prose. Keep the document's register. State
the distinction in one sentence so the user can override it.
