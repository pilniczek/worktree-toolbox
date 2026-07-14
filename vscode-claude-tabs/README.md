# vscode-claude-tabs

Open [Claude Code](https://claude.com/claude-code) as **editor-area terminal tabs** in VS Code - one
per git worktree - with a single keypress (`Ctrl+Alt+W`). Your normal `` Ctrl+` `` terminals stay in
the bottom panel.

> Part of [worktree-toolbox](../README.md). Installs USER-GLOBAL (`~/.claude/scripts` + your VS Code
> `keybindings.json`), not into a project.

If you run one worktree per issue (e.g. via Claude Code's native worktree support), this gives you a `claude` session per
worktree as real editor tabs you can arrange side by side or drag out into a floating window — instead
of a pile of native OS terminal windows.

## Why a keybinding (and not startup automation)

Editor-area terminals can only be created by VS Code itself, and the mechanics box you in:

- The `terminals` extension can't place a terminal in the editor area ([vscode#127515](https://github.com/microsoft/vscode/issues/127515)).
- The `code` CLI can't trigger a workbench command from a script.
- A `folderOpen` **task** *can* auto-open on startup, but task terminals only land in the editor area
  via the **global** `terminal.integrated.defaultLocation: "editor"` - which also sends every normal
  terminal to the editor area. Per-task location was requested and closed as *not planned*
  ([vscode#212070](https://github.com/microsoft/vscode/issues/212070)).

The one mechanism that opens a terminal in the editor area **without** the global flag is a **keybinding**
running `runCommands` → `workbench.action.createTerminalEditor` (+ `sendSequence`). That's what this
generates - the trade-off being it's on-demand (a keypress), not automatic on window open.

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

Under WSL the `text` is instead
`wsl.exe -d "<distro>" --cd "/path/to/main" -- bash -lic "claude"\r` - see [Requirements](#requirements)
for why.

It's **idempotent and self-migrating**: it replaces the binding it manages (detected by signature,
so changing the key removes the old one) and leaves your other keybindings untouched.

## Requirements

- Node.js
- VS Code, with `claude` on your PATH
- Works on WSL (targets the Windows-host `keybindings.json`, since keybindings are application-scoped
  and shared by the remote window), native Linux, macOS, and Windows. Under WSL the command is wrapped
  in `wsl.exe` so the chord also works from a **native-Windows** VS Code window, whose editor terminal
  is PowerShell/CMD and can't `cd` into a Linux path. `wsl.exe` is a console program, so it runs
  in-place inside the editor tab (not a separate window) and enters WSL from either shell type. This
  needs WSL interop enabled (`appendWindowsPath`, the default) so `wsl.exe` is reachable, and it runs
  `claude` under a login shell so your PATH (`~/.local/bin`, nvm, ...) is loaded.

## Install

Run from inside any git repo (worktree paths are read at generation time):

```sh
curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/vscode-claude-tabs/install.sh | sh
```

On native Windows, run this in **Git Bash** (not CMD/PowerShell). See the [toolbox README](../README.md#install).

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

If your worktrees are created by a tool that bypasses that native hook, wire the generator into its
per-worktree setup instead — see the [toolbox README](../README.md) for a ready-made recipe.

## Customize

Set env vars when running the generator or `install.sh`:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLAUDE_WT_KEY` | `ctrl+alt+w` | Keybinding chord |
| `CLAUDE_WT_COMMAND` | `claude` | Command run in each tab |
| `VSCODE_KEYBINDINGS_PATH` | auto-detected | Full path to `keybindings.json` |
| `INSTALL_DIR` | `~/.claude/scripts` | Where `install.sh` copies the generator |

## Caveats

- On a very slow machine the command may be typed before the new terminal finishes initializing; shells
  buffer input, so this is almost always fine.
- `keybindings.json` is application-scoped, so this repo's absolute worktree paths also exist in every
  VS Code window. Pressing the chord in another window just opens `claude` in those worktrees. Under
  WSL the paths are Linux paths, so the command is wrapped in `wsl.exe` to stay valid whether the
  window's terminal is PowerShell/CMD (native Windows) or bash (WSL Remote) — see Requirements.
- Under WSL, `claude` runs via a login+interactive shell (`bash -lic`); on some setups that prints a
  harmless `cannot set terminal process group` warning above the session.
