# AGENTS.md

This is a monorepo of two **self-contained** Claude Code tools for a worktree-per-issue workflow.
Each tool is a top-level folder installable into a target project by its own
`curl … | sh` one-liner. The tools complement each other but must not depend on each other.

**Strict isolation - no tool may name another.** Beyond "don't depend," a tool must not *reference*
any sibling anywhere in its own files (slash commands, template docs, its README); describe the
concept generically instead (e.g. "a separate Claude session started inside the worktree", not the
keybinding that opens one). Indirect leaks count too - keybinding chords, artifact names, and
relative paths (`../vscode-claude-tabs/`) all name a sibling a solo install may not have. The rule
extends to **external companions** such as the `/work-report` skill and its `WORK-REPORT.md`: a tool
must not assume one is installed either. Cross-tool integration recipes belong **only** in the
[root README](README.md).

## Tools

Each tool has its own `AGENTS.md` with its vocabulary and any tool-specific contributor notes —
read the one for the tool you're touching:

- [worktree-per-issue/AGENTS.md](worktree-per-issue/AGENTS.md) — the worktree-per-issue toolbox
  (slash commands, git hook, per-worktree provisioning).
- [vscode-claude-tabs/AGENTS.md](vscode-claude-tabs/AGENTS.md) — the per-worktree claude-tabs
  keybinding generator.

The `/work-report` skill was **removed from this monorepo** and now lives in
[pilniczek/dev-skills](https://github.com/pilniczek/dev-skills/tree/master/skills/work-report),
installed with skills.sh (`npx skills add`). Its spec, vocabulary, and contract pins are maintained
there — don't re-add a copy or an installer here. The ADR explaining why the report was built rather
than adopting claude-sessions or `handoff` moved with it:
[dev-skills ADR 0001](https://github.com/pilniczek/dev-skills/blob/master/docs/adr/0001-completion-report-over-claude-sessions.md).

## Installer conventions

Every `install.sh` is POSIX `#!/usr/bin/env sh` with `set -eu` and `say`/`die` helpers. Keep new
installers consistent with these rules:

- **Additive config, idempotent files.** Skip when identical (`cmp -s`); overwrite differing
  toolbox-owned files in place (they're git-tracked, so `git diff` is the safety net); merge
  config additively so user values are never lost; and append to `.gitignore` only if the
  line is absent. A second run must report "unchanged", not rewrite.
- **Env overrides** for testing and forks, honored by both installers:
  - `WORKTREE_TOOLBOX_REPO` — `owner/repo` to fetch (default `pilniczek/worktree-toolbox`).
  - `WORKTREE_TOOLBOX_REF` — branch/tag/sha (default `main`).
  - `WORKTREE_TOOLBOX_SRC` — a local source dir; **skips the download** entirely.
- **Source resolution order:** explicit `WORKTREE_TOOLBOX_SRC` → a checkout sitting next to
  the script → download a tarball from GitHub.

The ~50 lines of bootstrap boilerplate (`say`/`die`, env-override parsing, source resolution) are
**duplicated across both `install.sh` on purpose** - each must run standalone from a piped
`curl … | sh` with no second file to source, which a shared library would break. Do not factor them
out; keep the copies in sync by hand.

Tool-specific installer behavior (e.g. worktree-per-issue's interactive prompts and their
non-interactive env overrides) lives in that tool's `AGENTS.md`.

## How to test (no CI, no test suite)

No CI, linter, formatter, or automated test lives here - **you must self-verify.** Run an installer
against a throwaway git repo using the local source (pointed at the tool's own folder), then re-run
it:

```sh
# from a scratch target repo
WORKTREE_TOOLBOX_SRC=/path/to/worktree-toolbox/vscode-claude-tabs sh /path/to/worktree-toolbox/vscode-claude-tabs/install.sh
```

The first run should install the expected files; the second should report them `= … (unchanged)`
(idempotency).

`test/install-matrix.sh` smoke-tests all 3 non-empty tool combinations together, asserting they
don't collide, plus one case asserting worktree-per-issue's non-interactive env overrides
(`WORKTREE_TOOLBOX_PM_INSTALL` / `_PROVISION`) reach the templated output. It is fully **offline**
and **sandboxed** (`HOME`, `INSTALL_DIR`, and the VS Code
keybindings path are redirected to temp dirs, so your real `~/.claude` and VS Code config are never
touched). Requires `git`, `node`, `sh`.

**Known gap:** the matrix covers install and idempotency only, **not** the runtime
create→heal→remove worktree lifecycle - a portability bug once shipped through this gap. When you
change any `scripts/worktree-*.sh`, self-verify the lifecycle by hand (the dash/bash matrix is in
[worktree-per-issue/AGENTS.md](worktree-per-issue/AGENTS.md)).

## Comment & docs conventions

- **Comment density is deliberate — keep the "why."** Scripts here are comment-dense on purpose:
  comments that explain non-obvious reasoning (dash quirks, subshell/exit semantics, Windows file
  locks) are load-bearing and must be preserved. Only "what"-restating comments and header
  boilerplate are cuttable.
- **Say it once.** Each idea gets one canonical home; other mentions are brief pointers or nothing.
  Repeated statements of the same idea are length to cut, not reinforcement.
- **Doc audience split.** Human-facing `README.md` files (root + per-tool) may repeat across each
  other so each stands alone - that overlap is intentional, don't dedup it. Agent-facing guidance
  lives in `AGENTS.md`: **this root file** holds only general/organizational rules and links; each
  tool's own `AGENTS.md` holds that tool's vocabulary + tool-specific notes. The domain glossary is
  distributed - each term defined exactly once, in the tool that owns it.
- **Section dividers** (all scripts, `.sh` and `.js`): one form only — `# --- label -------` (or
  `// --- label -------`), a 1-2 word lowercase label then hyphens padding the line to **93**
  columns. Generate the padding programmatically (don't hand-count); the opening labeled divider is
  the only marker (no bottom rule). A comment whose dashes are real content (`// --porcelain …`, a
  `--force` flag) is **not** a divider — leave it alone.

## Decisions and commits

Significant or contested choices go in `docs/adr/`. Read before re-opening a settled question. The
directory **does not exist yet** — the one ADR it held moved to dev-skills with `/work-report` — so
create it lazily when the next decision needs recording, numbering from `0001`.
