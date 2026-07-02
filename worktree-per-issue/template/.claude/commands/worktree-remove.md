---
description: Close (remove) a worktree — deletes the dir, and the branch if it's merged
argument-hint: "branch name to close (from main); omit when run inside the worktree"
allowed-tools: Bash(cat:*), Bash(git worktree *), Bash(git branch:*), Bash(git rev-parse:*)
---

Close a worktree: remove its directory and, if the branch is safely merged, delete the branch too. Removal is plain git
(`git worktree remove` + `git branch -d`) — Claude's native cleanup does not apply here (worktrees are created with
`git worktree add` and entered by path). git refuses to remove the worktree you are standing in, so the command has **two
modes, chosen by where you run it**:

- **Inside a worktree** → closes **that** worktree; pass **no** argument.
- **In the main checkout** → closes the **named** worktree; you **must** pass its branch name.

Do these in order; STOP and report if any step fails:

1. **Pick the mode from your location.**
   - **Inside a worktree** (`pwd` matches `*/.claude/worktrees/*`): if `$ARGUMENTS` is non-empty, STOP — tell me
     "You're inside a worktree: run `/worktree-remove` with no argument to close it, or run `/worktree-remove <branch>`
     from the main checkout to close a different one." Otherwise capture this worktree's `<flat>` (from `pwd`) and branch
     (`git rev-parse --abbrev-ref HEAD`), then `ExitWorktree` with `action` `keep` to return to the main checkout — you
     cannot remove the worktree you occupy.
   - **In the main checkout** (not inside a worktree): if `$ARGUMENTS` is empty, STOP — tell me "Run
     `/worktree-remove <branch>` to name the worktree to close, or run `/worktree-remove` from inside a worktree to close
     that one." Otherwise validate `$ARGUMENTS` (see **Validation**), derive the flat name (see **Flat name**), confirm
     `.claude/worktrees/<flat>` appears in `git worktree list`, and take the branch as `$ARGUMENTS`. If it is not a live
     worktree, STOP and tell me.

2. **Remove the directory.** `git worktree remove ".claude/worktrees/<flat>"`. If git refuses because the worktree is
   dirty (uncommitted or untracked changes), STOP and report the changes — do **not** pass `--force`.

3. **Delete the branch if merged.** `git branch -d "<branch>"`. `-d` deletes only a branch already merged into your trunk
   (default branch); if git refuses (unmerged), **keep** the branch and report it — the commits are safe on that branch;
   delete it later after it merges, or with `git branch -D` yourself if you are sure. **Never** use `-D` automatically,
   and **never** delete the remote branch (for a shared branch the local ref simply stays if unmerged).

4. **Prune.** Run `git worktree prune` to clear any stale bookkeeping (a no-op after a clean remove).

5. **Report** what was removed, whether the branch was **deleted** or **kept** (and why), and that the session is now in
   the main checkout.

---

!`cat "${CLAUDE_PROJECT_DIR:-.}/.claude/worktree-shared.md"`
