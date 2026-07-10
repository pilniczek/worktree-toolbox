---
description: Heal (re-provision) a worktree — force-re-runs the worktree setup. Use when a worktree is broken or stale - missing generated files, a half-finished setup, or drifted codegen.
argument-hint: "full-branch-name (optional — omit to heal the current worktree)"
allowed-tools: Bash(sh scripts/worktree-heal.sh*)
---

Run `sh scripts/worktree-heal.sh $ARGUMENTS` and relay its output to me verbatim.

The script locates the worktree (from `$ARGUMENTS` if given, otherwise the current one) and force-re-runs `scripts/worktree-setup.sh --force` inside it, rebuilding everything and ignoring the run-once marker. Individual provisioning-step failures are reported but do not abort the rest.

A **non-zero exit** means it stopped and printed why (not inside a worktree with no argument given, no such worktree, or setup failed). Relay that and stop. Do not run any git or setup yourself.
