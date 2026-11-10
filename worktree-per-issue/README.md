# worktree-per-issue

A one-line installer that adds a **worktree-per-issue** toolbox to any git repo run with
[Claude Code](https://claude.com/claude-code).

> Part of [worktree-toolbox](../README.md). Installs INTO a target project.

It gives you two kinds of isolation:

- **Code isolation → a git worktree.** A second working folder that shares the same
  `.git` but sits on its own branch. Pure git.
- **Context isolation → a separate Claude session** opened _in_ the worktree, so
  parallel work never shares one context window.

You get three slash commands that manage a git worktree per issue under
`.claude/worktrees/`. The full narrative also lives in the `docs/worktrees.md` the
installer drops into your project.

## Commands

| Command | Does | Docs |
| --- | --- | --- |
| `/worktree-create` | create a worktree for a branch (new **or** existing) and move you into it | [docs/worktree-create.md](docs/worktree-create.md) |
| `/worktree-heal` | re-run a worktree's setup steps and add missing entries | [docs/worktree-heal.md](docs/worktree-heal.md) |
| `/worktree-remove` | close a worktree and, if safe, delete its branch | [docs/worktree-remove.md](docs/worktree-remove.md) |

## Install

Run from the **root of the target git repo**:

```sh
curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/worktree-per-issue/install.sh | sh
```

On native Windows, run this in **Git Bash** (not CMD/PowerShell). See the [toolbox README](../README.md#install).

The installer only adds; it never overwrites your existing config values. Files it
replaces are overwritten in place (review with `git diff`), and re-running it changes
nothing twice.

## What it installs

| Path | Purpose |
| --- | --- |
| `.claude/commands/worktree-create.md`, `worktree-heal.md`, `worktree-remove.md` | the three slash commands (thin wrappers that run the matching `scripts/worktree-*.sh` and relay its output) |
| `.husky/post-checkout` | convenience hook: runs the setup script on a bare-CLI `git worktree add` |
| `scripts/worktree-create.sh`, `worktree-heal.sh`, `worktree-remove.sh` | the command logic (mode detection, validation, the git worktree calls) — keeps each command off Claude's token budget |
| `scripts/worktree-common.sh` | shared rules (branch-name validation, the flat-name rule, find-main) sourced by the three scripts |
| `scripts/worktree-setup.cjs` | per-worktree setup, driven by `.claude/worktree.json`: checks the file, places entries, runs steps |
| `docs/worktrees.md` | full documentation of the flow |
| `.claude/worktree.json` | what each worktree gets: paths to copy, hardlink or link, and setup steps - written from your answers only when missing, never changed after that |

It also merges into these files without overwriting:

| Path | Merged in |
| --- | --- |
| `.claude/settings.json` | four `permissions.allow` entries: one `Bash(sh scripts/worktree-<name>.sh*)` per slash command, plus `Bash(git worktree *)` for manual use |
| `.vscode/settings.json` | `git.detectWorktrees` + `git.repositoryScanMaxDepth` |
| `.gitignore` | ignores `.claude/worktrees/` |

## What it asks

Only when `.claude/worktree.json` does not exist yet. If it exists, the installer keeps it and
asks nothing. Nothing is prefilled: for each key you type one entry per line, and a blank line
moves to the next key. The keys are described under
[What the automatic setup does](#what-the-automatic-setup-does); the file's shape is in
[docs/worktrees.md](template/docs/worktrees.md#what-the-automatic-setup-does).

Without a terminal (`curl | sh`) it writes an empty file. Edit the file later for more entries; to
script an install, commit `.claude/worktree.json` before you run the installer.

## How it's wired (big picture)

Every worktree is a light checkout sharing the primary checkout's single `.git`. None of this
replaces git - it's only config and a setup script on top of git's built-in worktree features.

- **Create** with `/worktree-create` from your primary checkout: creates or checks out the branch,
  moves you in, and runs setup. See [docs/worktree-create.md](docs/worktree-create.md).
  Add `--repo <path>` when the work also needs a worktree in another repo - see
  [Worktrees in other repos](template/docs/worktrees.md#worktrees-in-other-repos).
- **Heal** a broken worktree with `/worktree-heal`, which re-runs setup with
  `--force`. See [docs/worktree-heal.md](docs/worktree-heal.md).
- **Close** with `/worktree-remove`, which removes the worktree and deletes the branch only if it's
  merged. See [docs/worktree-remove.md](docs/worktree-remove.md).

`/worktree-remove` and `/worktree-heal` act on the main checkout, so they work whether
`/worktree-create` moved you into the worktree or you opened a session directly inside it - you
don't need to step back to main first.

### What the automatic setup does

Once the worktree exists, `scripts/worktree-setup.cjs` sets it up with `node` - called by
`/worktree-create`, or by `.husky/post-checkout` on a bare-CLI `git worktree add`.
It reads `.claude/worktree.json` and is safe to re-run: it never overwrites what the worktree
already has.

- **copy** entries are copied from the main checkout (`.env`, local settings).
- **hardlink** entries get their own dir tree with hardlinked files. For `node_modules` that is
  near-instant and adds almost no disk; an install inside the worktree isolates it, main is never
  touched. Falls back to a copy when hardlinks are not supported (e.g. another filesystem).
- **link** entries point to the main checkout's path.
- **repos** entries name repos next to the main checkout. One shared link in
  `.claude/worktrees/` makes `../<name>` reach the same repo from main and from every worktree.
- **steps** run once per worktree (a marker in the worktree's git dir records it);
  `/worktree-heal` passes `--force` to run them again.

A config error stops setup before it creates anything and names the entry to fix. Full rules:
[What the automatic setup does](template/docs/worktrees.md#what-the-automatic-setup-does).

## Requirements

- `git`, `node` (18.17+ or 20.1+), and (for the hosted one-liner) `curl` + `tar`.
- Cross-platform: setup makes symlinks on Unix/macOS and NTFS junctions on
  native Windows (Git Bash / MSYS / Cygwin).
- **husky** is optional. Without it, the `post-checkout` hook (which covers a bare
  `git worktree add` from the CLI) won't fire — but the `/worktree-create` and
  `/worktree-heal` commands run `scripts/worktree-setup.cjs` directly, so setup works
  either way.

## Local development / testing

```sh
# from a checkout of this repo, against some target project:
WORKTREE_TOOLBOX_SRC="$(pwd)" sh install.sh    # run inside the target repo, SRC points here
```

Env overrides: `WORKTREE_TOOLBOX_REPO` (owner/repo), `WORKTREE_TOOLBOX_REF`
(branch/tag), `WORKTREE_TOOLBOX_SRC` (local source dir, skips the download).
