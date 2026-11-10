# 0001 - `/worktree-remove` never forces removal

**Status:** accepted, 2026-11-10

## Context

`git worktree remove` refuses a worktree that is locked, dirty, or holds an initialized submodule. Git
refuses the submodule case even when everything is clean. An initialized submodule keeps its object
store in the worktree's admin dir (`.git/worktrees/<flat>/modules/<name>`, keyed by submodule name), so `--force` deletes any
submodule commit that was never pushed.

No repo using the toolbox has submodules today.

## Decision

`worktree-remove.sh` diagnoses and never acts. It names the refusal from git's `LC_ALL=C` message
and prints the checks and manual commands. It never runs `--force` or `git submodule deinit`, and it
never deletes `modules/` or gitlink files.

## Rejected

Clearing submodule state automatically, then removing. No repo needs it, and it deletes data on the
toolbox's own judgement.

## Reopen when

A repo needs submodules in its worktrees day to day, so the manual steps become routine.
