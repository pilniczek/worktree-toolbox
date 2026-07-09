# AGENTS.md

This is a monorepo of three **self-contained** Claude Code tools for a worktree-per-issue workflow.
Each tool is a top-level folder installable into a target project by its own
`curl … | sh` one-liner. The tools complement each other but must not depend on each other.

## Tools

Each tool has its own `AGENTS.md` with its vocabulary and any tool-specific contributor notes —
read the one for the tool you're touching:

- [worktree-per-issue/AGENTS.md](worktree-per-issue/AGENTS.md) — the worktree-per-issue toolbox
  (slash commands, git hook, per-worktree provisioning).
- [work-report/AGENTS.md](work-report/AGENTS.md) — the `/work-report` command (`WORK-REPORT.md`).
- [vscode-claude-tabs/AGENTS.md](vscode-claude-tabs/AGENTS.md) — the per-worktree claude-tabs
  keybinding generator.

## Installer conventions

Every `install.sh` is POSIX `#!/usr/bin/env sh` with `set -eu` and `say`/`die` helpers. Keep new
installers consistent with these rules:

- **Additive config, idempotent files.** Skip when identical (`cmp -s`); overwrite differing
  toolbox-owned files in place (they're git-tracked, so `git diff` is the safety net); merge
  config additively so user values are never lost; and append to `.gitignore` only if the
  line is absent. A second run must report "unchanged", not rewrite.
- **Env overrides** for testing and forks, honored by all three installers:
  - `WORKTREE_TOOLBOX_REPO` — `owner/repo` to fetch (default `pilniczek/worktree-toolbox`).
  - `WORKTREE_TOOLBOX_REF` — branch/tag/sha (default `main`).
  - `WORKTREE_TOOLBOX_SRC` — a local source dir; **skips the download** entirely.
- **Source resolution order:** explicit `WORKTREE_TOOLBOX_SRC` → a checkout sitting next to
  the script → download a tarball from GitHub.

Tool-specific installer behavior (e.g. worktree-per-issue's interactive prompts and their
non-interactive env overrides) lives in that tool's `AGENTS.md`.

## How to test (no CI, no test suite)

There is no CI, linter, formatter, or automated test in this repo — **you must self-verify.**
Run an installer against a throwaway git repo using the local source, then re-run it:

```sh
# from a scratch target repo
WORKTREE_TOOLBOX_SRC=/path/to/worktree-toolbox/work-report sh /path/to/worktree-toolbox/work-report/install.sh
```

Confirm the first run installs the expected files and the second run reports them as
`= … (unchanged)` (idempotency). `WORKTREE_TOOLBOX_SRC` points at the tool's own folder.
`test/install-matrix.sh` smoke-tests every tool combination together.

## Decisions and commits

Significant or contested choices go in `docs/adr/` (see
[0001](docs/adr/0001-completion-report-over-claude-sessions.md)). Read the relevant ADR
before re-opening a settled question.
