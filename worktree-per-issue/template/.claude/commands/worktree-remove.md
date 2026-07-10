---
description: Close (remove) a worktree — deletes the dir, and the branch if it's merged. Use when finished with an issue and ready to clean up its worktree.
argument-hint: "branch name to close (from main); omit when run inside the worktree"
allowed-tools: Bash(sh scripts/worktree-remove.sh*)
---

Run `sh scripts/worktree-remove.sh $ARGUMENTS` and relay its output to me verbatim.

The script does everything: it picks the mode from where you're standing (inside a worktree → closes that one with no argument; in the main checkout → closes the named `$ARGUMENTS`), validates the name, removes the directory (refuses if dirty — never `--force`), deletes the branch only if it's merged (keeps and reports it otherwise — never `-D`, never the remote), and prunes.

- A **non-zero exit** means it stopped and printed why (wrong mode, dirty worktree, not a live worktree). Relay that message and stop.
- Do **not** run any git yourself, do **not** call `ExitWorktree`, and do **not** question or reformat the branch name — the script and its after-the-fact report are the safety net.
