---
description: Write/update the work report for this repo — a standardized summary of the work done
argument-hint: "(optional) a note to emphasize in the report; omit to summarize all the work here"
allowed-tools: Bash(git rev-parse:*), Bash(git branch:*), Bash(printenv:*), Bash(ls:*), Bash(grep:*), Read, Write
---

Write (or update) the **work report**: a standalone, standardized summary another agent (a reviewer, or a fresh session
continuing the work) can read *instead of* re-deriving intent from the raw diff. There is **one report per working
tree** — `WORK-REPORT.md` at its root — and each run **overwrites** it, so it is always the current state, never a pile
of fragments. It works **anywhere** — a git worktree, the main checkout, or any git repo; it does **not** require a
worktree. Run it **every time** work is checkpointed or handed off, whatever its shape (commits, loose edits, cross-repo
changes, editor settings).

**Scope of "the work" = this chat session.** The report is a *self-report* of what you did in the current session — not
a reconstruction from git history. Do **not** infer the change set from `git diff`/`git log`; report from what you know.
Optional `$ARGUMENTS` is a free-text note that **emphasizes**, it never **restricts**: the report always covers all of
the session's work in full; a note only makes the named topic lead each section. Completeness never depends on the note.

**Altitude — keep every entry the same size.** Goal is 1–2 sentences. Every nested bullet (Problem, Solution, Checked,
etc.) is 1–2 sentences. Every list item is one sentence plus an optional parenthetical. **No paragraphs anywhere.**

Do these in order; STOP and report only if a **required command errors** (you cannot resolve the working-tree root, or
`git` is unavailable) — a quiet session with little to report is **not** a failure; still write a valid report.

1. **Locate the report.** Get the working-tree root with `git rev-parse --show-toplevel`; the report is
   `<root>/WORK-REPORT.md`. If you are **not** inside a git repo, use the current directory.

2. **Read the existing report if present, and build on it** — carry forward the Abandoned approaches list, close or keep
   Follow-ups, keep resolved decisions — rather than regenerating from scratch and losing prior context. (Resuming and
   reviewing are the same read-only act: a session picking the work back up reads this file to regain context; a
   reviewer reads it to assess. Only this command writes.)

3. **Compose the report.** Start with the title block, then the six sections below, in order. The report's value is what
   the diff **cannot** show — intent, reasoning, verification, next steps — so **never restate the git diff** (commits,
   changed files); the reader gets that from git/the PR. **Reference** artifacts (PR/issue URLs, file paths, ADRs)
   rather than pasting their contents. **Redact secrets** — never reproduce the value of any API key, password, token,
   credential, or PII; note only that it exists and where.

   **Title block** — the title is exactly `# Work report`, followed by three identifier lines:

   ```text
   # Work report

   - **branch:** <git branch --show-current, or `(detached)` if none>
   - **session title:** <session title, or `(untitled)` if none found>
   - **session id:** <$CLAUDE_CODE_SESSION_ID, or `unknown` if unset>
   ```

   These name the session that **last wrote** this report (the file is overwritten and may be resumed
   across days) — kept on **separate lines** so each label carries exactly one fact. *Session title* is
   the mutable name the VS Code plugin shows for this session and searches its list by; *session id* is
   the stable UUID that confirms the exact match. Read the title as follows (glob locates the transcript;
   the last title-bearing line wins, so a `/rename`d `custom-title` beats the auto-`aiTitle`):

   ```bash
   TRANSCRIPT=$(ls -t "$HOME"/.claude/projects/*/"$CLAUDE_CODE_SESSION_ID".jsonl 2>/dev/null | head -1)
   grep -hoE '"(customTitle|aiTitle)":"[^"]*"' "$TRANSCRIPT" | tail -1 | sed -E 's/^"[^"]*":"(.*)"$/\1/'
   ```

   The title is a **point-in-time snapshot**; an auto-generated title may drift from what the plugin
   later shows (the id stays the tie-breaker) — run `/rename` to lock a stable one. Fallbacks: no title
   found → **session title:** `(untitled)`; `$CLAUDE_CODE_SESSION_ID` unset → both lines `unknown`. (A
   title with an embedded `"` is a tolerated edge case — don't over-engineer it.)

   Then, each as an `##` (H2) heading:

   - **Goal** — what this work set out to do.
   - **Problem → Solution** — every problem you hit and how it was ultimately resolved, as a numbered list. Log an entry
     whenever **your first attempt failed and you changed course**, OR **a real fork (≥2 viable options) was chosen** —
     record the problem and the approach that **worked** (or the fork you took and why). Attempts you abandoned along the
     way do **not** go here; they go under *Abandoned approaches*. Each entry is a number with two nested bullets:

     ```text
     1.
         - **Problem:** description
         - **Solution:** description
     2.
         - **Problem:** description
         - **Solution:** description
     ```

   - **Verification** — two bulleted sub-lists: **Checked:** what you exercised to believe it works, and **Not verified:**
     the gaps you are leaving open. Be honest about the second.
   - **Follow-ups** — one flat list of what the next session or reviewer should pick up, each item **tagged** by kind:
     - `[question]` — an unresolved decision or unknown that needs an answer (phrase it as a question).
     - `[action]` — concrete work to be done (phrase it as an imperative).
   - **Suggested skills** — skills or slash-commands the next agent should invoke. List a skill **only if it advances an
     `[action]` item** in Follow-ups, formatted `/skill — which action it advances`. Mandatory; write "none" if nothing
     maps.
   - **Abandoned approaches** — approaches you did **not** keep, so the next agent does not re-walk them. Flat numbered
     list, each entry **tagged** by kind, one sentence plus the reason:
     - `[tried]` — you implemented or attempted it, then reverted.
     - `[considered]` — you evaluated it and rejected it without building it.

     ```text
     1. [tried] description — why it was backed out
     2. [considered] description — why it was rejected
     ```

     Omit this section entirely if there are none.

4. **Write the file** to `<root>/WORK-REPORT.md`, overwriting the previous report.

5. **Report** the path you wrote and a one-line summary. Note that `WORK-REPORT.md` is gitignored by default (the
   installer adds it); to make it visible to a reviewer on the PR, commit it deliberately with `git add -f WORK-REPORT.md`.
