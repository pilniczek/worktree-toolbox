# worktree-toolbox

A **worktree-per-issue** toolbox for [Claude Code](https://claude.com/claude-code), installable into
any JavaScript/TypeScript project with a one-line installer.

| Tool | What it does | Installs |
| --- | --- | --- |
| [worktree-per-issue](worktree-per-issue/) | `/worktree-create` (new-or-existing) + `/worktree-heal` (heal) + `/worktree-remove` (close) slash commands, a git hook, and idempotent per-worktree provisioning | **into a target project** (`.claude/`, `scripts/`, config merges) |

## Install

Run from the root of the target git repo:

```sh
curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/worktree-per-issue/install.sh | sh
```

**On Windows:** run the `curl … | sh` one-liner in **Git Bash** (not CMD or PowerShell) - it ships
with [Git for Windows](https://git-scm.com/download/win) and provides `sh`, `curl`, and `tar`. In
**WSL**, use your normal Linux terminal - everything works as-is.

See the [tool's README](worktree-per-issue/README.md) for what it prompts for, what it writes, and
how to customize it.

## Requirements

- `git` and `node`; `curl` + `tar` for the hosted one-liner (on native Windows, Git Bash supplies
  both - no separate install needed).

## Repository layout

```text
worktree-toolbox/
├── worktree-per-issue/     # installs the /worktree-create /worktree-heal /worktree-remove toolbox into a project
│   ├── install.sh
│   ├── lib/merge.cjs
│   ├── docs/…              # per-command reference for contributors
│   └── template/…          # the files copied into the target project
├── test/install-matrix.sh  # install smoke test (see Testing below)
└── skills-lock.json        # skills.sh pins for the Claude skills this repo vendors
```

The installer accepts `WORKTREE_TOOLBOX_REPO`, `WORKTREE_TOOLBOX_REF`, and `WORKTREE_TOOLBOX_SRC`
(a local source dir that skips the download) for testing and forks.

## Testing

`test/install-matrix.sh` is a smoke test guarding the install promise: it installs into a throwaway
git repo and asserts the expected files land, `.gitignore` gets each entry once, and a re-run is
idempotent. A second case checks that the non-interactive env overrides reach the templated output.
It runs fully offline and sandboxed (never touches your real `~/.claude`). Needs `git` + `node`:

```sh
sh test/install-matrix.sh
```

### A note on the shell style

Every `.sh` script here is plain POSIX shell, so the same file runs under **dash** (Linux
`/bin/sh`) and **bash** (Windows Git Bash). That is why the scripts use the older `[ … ]` test form
instead of bash's `[[ … ]]`: `[[` is a bash keyword that simply does not exist in dash, so using it
would break every script on Linux. A code scanner (SonarQube) keeps suggesting `[[`; we decline it
on purpose and tag those lines with a `# NOSONAR: POSIX sh` comment so the warning stays quiet. If
you contribute a script change, check it with both `dash -n yourscript.sh` and `bash -n yourscript.sh`.
