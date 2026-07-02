# Build a purpose-built completion report instead of adopting claude-sessions

We wanted per-worktree work summaries that a reviewing agent or a fresh session can read
instead of re-deriving intent from the diff. We evaluated
[iannuttall/claude-sessions](https://github.com/iannuttall/claude-sessions) (1207★, 137
forks) and its forks, and chose **not** to adopt it: it is archived, and its core model —
a single global `.current-session` pointer, one active session per project — is the
opposite of this toolbox's many-parallel-worktrees model. No fork is a live
re-architecture (the most-starred has 3★ and only adds a `session-load` command). The need
is validated but every implementation is dead.

Instead we added a small `/work-report` command (the standalone `work-report` tool) that
writes a single `WORK-REPORT.md` at the working tree's root, reusing claude-sessions'
retrospective _format shape_ (goals, completed tasks, problem→solution) and `handoff`'s
discipline (reference artifacts, don't duplicate; keep it lean). One living file per working
tree, overwritten in place, sidesteps the single-session collision entirely. It is a
standalone tool (not coupled to worktrees) because a work summary is useful in any repo.

## Considered options

- **Adopt claude-sessions / a fork** — rejected: archived; single-active-session model
  collides with parallel worktrees.
- **Adopt the `handoff` skill** — good fit for the lateral agent→agent hop, but ephemeral
  (OS temp dir, not worktree-scoped) and one-shot, so it does not give durable per-worktree
  records. Kept as inspiration, not a dependency — see [Why not depend on `handoff`?](#why-not-depend-on-handoff)
  for the full analysis. We ported its two portable content features (a "suggested skills" cue
  and secret-redaction discipline) into `/work-report` without adopting its storage or lifecycle model.
- **Build `/work-report` as a standalone tool** — chosen: small, works in any repo (worktree
  or not), one living file per working tree by construction.

## Why not depend on `handoff`?

Depending on `handoff` looked cleaner than owning a command, so we checked it against its
[SKILL.md source](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md).
Its entire spec is ~6 sentences, and it writes to the **OS temp directory — hardcoded, with no
override** (arguments shape the document's _content_, not its location). That leaves three ways to
"depend" on it, none of them actually a clean dependency:

1. **Depend on it unmodified** → reports live in `/tmp` and evaporate; a reviewer on the PR or a
   session resuming days later has nothing durable to read. This kills the per-worktree record that
   is the whole point.
2. **Fork it and change the storage path** → a fork is not a dependency. We would own it _and_
   inherit its `npx skills add …` distribution model — strictly more to maintain than the ~50-line
   command we already control.
3. **Wrapper that relocates handoff's output** → handoff never defines a filename, so we would be
   globbing `/tmp` for the freshest file. Brittle.

`handoff` is also **one-shot**: with no filename defined, repeated runs in a session produce
undefined behavior (orphan temp files), and nothing tells it to read a prior document and build on
it. `work-report` is deterministic by construction — one `WORK-REPORT.md` per worktree,
read-prior-then-overwrite — which is exactly the iterative-checkpointing case handoff does not serve.
Both are slash commands (`disable-model-invocation: true`), so invocation UX was never a
differentiator; the split is purely storage + lifecycle.
