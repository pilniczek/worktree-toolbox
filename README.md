# worktree-toolbox

A small collection of tools for a **worktree-per-issue** workflow with
[Claude Code](https://claude.com/claude-code). Each tool is self-contained in its own folder
with its own one-line installer.

| Tool | What it does | Installs |
| --- | --- | --- |
| [worktree-per-issue](worktree-per-issue/) | `/worktree-create` (new-or-existing) + `/worktree-heal` (heal) + `/worktree-remove` (close) slash commands, a git hook, and idempotent per-worktree provisioning | **into a target project** (`.claude/`, `scripts/`, config merges) |
| [work-report](work-report/) | `/work-report` slash command that writes a standardized `WORK-REPORT.md` summary of the work done — in any repo, worktree or not | **into a target project** (`.claude/commands/` + a `.gitignore` entry) |
| [vscode-claude-tabs](vscode-claude-tabs/) | a VS Code keybinding (`Ctrl+Alt+W`) that opens a `claude` editor tab per git worktree | **user-global** (`~/.claude/scripts` + your VS Code `keybindings.json`) |

They complement each other but stand alone: `worktree-per-issue` creates and provisions the worktrees;
`vscode-claude-tabs` opens a `claude` session as an editor tab for each; `work-report` leaves a readable
summary of what a session did (handy for a coder→reviewer handoff, or resuming later). Use any alone or together.

## Install

**worktree-per-issue** — run from the root of the target git repo:

```sh
curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/worktree-per-issue/install.sh | sh
```

**work-report** — run from inside the target git repo:

```sh
curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/work-report/install.sh | sh
```

**vscode-claude-tabs** — run from inside any git repo:

```sh
curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/vscode-claude-tabs/install.sh | sh
```

See each tool's README for what it prompts for, requirements, and customization.

## Using them together

The tools stand alone, but one integration is worth wiring up.

**Refresh the `vscode-claude-tabs` binding whenever `worktree-per-issue` creates a worktree.**
`worktree-per-issue`'s `/worktree-create` uses plain `git worktree add` (then enters by path), so
Claude Code's native `open-worktree-terminal.sh` hook never fires. Instead, append this guarded block
after the provisioning steps in that tool's `scripts/worktree-setup.sh` (it runs on every worktree
create — via `post-checkout` and the `/worktree-create` provision step):

```sh
if [ -f "$HOME/.claude/scripts/gen-claude-tabs-keybinding.js" ]; then
  node "$HOME/.claude/scripts/gen-claude-tabs-keybinding.js" >/dev/null 2>&1 || true
fi
```

It's a no-op when `vscode-claude-tabs` isn't installed, and `|| true` keeps it from ever failing setup
(which runs under `set -e`). The generator re-reads the full `git worktree list`, so one refresh reflects
every worktree. Then press `Ctrl+Alt+W` — no window reload needed (VS Code hot-applies `keybindings.json`).

## Requirements

- `git` for all three; `worktree-per-issue` and `vscode-claude-tabs` also need `node`; `curl` + `tar` for the hosted one-liners.
- `vscode-claude-tabs` additionally needs VS Code with `claude` on your PATH.

## Repository layout

```text
worktree-toolbox/
├── worktree-per-issue/     # installs the /worktree-create /worktree-heal /worktree-remove toolbox into a project
│   ├── install.sh
│   ├── lib/merge.cjs
│   └── template/…
├── work-report/            # installs the /work-report command (WORK-REPORT.md) into a project
│   ├── install.sh
│   └── template/…
└── vscode-claude-tabs/     # installs the per-worktree claude-tabs keybinding generator
    ├── install.sh
    └── gen-claude-tabs-keybinding.js
```

Both installers accept `WORKTREE_TOOLBOX_REPO`, `WORKTREE_TOOLBOX_REF`, and `WORKTREE_TOOLBOX_SRC`
(a local source dir that skips the download) for testing and forks.

## Testing

`test/install-matrix.sh` is a smoke test that guards the "install any combination" promise: it
installs each of the 7 non-empty tool combinations into throwaway git repos and asserts they do
not collide (expected files land, no installer clobbers another's, `.gitignore` gets each entry
once, `vscode-claude-tabs` stays user-global, re-runs are idempotent). It runs fully offline
(installs from this checkout via `WORKTREE_TOOLBOX_SRC`) and fully sandboxed (never touches your
real `~/.claude` or VS Code config). Needs `git` + `node`:

```sh
sh test/install-matrix.sh
```
