# vscode-claude-tabs

Open [Claude Code](https://claude.com/claude-code) as **editor-area terminal tabs** in VS Code — one
per git worktree — with a single keypress (`Ctrl+Alt+W`). Your normal `` Ctrl+` `` terminals stay in
the bottom panel.

> Part of [worktree-toolbox](../README.md). Installs USER-GLOBAL (`~/.claude/scripts` + your VS Code
> `keybindings.json`), not into a project.

If you run one worktree per issue (e.g. via Claude Code's `/worktree-create`), this gives you a `claude` session per
worktree as real editor tabs you can arrange side by side or drag out into a floating window — instead
of a pile of native OS terminal windows.

## Why a keybinding (and not startup automation)

Editor-area terminals can only be created by VS Code itself, and the mechanics box you in:

- The `terminals` extension can't place a terminal in the editor area ([vscode#127515](https://github.com/microsoft/vscode/issues/127515)).
- The `code` CLI can't trigger a workbench command from a script.
- A `folderOpen` **task** *can* auto-open on startup, but task terminals only land in the editor area
  via the **global** `terminal.integrated.defaultLocation: "editor"` — which also sends every normal
  terminal to the editor area. Per-task location was requested and closed as *not planned*
  ([vscode#212070](https://github.com/microsoft/vscode/issues/212070)).

The one mechanism that opens a terminal in the editor area **without** the global flag is a **keybinding**
running `runCommands` → `workbench.action.createTerminalEditor` (+ `sendSequence` to run the command).
That's what this generates. The trade-off: it's on-demand (a keypress), not automatic on window open.

## How it works

`gen-claude-tabs-keybinding.js` enumerates `git worktree list` and writes one keybinding into your VS
Code `keybindings.json`:

```jsonc
{
  "key": "ctrl+alt+w",
  "command": "runCommands",
  "args": { "commands": [
    "workbench.action.createTerminalEditor",
    { "command": "workbench.action.terminal.sendSequence",
      "args": { "text": "cd \"/path/to/main\" && claude\r" } }
    // ...one createTerminalEditor + sendSequence pair per worktree
  ]}
}
```

It's **idempotent and self-migrating**: it replaces the binding it manages (detected by signature, so
changing the key removes the old one) and leaves all your other keybindings untouched.

## Requirements

- Node.js
- VS Code, with `claude` on your PATH
- Works on WSL (targets the Windows-host `keybindings.json`, since keybindings are application-scoped
  and shared by the remote window), native Linux, macOS, and Windows.

## Install

Run from inside any git repo (worktree paths are read at generation time):

```sh
curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/vscode-claude-tabs/install.sh | sh
```

Or from a clone:

```sh
git clone https://github.com/pilniczek/worktree-toolbox
sh worktree-toolbox/vscode-claude-tabs/install.sh
```

This copies the generator to `~/.claude/scripts/`, runs it once (if you're in a git repo), and prints
next steps. Then **reload VS Code** and press `Ctrl+Alt+W`.

## Usage

- Press **`Ctrl+Alt+W`** → one editor-area terminal tab opens per worktree in the current window, each
  `cd`'d into its directory running `claude`. Drag a tab out of the editor to detach it into a floating
  window. (VS Code can't create terminals directly in another window — `createTerminalEditor` always
  targets the focused window — so opening straight into a new window isn't supported; see
  [vscode#201442](https://github.com/microsoft/vscode/issues/201442).)
- **When worktrees change**, re-run the generator so the binding reflects the new set:
  ```sh
  node ~/.claude/scripts/gen-claude-tabs-keybinding.js
  ```

### Auto-refresh with Claude Code's native worktrees

Claude Code's built-in worktree creation calls `~/.claude/scripts/open-worktree-terminal.sh` after creating a worktree.
Point it at the generator so the binding is refreshed automatically:

```sh
#!/usr/bin/env sh
exec node "$HOME/.claude/scripts/gen-claude-tabs-keybinding.js"
```

(A shell can't press the key for you, so afterwards you press `Ctrl+Alt+W` to open the tabs — the new worktree is now
included.)

### Auto-refresh with `worktree-per-issue`

If you use the sibling [`worktree-per-issue`](../worktree-per-issue/) tool, its `/worktree-create` creates worktrees
with plain `git worktree add` (then enters by path), so Claude's native worktree hook `open-worktree-terminal.sh` never
fires. Instead, wire the generator into that tool's `scripts/worktree-setup.sh` (which runs on every worktree create —
via `post-checkout` and the `/worktree-create` provision step), so the binding refreshes whenever a worktree is created.
Append this guarded block after the provisioning steps:

```sh
if [ -f "$HOME/.claude/scripts/gen-claude-tabs-keybinding.js" ]; then
  node "$HOME/.claude/scripts/gen-claude-tabs-keybinding.js" >/dev/null 2>&1 || true
fi
```

It's a no-op when this tool isn't installed, and `|| true` keeps it from ever failing setup (which runs
under `set -e`). The generator re-reads the full `git worktree list`, so one refresh reflects every
worktree. Then press `Ctrl+Alt+W` — no window reload needed (VS Code hot-applies `keybindings.json`).

## Customize

Set env vars when running the generator or `install.sh`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_WT_KEY` | `ctrl+alt+w` | Keybinding chord |
| `CLAUDE_WT_COMMAND` | `claude` | Command run in each tab |
| `VSCODE_KEYBINDINGS_PATH` | auto-detected | Full path to `keybindings.json` |

## Caveats

- On a very slow machine the command may be typed before the new terminal finishes initializing; shells
  buffer input, so this is almost always fine.
- `keybindings.json` is application-scoped, so this repo's absolute worktree paths also exist in other
  VS Code windows (harmless — pressing the chord elsewhere just `cd`s into those paths).
