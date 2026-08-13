# AGENTS.md

This repo holds one **self-contained** Claude Code tool for a worktree-per-issue workflow:
[worktree-per-issue](worktree-per-issue/), a top-level folder installable into a target project by
its own `curl … | sh` one-liner.

**The tool must stand alone - it may not name a companion it cannot install.** Nothing inside
`worktree-per-issue/` (slash commands, template docs, its README) may reference an external tool or
skill as if it were present: not a VS Code keybinding or extension, not the `/work-report` skill or
its `WORK-REPORT.md`, not a sibling checkout by relative path. Describe the concept generically
instead (e.g. "a separate Claude session started inside the worktree", not the chord that opens one).
Integration recipes that assume a companion belong **only** in the [root README](README.md).

## Tool notes

[worktree-per-issue/AGENTS.md](worktree-per-issue/AGENTS.md) holds the tool's vocabulary and its
contributor notes (interactive prompts and their env overrides, the thin-command/scripts split,
dash-safety rules, shell function conventions) — read it before touching anything in that folder.

Two tools were **removed from this repo** and now live elsewhere; don't re-add a copy or an installer
for either:

- the `/work-report` skill →
  [pilniczek/dev-skills](https://github.com/pilniczek/dev-skills/tree/master/skills/work-report),
  installed with skills.sh (`npx skills add`).
- the per-worktree claude-tabs VS Code extension → its own repo.

## Installer conventions

`install.sh` is POSIX `#!/usr/bin/env sh` with `set -eu` and `say`/`die`/`warn` helpers. Keep it
consistent with these rules:

- **Additive config, idempotent files.** Skip when identical (`cmp -s`); overwrite differing
  toolbox-owned files in place (they're git-tracked, so `git diff` is the safety net); merge
  config additively so user values are never lost; and append to `.gitignore` only if the
  line is absent. A second run must report "unchanged", not rewrite.
- **Env overrides** for testing and forks:
  - `WORKTREE_TOOLBOX_REPO` — `owner/repo` to fetch (default `pilniczek/worktree-toolbox`).
  - `WORKTREE_TOOLBOX_REF` — branch/tag/sha (default `main`).
  - `WORKTREE_TOOLBOX_SRC` — a local source dir; **skips the download** entirely.
- **Source resolution order:** explicit `WORKTREE_TOOLBOX_SRC` → a checkout sitting next to
  the script → download a tarball from GitHub.
- **Artifacts the tool does not own are warned about, not edited.** The installer may replace or
  delete what a former version of itself wrote (that is git-tracked and documented); a user's own
  scripts and hooks get a printed warning instead.

The ~50 lines of bootstrap boilerplate (`say`/`die`, env-override parsing, source resolution) live
inline in `install.sh` on purpose - it must run standalone from a piped `curl … | sh` with no second
file to source, which a shared library would break. Do not factor them out.

## How to test (no CI, no test suite)

No CI, linter, formatter, or automated test lives here - **you must self-verify.** Run the installer
against a throwaway git repo using the local source, then re-run it:

```sh
# from a scratch target repo
WORKTREE_TOOLBOX_SRC=/path/to/worktree-toolbox/worktree-per-issue sh /path/to/worktree-toolbox/worktree-per-issue/install.sh
```

The first run should install the expected artifacts; the second should report them `= … (unchanged)`
(idempotency).

`test/install-matrix.sh` automates that: one case for install + reinstall, plus one asserting the
non-interactive env overrides (`WORKTREE_TOOLBOX_PM_INSTALL` / `_PROVISION`) reach the templated
output. It is fully **offline** and **sandboxed** (`HOME` and `INSTALL_DIR` are redirected to temp
dirs, so your real `~/.claude` is never touched). Requires `git`, `node`, `sh`.

**Known gap:** the matrix covers install and idempotency only, never runtime behavior. The
create→heal→remove worktree lifecycle is untested - a portability bug once shipped through this gap.
When you change any `scripts/worktree-*.sh`, self-verify the lifecycle by hand (the dash/bash matrix
is in [worktree-per-issue/AGENTS.md](worktree-per-issue/AGENTS.md)).

## Comment & docs conventions

- **Comment density is deliberate — keep the "why."** Scripts here are comment-dense on purpose:
  comments that explain non-obvious reasoning (dash quirks, subshell/exit semantics, Windows file
  locks) are load-bearing and must be preserved. Only "what"-restating comments and header
  boilerplate are cuttable.
- **Say it once.** Each idea gets one canonical home; other mentions are brief pointers or nothing.
  Repeated statements of the same idea are length to cut, not reinforcement.
- **Doc audience split.** The human-facing `README.md` files (root + tool) may repeat across each
  other so each stands alone - that overlap is intentional, don't dedup it. Agent-facing guidance
  lives in `AGENTS.md`: **this root file** holds only general/organizational rules and links; the
  tool's own `AGENTS.md` holds its vocabulary and tool-specific notes. Each term is defined exactly
  once, in the tool's `AGENTS.md`.
- **Section dividers** (all scripts, `.sh` and `.js`): one form only — `# --- label -------` (or
  `// --- label -------`), a 1-2 word lowercase label then hyphens padding the line to **93**
  columns. Generate the padding programmatically (don't hand-count); the opening labeled divider is
  the only marker (no bottom rule). A comment whose dashes are real content (`// --porcelain …`, a
  `--force` flag) is **not** a divider — leave it alone.

## Decisions and commits

Significant or contested choices go in `docs/adr/`. Read before re-opening a settled question. The
directory **does not exist yet** — the ADRs it held moved out with the two tools that left — so
create it lazily when the next decision needs recording, numbering from `0001`.
