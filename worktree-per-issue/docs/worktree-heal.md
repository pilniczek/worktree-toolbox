# `/worktree-heal` — heal a broken worktree

> Part of [worktree-per-issue](../README.md). Rebuilds a worktree's setup in place.

If a worktree is broken or stale (missing generated files, drifted deps),
`/worktree-heal [branch]` re-runs `scripts/worktree-setup.sh --force` in it. Omit the
name to heal the current one.

`--force` ignores the run-once marker, so it re-runs **all** setup steps regardless of
whether they ran before (see
[What the automatic setup does](../README.md#what-the-automatic-setup-does)).

```mermaid
flowchart TD
  start(["/worktree-heal [branch]"])
  start --> hasarg{"Branch name given?"}
  hasarg -->|"yes"| locate["Validate + derive flat name<br/>(confirm .claude/worktrees/&lt;flat&gt; exists — else STOP)"]
  hasarg -->|"no"| current["Target the CURRENT worktree<br/>(pwd must be inside one — else STOP and ask)"]
  locate --> movein["Move in if needed<br/>(EnterWorktree by path, unless already inside)"]
  movein --> heal
  current --> heal["sh scripts/worktree-setup.sh --force<br/>(ignore the run-once marker)"]
  heal --> nm["Relink node_modules<br/>(only if missing)"]
  nm --> steps["Re-run ALL provisioning steps<br/>(e.g. codegen — regardless of the marker)"]
  steps --> cfg["Copy any missing .worktreeinclude config"]
  cfg --> report(["Report what was rebuilt"])

  classDef step fill:#eaeaea,stroke:#888,color:#000;
  class start,hasarg,locate,current,movein,heal,nm,steps,cfg,report step;
```
