# Inline the shared command block at install instead of injecting it at runtime

The three worktree slash commands (`/worktree-create`, `/worktree-heal`, `/worktree-remove`)
share a block of behavior. We kept it in one file and, at first, pulled it into each command at
invocation with `` !`cat "${CLAUDE_PROJECT_DIR:-.}/.claude/worktree-shared.md"` ``. Recent Claude
Code versions broke this: the slash-command permission checker now statically rejects any `!`
bang-command containing a shell **expansion** (`${...}`) with `Contains expansion`, so all three
commands failed at expansion time. We decided to move the deduplication from **runtime to install
time**: the shared block lives once in the toolbox (`worktree-per-issue/shared/worktree-shared.md`),
and `install.sh` inlines it into each command in place of a `{{WORKTREE_SHARED}}` placeholder
(reusing the same node templating pass that already substitutes `{{WORKTREE_SETUP_SUMMARY}}`). The
installed commands become self-contained plain text — no runtime shell, no permission surface, no
dependence on the session's working directory — and `worktree-shared.md` is never shipped into the
target repo. This supersedes the "Why `` !`cat` `` and not `@import`" rationale previously recorded
in `docs/worktrees.md`.

## Considered options

- **Plain relative `` !`cat .claude/worktree-shared.md` ``** — drops only the expansion. Keeps the
  runtime-injection architecture and still requires `Bash(cat:*)`, a live shared file, and a
  working-directory that happens to be a repo-root checkout. Swaps one fragile runtime dependency
  for another; rejected.
- **`@`-import (`@.claude/worktree-shared.md`)** — the importer that `CLAUDE.md` memory files use
  does not run in `.claude/commands/*.md`, so the line would stay literal text. Not viable.
- **Inline at install (chosen)** — kills the whole class of runtime failures, needs no new
  machinery (the installer already templates these files), and keeps a single source of truth in
  the toolbox. Cost: the installed commands each carry a copy of the block, so shared behavior must
  be edited in the toolbox and re-installed rather than hand-edited in place.
