# `/worktree-heal` — heal a broken worktree

> Part of [worktree-per-issue](../README.md). Rebuilds a worktree's setup in place when
> it's broken or stale (missing generated files, drifted deps).

The command is a thin wrapper: it runs `scripts/worktree-heal.sh` (installed from
`template/scripts/worktree-heal.sh`) and relays its output. The script locates the target
worktree (from the branch name, or the current one if none is given) and force-re-runs
`scripts/worktree-setup.sh --force` inside it — `--force` ignores the run-once marker so
**all** setup steps run again.

## Flow

```mermaid
flowchart TD
  start(["/worktree-heal [branch]"])
  start --> hasarg{"Branch name given?"}
  hasarg -->|"yes"| locate["Validate + derive flat name<br/>(confirm .claude/worktrees/&lt;flat&gt; is live — else STOP)"]
  hasarg -->|"no"| current["Target the CURRENT worktree<br/>(pwd must be inside one — else STOP and ask)"]
  locate --> heal
  current --> heal["( cd &lt;worktree&gt; && sh scripts/worktree-setup.sh --force )<br/>(run setup from inside it — no session move; ignore the run-once marker)"]
  heal --> nm["Relink node_modules<br/>(only if missing)"]
  nm --> steps["Re-run ALL provisioning steps<br/>(e.g. codegen — regardless of the marker)"]
  steps --> cfg["Copy any missing .worktreeinclude config"]
  cfg --> report(["Report what was rebuilt"])

  classDef step fill:#eaeaea,stroke:#888,color:#000;
  class start,hasarg,locate,current,heal,nm,steps,cfg,report step;
```

Full flow and the diagram:
[Healing a worktree](../template/docs/worktrees.md#healing-a-worktree-worktree-heal).
What the setup rebuilds:
[What the automatic setup does](../template/docs/worktrees.md#what-the-automatic-setup-does).
