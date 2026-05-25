---
name: Agent token cost calibration
description: Real-world data on how much Explore agents cost; guidance on when parallelism is worth it
type: feedback
---

Avoid spawning multiple broad Explore agents during planning on large codebases. A single "explore the staging layer" Explore agent read 36 files and consumed 58.7k tokens; 3 agents together burned 24% of a weekly session before any implementation began.

**Why:** The user observed session usage jump from 61% to 85% during a planning pass with 3 Explore agents on a dbt project (RCG). That left insufficient budget to implement the plan.

**How to apply:**
- During planning: prefer targeted Glob/Grep over Explore agents when you know what to look for. Use 1-2 Explore agents max, with tightly scoped prompts.
- During implementation: parallel agents are fine for independent file writes -- cost is bounded by files being modified.
- Lean plan + refine during implementation beats exhaustive plan that exhausts the session.
- The user is explicitly patient -- sequential planning is acceptable; wall-clock time is not the constraint.
