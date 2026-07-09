# `/worktree-remove` — close a worktree

> Part of [worktree-per-issue](../README.md). Removes a worktree and, if safe,
> deletes its branch.

Claude's native worktree auto-cleanup does not apply here — `ExitWorktree` won't
remove a worktree created with `git worktree add` and entered by path, so it's a
no-op on ours (by design). Closing is explicit.

`/worktree-remove` has two modes, chosen by where you run it:

- **inside a worktree** — run `/worktree-remove` (no argument) to close _that_ one. It
  steps back to main first (git won't remove the tree you're in).
- **from the main checkout** — run `/worktree-remove <branch>` to close a named one.

The wrong combination (an argument inside a worktree, or none from main) stops with a
hint. It runs `git worktree remove` (refuses if the worktree is dirty), then
`git branch -d`, which deletes the branch **only if it's merged into your trunk**. An
unmerged branch is kept and reported, so no commits are ever lost. It never
force-removes, never uses `git branch -D`, and never touches the remote.

## From inside the worktree — `/worktree-remove`

```mermaid
flowchart TD
  start(["/worktree-remove<br/>(run inside the worktree — no branch arg)"])
  start --> inside{"Inside a worktree?"}
  inside -->|"no"| stopA["STOP — nothing to close here<br/>(use /worktree-remove &lt;branch&gt; from main)"]
  inside -->|"yes"| capture["Capture flat + branch from pwd"]
  capture --> exitwt["ExitWorktree action=keep<br/>(return to main — can't remove the tree you occupy)"]
  exitwt --> removedir["git worktree remove .claude/worktrees/&lt;flat&gt;<br/>(refuses if the working tree is dirty)"]

  subgraph shared["shared below"]
    direction TB
    clean{"Working tree clean?"}
    clean -->|"no"| stopdirty["STOP — report changes, keep the dir<br/>(no --force; commit or stash first)"]
    clean -->|"yes"| delbranch["git branch -d &lt;branch&gt;<br/>(deletes only if merged into trunk)"]
    delbranch --> merged{"Merged into trunk?"}
    merged -->|"yes"| gone["Branch deleted"]
    merged -->|"no"| kept["Branch KEPT and reported<br/>(commits safe; never -D, never the remote)"]
    gone --> prune["git worktree prune"]
    kept --> prune
    prune --> report(["Report: dir removed · branch deleted/kept · now in main"])
  end

  removedir --> clean

  classDef step fill:#eaeaea,stroke:#888,color:#000;
  classDef stop fill:#f8d7da,stroke:#d9534f,color:#000;
  class start,inside,capture,exitwt,removedir,clean,delbranch,merged,gone,prune,report step;
  class stopA,stopdirty,kept stop;
  style shared fill:#eef4ff,stroke:#3d7bd6;
```

## From the main checkout — `/worktree-remove <branch>`

```mermaid
flowchart TD
  start(["/worktree-remove &lt;branch&gt;<br/>(run from the main checkout)"])
  start --> validate["Validate the branch name + derive flat<br/>(must be a valid git branch name)"]
  validate --> live{"A live worktree?<br/>(shows in git worktree list)"}
  live -->|"no"| stopB["STOP — not a live worktree"]
  live -->|"yes"| removedir["git worktree remove .claude/worktrees/&lt;flat&gt;"]
  removedir --> rest["Continue in the shared tail of /worktree-remove above<br/>(clean? → git branch -d → merged? → prune → report)"]

  classDef step fill:#eaeaea,stroke:#888,color:#000;
  classDef stop fill:#f8d7da,stroke:#d9534f,color:#000;
  classDef ref fill:#cfe2ff,stroke:#3d7bd6,color:#000;
  class start,validate,live,removedir step;
  class stopB stop;
  class rest ref;
```

## Automatic prune (safe)

`/worktree-create` (and the setup script when run from main) runs `git worktree
prune`, which only removes records for folders that are **already gone** — never a
live worktree or a branch. So a folder you delete by hand clears its stale `git
worktree list` entry next time. You can also run it yourself.

## Manual fallback

The same steps by hand:

```sh
git worktree list                                 # review worktrees + their branches
git worktree remove .claude/worktrees/<flat>      # drop a finished worktree's dir (refuses if dirty)
git branch --merged main                          # branches fully merged into trunk — safe to delete
git branch -d feature/<initials>/<ISSUE>/<slug>   # -d refuses to delete anything unmerged
```

Use `git worktree remove --force` only when the uncommitted changes can be thrown
away, and `git branch -D` only for an unmerged branch you know you don't need.

## Shared branches

A worktree checked out from an existing branch is often on a colleague's branch. `git
branch -d` (and `/worktree-remove`) only delete your **local** copy and never touch
the remote. Still, never force-push or `git branch -D` someone else's branch without
asking first.
