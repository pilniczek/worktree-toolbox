---
description: Create a git worktree for a branch (new or existing) and move into it — auto-detects which. Use when starting work on a ticket or issue on its own branch, isolated from the main checkout. Also use it with `--repo <path>` when the work needs a worktree in another repo - never run a bare `git worktree add` there.
argument-hint: <full-branch-name, e.g. feature/<initials>/<TICKET>/<slug>> [--repo <path-to-other-repo>]
allowed-tools: Bash(sh scripts/worktree-create.sh*), EnterWorktree
---

Create a worktree for `$ARGUMENTS` and relocate this session into it. Two steps:

1. Run `sh scripts/worktree-create.sh $ARGUMENTS`. The script validates the name, fetches, resolves whether the branch is new or existing (git decides — nothing is guessed), runs `git worktree add`, and provisions the worktree. On success its last lines are a `WORKTREE_PATH=<path>` line and a NEW/EXISTING report.
   - A **non-zero exit** means it stopped and printed why (invalid name, branch already checked out elsewhere, …). Relay that and stop — do **not** continue to step 2.
   - With `--repo`, the worktree is in another repo: skip step 2 (no `EnterWorktree`, this session stays here and works there by path). Relay the output verbatim, including any `MINIMAL WORKTREE:` lines. One `--repo` per call; for several repos, run the command once per repo.

2. Take the path from the `WORKTREE_PATH=` line and call `EnterWorktree` with that `path` to move this session into the worktree, so you can start working there right away. The worktree was created by plain `git worktree add`, so it persists regardless of the session — do **not** `ExitWorktree`. Then relay the script's NEW/EXISTING report verbatim.

Do not run any git yourself and do not question or reformat the branch name — the script and its after-the-fact report are the safety net. To work on a **different** issue in parallel with its own isolated context, open a separate Claude session in that worktree's directory (not needed to work on this one). See `docs/worktrees.md` for the full flow.
