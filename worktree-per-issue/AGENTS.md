# worktree-per-issue — AGENTS.md

Tool-specific contributor notes and vocabulary for worktree-per-issue. General monorepo
conventions (shared installer rules, how to test, ADRs) live in the [root AGENTS.md](../AGENTS.md).

## Installer specifics

Its `install.sh` adds a `warn` helper alongside the shared `say`/`die`. It is the only tool with
**interactive prompts**, so under `curl | sh` (no TTY) it takes all defaults. These env overrides
are the non-interactive escape hatch for those prompts:

- `WORKTREE_TOOLBOX_PM_INSTALL` — the exact install command to template into
  `worktree-setup.sh` / `docs/worktrees.md`, for repos whose command isn't the package
  manager's default (e.g. `npm run init`, not `npm install`).
- `WORKTREE_TOOLBOX_PROVISION` — provisioning steps, **one command per line**, for the
  per-worktree setup the interactive loop would otherwise collect.

## Commands are thin wrappers over scripts

The three slash commands (`.claude/commands/worktree-*.md`) carry no logic - each just runs the
matching `template/scripts/worktree-<name>.sh` and relays its output. The branchy work (mode
detection, validation, the flat-name rule, the `git worktree` calls) lives in the scripts, so a
command run costs no prompt reasoning. Shared rules live once in `scripts/worktree-common.sh`,
sourced by all three - edit a shared rule **there**. When you change behavior, edit the script (and
its `docs/worktree-<name>.md`), not the command file.

`EnterWorktree` is the one thing that stays in the command prompt on purpose: relocating the Claude
session is not a shell operation, so `/worktree-create` reads the script's `WORKTREE_PATH=` line and
calls `EnterWorktree` itself (after the script has already provisioned the worktree).

One in-script trick worth knowing: `worktree-remove.sh` re-execs the main checkout's own copy of
itself before removing anything, so the running script never sits inside the directory being deleted
(an open file blocks its own removal on Windows/MSYS).

**Remove and heal operate from the main checkout, via `git -C "$MAIN" …`** - never via
`ExitWorktree` and never assuming `/worktree-create` relocated the session. That's why they work
from a session started *directly inside* the worktree, not only one create moved in. Keep all
removal git calls anchored to `$MAIN` (`git -C "$MAIN" worktree remove/branch -d/worktree prune` in
`worktree-remove.sh`); do not reintroduce a relative-path or session-location assumption.

## Scripts must be dash-safe

`template/scripts/*.sh` and `.husky/post-checkout` are run as `sh <script>`. On Linux `/bin/sh` is
**dash** (POSIX-strict); on Windows Git Bash `sh` is **bash**. Code that only ran on Windows can
silently break on Linux - two confirmed gotchas that bit this repo:

1. **`echo` mangles backslashes on dash** (bash's doesn't). Never `echo` dynamic content (branch
   names, `$err` from git, paths). Use the `wt_say` / `wt_warn` helpers in `worktree-common.sh`
   (both `printf '%s\n'`), identical on both shells.
2. **A redirect failure on a POSIX *special builtin* (`:`) exits non-interactive dash even with
   `|| true`** (bash keeps going). `: > "$MARKER"` aborted `worktree-setup.sh` when `node_modules`
   was absent. Guard the whole thing instead: `[ -d "$WT/node_modules" ] && { : > "$MARKER" …; }`.

Before shipping a script change, lint with **`dash -n` AND `bash -n`**, and run the full
create → heal → remove lifecycle forced through **both** shells (the repo-wide `install-matrix.sh`
does not cover this runtime lifecycle).

SonarQube (`shelldre:S7688`) flags every `[ … ]` test and suggests `[[ … ]]`. That is a **bash
keyword dash does not have** (`[[: not found`), so switching would break Linux. We keep POSIX `[ … ]`
and mark each flagged line with a trailing `# NOSONAR: POSIX sh` (SonarQube honors `NOSONAR` only on
the issue's own line, never the line above).

## Shell function conventions

When you add or edit a function in any `*.sh`, follow these so the SonarQube scan stays clean and
behavior stays correct. Both hold under dash and bash.

1. **Capture positional parameters in `local` vars** (`shelldre:S7679`). At the top of the function
   write `local name="$1"` (name it after the `# $1 = …` comment) and use `$name` in the body, not
   `$1`/`$2`. `local` is not strict POSIX, but both target shells support it. Example:
   `wt_assert_live()` opens with `local main="$1" flat="$2"`.
2. **End every function with an explicit `return`** (`shelldre:S7682`) - and pick the right one:
   - **`return 0`** for print-only / side-effect helpers whose exit status no caller inspects
     (e.g. `wt_say`, `add_step`).
   - **`return $?`** when a caller inspects the status - `if ! fn …`, `fn || exit 1`, or a checked
     `$(fn)`. A bare `return 0` here silently breaks the caller: e.g. `wt_assert_live` must
     `return $?`, otherwise every worktree reads as "live" and the guard never fires.

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
