---
name: Memory workflow process
description: How and when to update memory across projects -- three-tier approach, cost tradeoffs, what not to build
type: feedback
---

Memory, compaction, and session history are separate layers with no interaction:
- **Memory files**: loaded fresh at session start; stable facts explicitly saved; persists across sessions
- **Compaction**: mid-session only (~95% context full or `/compact`); condenses current conversation; gone when session ends
- **Session history**: full JSONL transcript on disk; persists until deleted via `claude-cleanup`

Compaction does not read memory. Memory does not influence compaction.

## Three-tier update process

**Tier 1 -- Passive (zero cost):** Claude saves memories during sessions when it encounters something non-obvious (BigQuery encoding quirks, strategic decisions, user corrections). No trigger needed.

**Tier 2 -- End-of-session prompt (~5-10k tokens):** After sessions covering substantive work (architectural decisions, corrected assumptions, strategic shifts), end with:
> "Update memory with anything worth preserving from this session."

Use this for heavy sessions (100+ msgs, complex multi-file work). Skip for routine sessions (quick queries, small fixes).

**Tier 3 -- Manual for strategic context (no cost):** `project_current_phase.md` is maintained by the user, not Claude. Update it in 3 sentences when a major milestone is reached or focus shifts.

**Why:** A post-session memory agent would cost 20-50k tokens per run and most sessions don't produce new memories. The three-tier approach concentrates effort where it adds value.

**How to apply:** Before deleting large old sessions, run Tier 2 prompt in that project to extract anything worth keeping. After seeding a new project with seed-memory.sh, fill in project_current_phase.md manually before starting work.
