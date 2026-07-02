---
description: Create a git worktree for a branch (new or existing) and move into it — auto-detects which
argument-hint: <full-branch-name, e.g. feature/<initials>/<TICKET>/<slug>>
allowed-tools: Bash(cat:*), Bash(git worktree *), Bash(git fetch:*), Bash(git rev-parse:*), Bash(git ls-remote:*), Bash(sh:*)
---

Create a git worktree for `$ARGUMENTS` and relocate this session into it, per the worktree-per-issue flow (see
`docs/worktrees.md`). This one command handles **both** a brand-new branch and an existing one (local or already on the
remote) — git itself forces which, so nothing is guessed: you cannot create a branch that already exists, nor check out
one that does not. `$ARGUMENTS` is the FULL branch name exactly as you want it (real `/` separators, no spaces); nothing
is parsed, defaulted, or derived. Do these in order; STOP and report if any step fails:

1. **Validate** `$ARGUMENTS` (see **Validation** below).

2. **Preflight.** Run `git fetch origin` so remote-tracking refs are current — this is what lets a remote-only branch
   resolve, and what makes a freshly-created branch base on up-to-date trunk. Then run `git worktree prune` to clear
   records for any worktree folders that were already deleted. A tidy main window is good hygiene but not required.

3. **Resolve existence.** Check whether `$ARGUMENTS` already exists:
   - locally: `git rev-parse --verify --quiet "refs/heads/$ARGUMENTS"`
   - on the remote: `git ls-remote --exit-code --heads origin "$ARGUMENTS"`

4. **Create the worktree** at `.claude/worktrees/<flat>` (see **Flat name**). Exactly one action is valid:
   - **Neither exists → NEW branch:** `git worktree add -b "$ARGUMENTS" ".claude/worktrees/<flat>" origin/main`
     (bases the new branch on freshly-fetched trunk regardless of this window's state — use your repo's default branch if
     it is not `main`).
   - **Exists (local or remote) → EXISTING branch:** `git worktree add ".claude/worktrees/<flat>" "$ARGUMENTS"`
     (a remote-only branch makes git DWIM a local tracking branch). If git reports the branch is already checked out in
     another worktree, STOP and report.

5. **Move in.** `EnterWorktree` with `path` `.claude/worktrees/<flat>` to relocate THIS session into the new worktree, so
   you can start working there immediately. The worktree was created by plain `git worktree add`, so it persists on disk
   regardless of the session — do **not** `ExitWorktree`.

6. **Provision.** From inside the worktree, run `sh scripts/worktree-setup.sh` to set it up (see **Worktree setup**). With
   husky installed, `post-checkout` already ran this on the `git worktree add`; the run-once marker makes this a fast
   no-op. If a step fails, report it — the rest still completes.

7. **Report — loudly and exactly** which action was taken, so a typo or name collision is obvious immediately, and that
   you are now working inside the worktree:
   - NEW: "Branch not found on local/origin → created **NEW** branch `$ARGUMENTS` off trunk. You are now in the worktree,
     ready to work."
   - EXISTING: "Found `$ARGUMENTS` (local/remote) → checked out **EXISTING SHARED** branch (do **not** force-push or
     `git branch -D` it without coordinating). You are now in the worktree, ready to work."

   Report the worktree path too. To work on a **different** issue in parallel with its own isolated context, open a
   separate Claude session in that issue's worktree — not needed to work on this one.

**Pushing.** From the worktree, a NEW branch pushes with `git push -u origin HEAD` (creates `$ARGUMENTS` on the remote,
exact name). An EXISTING branch pushes with plain `git push` (tracking is already set). See `docs/worktrees.md` for the
full flow and cleanup.

---

!`cat "${CLAUDE_PROJECT_DIR:-.}/.claude/worktree-shared.md"`
