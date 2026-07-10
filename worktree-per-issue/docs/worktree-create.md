# `/worktree-create` — create a worktree for a branch

> Part of [worktree-per-issue](../README.md). Creates a git worktree under
> `.claude/worktrees/` for a branch, new **or** existing, and moves you into it.

The command is a thin wrapper: it runs `scripts/worktree-create.sh` (installed from
`template/scripts/worktree-create.sh`), which validates the name, fetches, resolves
new-vs-existing (git decides — nothing is guessed), creates the worktree and provisions
it, then prints `WORKTREE_PATH=<path>`. The one part a script can't do — relocating the
session into the worktree — stays with Claude: the command reads that path and calls
`EnterWorktree`.

## Flow

```mermaid
flowchart TD
  start(["/worktree-create &lt;full-branch-name&gt;"])
  start --> validate["Validate the name<br/>(must be a valid git branch name — else STOP and report)"]
  validate --> fetch["git fetch origin<br/>(refresh remote-tracking refs)"]
  fetch --> prune["git worktree prune<br/>(clear records of already-deleted worktrees)"]
  prune --> exists{"Branch exists?<br/>(local: rev-parse · origin: ls-remote)"}
  exists -->|"no"| createnew["git worktree add -b &lt;name&gt; … origin/HEAD<br/>(create a NEW branch off the fresh default branch)"]
  exists -->|"yes"| checkout["git worktree add … &lt;name&gt;<br/>(check out EXISTING; remote-only → tracking branch)"]
  createnew --> setup
  checkout --> setup
  setup["sh scripts/worktree-setup.sh<br/>(the script provisions the worktree; idempotent, marker-guarded)"]
  setup --> nm["node_modules<br/>(hardlink-copy of main's install — shared inodes, ~instant)"]
  nm --> steps["provisioning steps<br/>(your configured commands, e.g. codegen — run once)"]
  steps --> cfg[".worktreeinclude<br/>(copy gitignored local config from main)"]
  cfg --> report["Report NEW vs EXISTING + print WORKTREE_PATH<br/>(the loud after-the-fact safety net)"]
  report --> enter["EnterWorktree (by path)<br/>(the command moves THIS session in — and stay)"]
  enter --> ready(["Ready — you're now working inside the worktree"])

  classDef step fill:#eaeaea,stroke:#888,color:#000;
  classDef newc fill:#fff3cd,stroke:#e0a800,color:#000;
  classDef oldc fill:#cfe2ff,stroke:#3d7bd6,color:#000;
  class start,validate,fetch,prune,exists,setup,nm,steps,cfg,report,enter,ready step;
  class createnew newc;
  class checkout oldc;
```

Full flow, the new-vs-existing rules, and the diagram:
[Creating a worktree](../template/docs/worktrees.md#creating-a-worktree-worktree-create).
Pushing from the worktree: [Pushing](../template/docs/worktrees.md#pushing).
