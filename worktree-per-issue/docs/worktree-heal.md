# `/worktree-heal` — heal a broken worktree

> Part of [worktree-per-issue](../README.md). Re-runs a worktree's setup steps and adds
> missing entries when it's broken or stale (missing generated files, drifted deps).

The command is a thin wrapper: it runs `scripts/worktree-heal.sh` (installed from
`template/scripts/worktree-heal.sh`) and relays its output. The script locates the target
worktree (from the branch name, or the current one if none is given) and force-re-runs
`scripts/worktree-setup.cjs setup <worktree> --force` — `--force` ignores the run-once marker so
**all** setup steps run again, and missing entries are added. A failed step or entry does not
stop the rest, but the heal then exits non-zero.

## Flow

```mermaid
flowchart TD
  start(["/worktree-heal [branch]"])
  start --> hasarg{"Branch name given?"}
  hasarg -->|"yes"| locate["Validate + derive flat name<br/>(confirm .claude/worktrees/&lt;flat&gt; is live — else STOP)"]
  hasarg -->|"no"| current["Target the CURRENT worktree<br/>(pwd must be inside one — else STOP and ask)"]
  locate --> heal
  current --> heal["node scripts/worktree-setup.cjs setup &lt;worktree&gt; --force<br/>(no session move; ignore the run-once marker)"]
  heal --> nm["Recreate missing copy / hardlink / link entries"]
  nm --> steps["Re-run ALL steps<br/>(e.g. codegen - regardless of the marker)"]
  steps --> report(["Report the result"])

  classDef step fill:#eaeaea,stroke:#888,color:#000;
  class start,hasarg,locate,current,heal,nm,steps,report step;
```

Full flow and the diagram:
[Healing a worktree](../template/docs/worktrees.md#healing-a-worktree-worktree-heal).
What the setup does:
[What the automatic setup does](../template/docs/worktrees.md#what-the-automatic-setup-does).
