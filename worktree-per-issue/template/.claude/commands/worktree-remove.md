---
description: Close (remove) a worktree — deletes the dir, and the branch if it's merged
argument-hint: "branch name to close (from main); omit when run inside the worktree"
allowed-tools: Bash(git worktree *), Bash(git -C:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git check-ref-format:*)
---

Close a worktree: remove its directory and, if the branch is safely merged, delete the branch too. Removal is plain git
(`git worktree remove` + `git branch -d`) — Claude's native cleanup does not apply here (worktrees are created with
`git worktree add` and entered by path). Removal always runs against the **main checkout** via `git -C "<main>"`, so it
works no matter where you stand — including a separate Claude session started **directly inside** the worktree (which
has no `EnterWorktree` session to exit). The command has **two modes, chosen by where you run it**:

- **Inside a worktree** → closes **that** worktree; pass **no** argument.
- **In the main checkout** → closes the **named** worktree; you **must** pass its branch name.

Do **not** call `ExitWorktree` — it is a no-op in a session started inside the worktree (rather than relocated there by
`EnterWorktree`) and is unnecessary once removal runs from main. Do these in order; STOP and report if any step fails:

1. **Pick the mode from your location.**
   - **Inside a worktree** (`pwd` matches `*/.claude/worktrees/*`): if `$ARGUMENTS` is non-empty, STOP — tell me
     "You're inside a worktree: run `/worktree-remove` with no argument to close it, or run `/worktree-remove <branch>`
     from the main checkout to close a different one." Otherwise capture this worktree's `<flat>` (from `pwd`) and branch
     `<branch>` (`git rev-parse --abbrev-ref HEAD`).
   - **In the main checkout** (not inside a worktree): if `$ARGUMENTS` is empty, STOP — tell me "Run
     `/worktree-remove <branch>` to name the worktree to close, or run `/worktree-remove` from inside a worktree to close
     that one." Otherwise validate `$ARGUMENTS` (see **Validation**), derive the flat name (see **Flat name**), confirm
     `.claude/worktrees/<flat>` appears in `git worktree list`, and take `<branch>` as `$ARGUMENTS`. If it is not a live
     worktree, STOP and tell me.

2. **Find the main checkout `<main>`.** The first `worktree <path>` line of `git worktree list --porcelain` is always the
   primary checkout — take its path as `<main>`.

3. **Remove from main, in a single command.** Removal deletes the folder you may be standing in, so run removal +
   branch-delete + prune as **one** invocation — the shell is spawned while the folder still exists, and every git call
   is anchored to `<main>` so none depend on the shell's working directory:

   ```sh
   git -C "<main>" worktree remove "<main>/.claude/worktrees/<flat>" \
     && { git -C "<main>" branch -d "<branch>"; git -C "<main>" worktree prune; }
   ```

   - `git worktree remove` refuses if the worktree is dirty (uncommitted or untracked changes) — the `&&` then skips the
     rest; STOP and report the changes, do **not** pass `--force`.
   - `git branch -d` deletes only a branch already merged into your trunk (default branch); if git refuses (unmerged),
     **keep** the branch and report it — the commits are safe on that branch; delete it later after it merges, or with
     `git branch -D` yourself if you are sure. **Never** use `-D` automatically, and **never** delete the remote branch.
   - `git worktree prune` clears any stale bookkeeping (a no-op after a clean remove).

4. **Report** what was removed and whether the branch was **deleted** or **kept** (and why). If you ran this **inside**
   the worktree, its folder is now gone — if this session was started inside that worktree, its working directory no
   longer exists, so close it and continue from the main checkout. If you ran it from main, you are still in the main
   checkout.

---

{{WORKTREE_SHARED}}
