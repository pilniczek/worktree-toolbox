# worktree-per-issue — AGENTS.md

Tool-specific contributor notes and vocabulary for worktree-per-issue. Repo-wide conventions
(installer rules, how to test, docs conventions, ADRs) live in the [root AGENTS.md](../AGENTS.md).

## Installer specifics

Its `install.sh` adds a `warn` helper alongside the shared `say`/`die`. It is the only tool with
**interactive prompts**, and they only build the *config file* when it is missing: free-form
entries per key, nothing prefilled. Under `curl | sh` (no TTY) it writes an empty file. There is
no env override: a scripted install commits `.claude/worktree.json` first, and the installer keeps
it. Every template file is copied as-is. The installer hands its answers to
`scripts/worktree-setup.cjs init` as `<key> <entry>` argument pairs, which writes the file. Then it
runs the same check setup uses (`worktree-setup.cjs check`) and prints any config error as a
warning, exit 0.

## Commands are thin wrappers over scripts

The three slash commands (`.claude/commands/worktree-*.md`) carry no logic - each just runs the
matching `template/scripts/worktree-<name>.sh` and relays its output. The branchy work (mode
detection, validation, the flat-name rule, the `git worktree` calls) lives in the scripts, so a
command run costs no prompt reasoning. Worktree setup is the exception to shell: callers run
`scripts/worktree-setup.cjs` through `wt_setup_cjs` (checks for `node`). That node module owns the config schema (the five keys, every path rule), places the entries, runs the steps,
and writes the marker; before removal it drops the link entries (`unlink`) and puts them back if git refuses (`relink`). Shared rules live once in `scripts/worktree-common.sh`,
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
   `|| true`** (bash keeps going). `: > "$MARKER"` aborts the script when the marker's directory is
   absent. Guard the whole thing instead:
   `if [ -d "$DIR" ]; then : > "$MARKER" …; fi`. Not `[ -d … ] && { … }`: as a script's last
   command under `set -e`, its false test becomes the exit status, so the script reports failure
   whenever the directory is absent.

Before shipping a script change, lint with **`dash -n` AND `bash -n`**, and run the full
create → heal → remove lifecycle forced through **both** shells (`TEST_SH=dash` and `TEST_SH=bash`
runs of the repo-wide `install-matrix.sh`; see its known gap in the [root AGENTS.md](../AGENTS.md)).

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
The scope one worktree (one issue / one agent run) addresses.

**Config file**:
`.claude/worktree.json` in the main checkout, committed. Holds every per-worktree setup choice in
five keys: `copy`, `hardlink`, `link`, `repos`, `steps`. Read by `scripts/worktree-setup.cjs`, which
validates it and does the setup.

**Copy / hardlink / link mode**:
How an entry `<path>` becomes `<worktree>/<path>` from `<main>/<path>`. *Copy*: a real copy.
*Hardlink*: its own dir tree with hardlinked files, falling back to copy. *Link*: a symlink, or a
junction on Windows.

**Repo link**:
A `repos` entry `<name>`: one link `<main>/.claude/worktrees/<name>` to `<main>/../<name>`,
shared by all worktrees, so `../<name>` resolves the same from main and every worktree. No
worktree owns it; removal never touches it. See [ADR 0002](../docs/adr/0002-repos-separate-key.md).

**Submodule stop**:
The STOP `/worktree-remove` gives when git refuses a worktree with an initialized submodule. It
prints the checks and the manual removal commands; it never forces.

**Provisioning step**:
A command in the config file's `steps`, run once when a worktree is created and again on
`/worktree-heal`.

**Minimal worktree**:
A worktree that `worktree-create.sh <branch> --repo <path>` makes in another repo that has no
worktree toolbox (no *config file*): `git worktree add` and nothing more - no package install, no
setup. It never reads this repo's config file and gets no heal or remove; the user removes it by
hand.

**Non-interactive install**:
Running an `install.sh` with no controlling TTY (the `curl | sh` path). The installer detects
this (`( : >/dev/tty )`), skips all prompts, and writes an empty config file - so any entry must
come from a committed config file.
