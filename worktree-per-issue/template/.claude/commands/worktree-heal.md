---
description: Heal (re-provision) a worktree — force-re-runs the worktree setup
argument-hint: "full-branch-name (optional — omit to heal the current worktree)"
allowed-tools: Bash(cat:*), Bash(cd:*), Bash(sh:*)
---

Heal a worktree by force-re-running its setup (`scripts/worktree-setup.sh --force`), which rebuilds everything: it
relinks `node_modules` if missing and re-runs **every** configured provisioning step, ignoring the run-once marker. Use
this when a worktree is broken or stale (missing generated files, a half-finished setup, deps that drifted). Do these in
order; STOP and report if any step fails:

1. **Locate the worktree.**
   - If `$ARGUMENTS` is given, validate it (see **Validation**), derive the flat name (see **Flat name**), and confirm
     `.claude/worktrees/<flat>` exists. If it does not, STOP and tell me — use `/worktree-create` to create it first.
   - If `$ARGUMENTS` is empty, heal the **current** worktree. Confirm this session is inside one
     (`pwd` matches `*/.claude/worktrees/*`); if not, STOP and ask me which worktree to heal.

2. **Move in (only if needed).** If you located a worktree by name and this session is not already inside it,
   `EnterWorktree` with `path` `.claude/worktrees/<flat>` to relocate into it. If already inside the target, skip this.

3. **Heal.** From inside the worktree, run `sh scripts/worktree-setup.sh --force`. This re-runs all provisioning steps
   regardless of the run-once marker. Individual step failures are reported but do not abort the rest of the setup.

4. **Report.** Summarize what was rebuilt (and any step that failed and needs a manual re-run) and the worktree path.

---

!`cat "${CLAUDE_PROJECT_DIR:-.}/.claude/worktree-shared.md"`
