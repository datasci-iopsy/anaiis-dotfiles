Auto-triggers on CodeRabbit inline review pastes ("Verify each finding against", "Inline comments:", "Outside diff comments:", "Nitpick comments:"). Use /coderabbit-fix explicitly for staged-batch processing. Process findings through the triage rubric, fix rated-4/5 defects, commit by logical group.

## Arguments

$ARGUMENTS, optional flags:
- `--review`: spawn the `code-reviewer` agent on staged changes before committing (quality gate, costs extra tokens)

## Pipeline

Run all steps inline. Do not spawn agents unless `--review` is passed.

### 0. Check for staged batch

Check whether `~/.claude/coderabbit-staged-batch.md` exists and contains non-comment content (lines not starting with `#`).

If a staged batch exists:
- Read the file, it contains raw CodeRabbit findings in the "fix all" format, one finding per "In @file around lines X" block
- For each finding, apply the **full triage rubric**:
  1. Read the affected file around the reported lines to understand local context
  2. Grep for the affected symbol across the codebase to find callers and related files
  3. Rate 1-5:
     - 1-2: false positive or nitpick, dismiss with one-line rationale, no edit
     - 3: judgment call, append to `~/.claude/coderabbit-deferred.md`, report "Deferred: <summary>"
     - 4-5: real defect, spawn the `code-surgeon` agent (`subagent_type: "general-purpose"`, description `"Fix CR-<N>: <summary>"`)
  4. After each surgeon fix, append to `~/.claude/coderabbit-session-log.md` per the standard format
- After all findings are processed, delete `~/.claude/coderabbit-staged-batch.md`
- Then continue to step 1

If no staged batch, proceed directly to step 1.

### 1. Read deferred findings

Read `~/.claude/coderabbit-deferred.md`. If the file is empty or contains only comments (lines starting with `#`), report "No deferred findings. Done." and stop.

### 2. Re-assess each finding

For each finding in the deferred file:
- Use Grep/Glob/Read to verify whether the issue still exists in the current code
- If already resolved (e.g., fixed in a prior commit): mark as **resolved**, skip
- If still present: mark as **actionable**

### 3. Fix actionable findings

For each actionable finding:
- Apply the minimal fix using Edit (never Write unless creating a new file is the fix)
- Do not refactor surrounding code, add comments, or touch unrelated lines
- Group fixes by logical concern (same file, same subsystem, or same finding type)

### 4. Commit by group

For each logical fix group:
- Stage files by name: `git add <file1> <file2>`, never `git add .` or `git add -A`
- Commit with an imperative message describing the fix: `git commit -m "fix: <what>"`
- One commit per logical group; do not batch unrelated fixes into a single commit

If `--review` was passed: before the first commit, spawn the `code-reviewer` agent with the staged diff as context. Address any blocking findings before committing. Advisory findings may be noted but do not block the commit.

### 5. Report

Print a concise summary:
- Fixed: N findings (list commit SHAs and one-line descriptions)
- Already resolved: N findings (list)
- Still deferred: N findings (list, these remain in `~/.claude/coderabbit-deferred.md`)

Do NOT push. The user reviews commits and pushes when satisfied.

## Escalation note

If findings span 5+ unrelated files and you judge that parallel exploration would materially reduce errors, say so explicitly and ask the user whether to proceed with parallel agents. The `cost-guard.sh` hook will gate the cost tier automatically.
