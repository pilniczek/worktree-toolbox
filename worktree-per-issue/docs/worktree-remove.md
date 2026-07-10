# `/worktree-remove` — close a worktree

> Part of [worktree-per-issue](../README.md). Removes a worktree and, if the branch is
> safely merged, deletes it too.

The command is a thin wrapper: it runs `scripts/worktree-remove.sh` (installed from
`template/scripts/worktree-remove.sh`) and relays its output. The script re-execs the main
checkout's copy of itself before removing anything, so the running script never sits inside
the directory being deleted (matters on Windows, where an open file blocks its own removal).
Removal always runs against the main checkout via `git -C`, so it works from anywhere and
never needs `ExitWorktree`.

## From inside the worktree — `/worktree-remove`

```mermaid
flowchart TD
  start(["/worktree-remove<br/>(run inside the worktree — no branch arg)"])
  start --> inside{"Inside a worktree?"}
  inside -->|"no"| stopA["STOP — nothing to close here<br/>(use /worktree-remove &lt;branch&gt; from main)"]
  inside -->|"yes"| capture["Capture flat + branch from pwd"]
  capture --> findmain["Find main checkout &lt;main&gt;<br/>(first entry of git worktree list)"]
  findmain --> removedir["git -C &lt;main&gt; worktree remove &lt;main&gt;/.claude/worktrees/&lt;flat&gt;<br/>(refuses if the working tree is dirty)"]

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
    prune --> report(["Report: dir removed · branch deleted/kept · worktree folder gone (if the session was started inside it, close it)"])
  end

  removedir --> clean

  classDef step fill:#eaeaea,stroke:#888,color:#000;
  classDef stop fill:#f8d7da,stroke:#d9534f,color:#000;
  class start,inside,capture,findmain,removedir,clean,delbranch,merged,gone,prune,report step;
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
  live -->|"yes"| removedir["git -C &lt;main&gt; worktree remove &lt;main&gt;/.claude/worktrees/&lt;flat&gt;"]
  removedir --> rest["Continue in the shared tail of /worktree-remove above<br/>(clean? → git branch -d → merged? → prune → report)"]

  classDef step fill:#eaeaea,stroke:#888,color:#000;
  classDef stop fill:#f8d7da,stroke:#d9534f,color:#000;
  classDef ref fill:#cfe2ff,stroke:#3d7bd6,color:#000;
  class start,validate,live,removedir step;
  class stopB stop;
  class rest ref;
```

Full flow (both modes), the never-`--force`/never-`-D` safety rules, the
manual fallback, and the shared-branch caution: [Cleanup](../template/docs/worktrees.md#cleanup).
