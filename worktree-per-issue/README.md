# worktree-per-issue

A one-line installer that adds a **worktree-per-issue** toolbox to any
JavaScript/TypeScript project run with [Claude Code](https://claude.com/claude-code).

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
| `/worktree-heal` | rebuild a broken or stale worktree's setup in place | [docs/worktree-heal.md](docs/worktree-heal.md) |
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
| `scripts/worktree-setup.sh` | per-worktree setup (`node_modules`, your setup steps, `.worktreeinclude` config) |
| `docs/worktrees.md` | full documentation of the flow |

It also merges into these files without overwriting:

| Path | Merged in |
| --- | --- |
| `.claude/settings.json` | a `Bash(git worktree *)` allow entry |
| `.vscode/settings.json` | `git.detectWorktrees` + `git.repositoryScanMaxDepth` |
| `.gitignore` | ignores `.claude/worktrees/` |
| `.worktreeinclude` | the gitignored local files copied into each worktree |

## What it asks

1. **Package manager** — auto-detected from your lockfile; confirm or override.
2. **Per-worktree setup commands** — zero or more commands (e.g. `npm run generate`).
   They run once when a worktree is created, and again on `/worktree-heal`.
3. **`.worktreeinclude` entries** — zero or more gitignored files to copy into each new
   worktree (env files, `.claude/settings.local.json`, …), entered one path per line.

## How it's wired (big picture)

Every worktree is a light checkout sharing the primary checkout's single `.git`. None of this
replaces git - it's only config and a setup script on top of git's built-in worktree features.

- **Create** with `/worktree-create` from your primary checkout: creates or checks out the branch,
  moves you in, and runs setup. See [docs/worktree-create.md](docs/worktree-create.md).
- **Heal** a broken worktree with `/worktree-heal`, which re-runs setup with
  `--force`. See [docs/worktree-heal.md](docs/worktree-heal.md).
- **Close** with `/worktree-remove`, which removes the worktree and deletes the branch only if it's
  merged. See [docs/worktree-remove.md](docs/worktree-remove.md).

`/worktree-remove` and `/worktree-heal` act on the main checkout, so they work whether
`/worktree-create` moved you into the worktree or you opened a session directly inside it - you
don't need to step back to main first.

### What the automatic setup does

Once the worktree exists, `scripts/worktree-setup.sh` sets it up - called by
`/worktree-create`, or by `.husky/post-checkout` on a bare-CLI `git worktree add`.
It's safe to re-run: a run-once marker under `node_modules/.wt-provisioned` makes a
repeat trigger do nothing, and `/worktree-heal` passes `--force` to rebuild anyway.

- **`node_modules`** is a hardlink-copy of the main checkout's install - a real directory whose
  files share inodes with main, so it's near-instant and adds almost no disk. If a branch needs
  different deps, run your package manager's install inside the worktree; it isolates automatically
  (packages are swapped by atomic rename, so main is never touched). Falls back to a full copy
  (cross-filesystem / Windows), then a real install.
- **Your setup steps** (configured at install time, e.g. `npm run generate`) run once.
- **`.worktreeinclude` config** - the gitignored files you listed are copied from the
  main checkout. Plain `git worktree add` doesn't do this, so the script does.

## Not configured for you

**Sibling-repo links.** If your project imports a sibling repo through a relative
path (a shared library, design system, or knowledge base next to your repo), wire it
up by editing the clearly-marked block in `scripts/worktree-setup.sh`. It ships
commented out with a working `make_junction` example. Layouts vary too much per team
to guess.

## Requirements

- `git`, `node`, and (for the hosted one-liner) `curl` + `tar`.
- Cross-platform: the setup script makes symlinks on Unix/macOS and NTFS junctions on
  native Windows (Git Bash / MSYS / Cygwin).
- **husky** is optional. Without it, the `post-checkout` hook (which covers a bare
  `git worktree add` from the CLI) won't fire — but the `/worktree-create` and
  `/worktree-heal` commands run `scripts/worktree-setup.sh` directly, so setup works
  either way.

## Local development / testing

```sh
# from a checkout of this repo, against some target project:
WORKTREE_TOOLBOX_SRC="$(pwd)" sh install.sh    # run inside the target repo, SRC points here
```

Env overrides: `WORKTREE_TOOLBOX_REPO` (owner/repo), `WORKTREE_TOOLBOX_REF`
(branch/tag), `WORKTREE_TOOLBOX_SRC` (local source dir, skips the download).
