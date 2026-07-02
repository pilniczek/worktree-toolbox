# worktree-per-issue — AGENTS.md

Tool-specific contributor notes and vocabulary for worktree-per-issue. General monorepo
conventions (shared installer rules, how to test, ADRs) live in the [root AGENTS.md](../AGENTS.md).

## Installer specifics

Its `install.sh` adds a `warn` helper alongside the shared `say`/`die`. It is the only tool with
**interactive prompts**, so under `curl | sh` (no TTY) it takes all defaults. These env overrides
give a non-interactive run the escape hatch the prompts would otherwise provide:

- `WORKTREE_TOOLBOX_PM_INSTALL` — the exact install command to template into
  `worktree-setup.sh` / `docs/worktrees.md`, for repos whose command isn't the package
  manager's default (e.g. `npm run init`, not `npm install`).
- `WORKTREE_TOOLBOX_PROVISION` — provisioning steps, **one command per line**, for the
  per-worktree setup the interactive loop would otherwise collect.

## Vocabulary is deliberate

Use these terms precisely, and honor the *Avoid* notes.

**Worktree**:
A second working folder that shares the primary checkout's single `.git` but sits on its
own branch — one per issue, under `.claude/worktrees/<flat>/`. Delivers *code isolation*.
*Avoid*: clone, checkout (for this concept).

**Code isolation**:
Giving a work stream its own directory and branch — what a worktree provides. Distinct
from *context isolation*.

**Context isolation**:
Giving a work stream its own Claude conversation (a separate session opened in the
worktree), so parallel work never shares one context window. A worktree does **not** by
itself provide this; opening a fresh session in it does.
*Avoid*: conflating with code isolation.

**Flat name**:
A branch name with every `/` replaced by `+`, used only as the worktree's directory name
(e.g. `feature/abc/T-1` → `feature+abc+T-1`). The branch keeps real `/` separators.

**Work unit**:
The scope one worktree (one issue / one agent run) addresses — the thing a work report covers.

**Provisioning step**:
A per-worktree setup command (e.g. a codegen step) run once when a worktree is created and
again on `/worktree-heal`. Configured interactively during install, or non-interactively via
`WORKTREE_TOOLBOX_PROVISION` (one command per line). Distinct from the *install command*
(`WORKTREE_TOOLBOX_PM_INSTALL`), which only wires up the husky hook.

**Non-interactive install**:
Running an `install.sh` with no controlling TTY (the `curl | sh` path). The installer detects
this (`( : >/dev/tty )`), skips all prompts, and takes defaults — so any non-default choice
must come from an env override.
