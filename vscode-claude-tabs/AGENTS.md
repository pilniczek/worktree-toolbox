# vscode-claude-tabs — AGENTS.md

Tool-specific contributor notes for vscode-claude-tabs. General monorepo conventions (shared
installer rules, how to test, ADRs) live in the [root AGENTS.md](../AGENTS.md).

The key deviation from `worktree-per-issue`: this one installs **user-global**
(`~/.claude/scripts` + the user's VS Code `keybindings.json`), **not** into a target project. Its
installer and generator must never write into the repo they're run from. The generator edits
`keybindings.json` in place, so it must stay idempotent and self-migrating — replacing only the
binding it manages (detected by signature) and leaving every other keybinding untouched.

Under WSL the generator wraps each tab's command in `wsl.exe ... --cd ... -- bash -lic "<cmd>"`
rather than a bare `cd "<path>" && <cmd>`. This is deliberate, not redundant: the binding is written
to the Windows-host `keybindings.json` and shared with native-Windows windows, whose editor terminal
is PowerShell/CMD and can't `cd` into a Linux path. Don't "simplify" it back to a bare `cd`.

It introduces no domain vocabulary of its own.
