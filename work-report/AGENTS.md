# work-report — AGENTS.md

Tool-specific vocabulary for work-report. General monorepo conventions (shared installer rules,
how to test, ADRs) live in the [root AGENTS.md](../AGENTS.md).

## Vocabulary is deliberate

Use these terms precisely, and honor the *Avoid* notes — e.g. don't call the work report a
"session", "journal", or "handoff doc".

**Work report** (a.k.a. completion report):
The standardized `WORK-REPORT.md` at a working tree's root, written via `/work-report` when
work is checkpointed or handed off — **one per working tree**, overwritten in place on each run,
so it always reflects the current state, never fragments. Works in any repo — a worktree, the
main checkout, or a repo with no worktrees. Gitignored by default.
*Avoid*: summary, handoff doc, session log, journal.

**Self-report**:
The stance of the work report: it records what the author *did and intended*, scoped to the
current chat session, and is **not** reconstructed from git history. Git remains the factual
record of the diff.
*Avoid*: audit, proof, reconstruction.

**The work**:
The subject a work report summarizes — everything done in **the current chat session**, not the
branch's whole history.
*Avoid*: the diff, the changes, the branch.

**Problem → Solution**:
The report section logging every problem hit and the approach that **worked** — triggered by a
first attempt that failed and forced a change of course, or a real fork (≥2 viable options) that
was chosen.
*Avoid*: challenges, issues, notes.

**Abandoned approaches**:
The report section recording approaches that were **not** kept, so the next agent does not
re-walk them. Each entry is tagged `[tried]` (implemented or attempted, then reverted) or
`[considered]` (evaluated and rejected without being built).
*Avoid*: discarded, dead ends, rejected.

**Follow-ups**:
The report section listing what the next session or reviewer picks up. Each entry is tagged
`[question]` (an unresolved decision or unknown) or `[action]` (concrete work to be done).
*Avoid*: open questions, next actions, TODOs.

**Session title**:
The human-readable, **mutable** name the VS Code plugin shows for a session and searches its
list by (`custom-title` if the session was `/rename`d, else the latest auto-generated `aiTitle`).
Recorded in the work report's `session:` line so a reader can find the session in the plugin.
*Avoid*: session name, summary.

**Session id**:
The session's UUID — the transcript filename under `~/.claude/projects/`. **Stable and unique**,
but **not searchable** in the VS Code plugin; it serves as the tie-breaker that confirms an exact
match.
*Avoid*: session, chat id.
