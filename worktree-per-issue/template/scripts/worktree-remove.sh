#!/usr/bin/env sh
# Close (remove) a worktree: remove its directory and, if the branch is safely merged, delete the
# branch too. Plain git — never --force, never `git branch -D`, never the remote. Mode is chosen by
# where you run it: inside a worktree closes THIS one (no argument); in the main checkout closes the
# NAMED one (pass its branch). Full narrative: docs/worktrees.md.

# Re-exec guard: removal deletes the worktree directory — including this script file when run from
# inside it. On Windows/MSYS an open file blocks its own deletion, so `git worktree remove` would
# fail to clear the dir. Re-exec the MAIN checkout's copy (never removed) and cd there, so the
# running script never sits inside the directory being deleted. WT_ORIGIN_PWD carries the original
# location forward for mode detection.
. "$(dirname "$0")/worktree-common.sh"           # sourced on both the pre- and post-re-exec run
MAIN="$(wt_main_or_die)" || exit 1               # needed here to locate the re-exec target below;
                                                 # the re-execed process recomputes it (cheap, location-independent)
if [ "${WT_REEXEC:-0}" != 1 ]; then  # NOSONAR: POSIX sh
  WT_ORIGIN_PWD="$PWD" WT_REEXEC=1 exec sh "$MAIN/scripts/worktree-remove.sh" "$@"
fi
cd "$MAIN" || exit 1                              # leave the (to-be-deleted) worktree cwd

ARG="${1:-}"

# --- mode ----------------------------------------------------------------------------------
if wt_inside_worktree; then
  if [ -n "$ARG" ]; then  # NOSONAR: POSIX sh
    wt_warn "You're inside a worktree: run /worktree-remove with no argument to close it, or run"
    wt_warn "/worktree-remove <branch> from the main checkout to close a different one."
    exit 1
  fi
  FLAT="$(wt_flat_from_path "$WT_ORIGIN_PWD")"
  WT="$MAIN/.claude/worktrees/$FLAT"
  BRANCH="$(git -C "$WT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
else
  if [ -z "$ARG" ]; then  # NOSONAR: POSIX sh
    wt_warn "Run /worktree-remove <branch> to name the worktree to close, or run /worktree-remove"
    wt_warn "from inside a worktree to close that one."
    exit 1
  fi
  wt_validate "$ARG" || exit 1
  FLAT="$(wt_flat "$ARG")"
  if ! wt_assert_live "$MAIN" "$FLAT"; then
    wt_warn "No live worktree at .claude/worktrees/$FLAT for branch '$ARG' (see 'git worktree list')."
    exit 1
  fi
  BRANCH="$ARG"
  WT="$MAIN/.claude/worktrees/$FLAT"
fi

# --- remove --------------------------------------------------------------------------------
# Git for Windows deletes through a junction, emptying main's linked directory.
if ! wt_setup_cjs "$MAIN" unlink "$WT"; then
  wt_warn "STOP - could not drop the worktree's links, so it was not removed. Run /worktree-heal to restore any it dropped."
  exit 1
fi
# Git localizes its messages; the refusal is classified by its English text.
if ! err="$(LC_ALL=C git -C "$MAIN" worktree remove "$WT" 2>&1)"; then
  wt_setup_cjs "$MAIN" relink "$WT" >&2 \
    || wt_warn "warn: could not restore the worktree's links (see above); run /worktree-heal to retry."
  wt_warn "STOP - could not remove the worktree (not forcing):"
  wt_warn "$err"
  wt_warn "Changes in $WT (none if empty):"
  git -C "$WT" status --short >&2 2>/dev/null || true
  case "$err" in
    *"cannot remove a locked working tree"*)
      wt_warn "The worktree is locked. Unlock it, then retry /worktree-remove:"
      wt_warn "  git -C $(sh_quote "$MAIN") worktree unlock $(sh_quote "$WT")" ;;
    *"containing submodules"*)
      wt_warn "Git refuses any worktree with an initialized submodule, even a clean one."
      wt_warn "--force would delete this worktree's copy of each submodule repository, including"
      wt_warn "commits never pushed, and every change listed above."
      wt_warn "Check the submodules too (empty output for every submodule = nothing to lose there):"
      wt_warn "  git -C $(sh_quote "$WT") submodule foreach --recursive 'git status --short; git stash list; git log --oneline HEAD --branches --not --remotes'"
      wt_warn "Then, if sure, run these in order (drop the links first, or --force on Git for Windows"
      wt_warn "empties the main checkout's linked directories):"
      wt_warn "  node $(sh_quote "$MAIN/scripts/worktree-setup.cjs") unlink $(sh_quote "$WT")"
      wt_warn "  git -C $(sh_quote "$MAIN") worktree remove --force $(sh_quote "$WT")"
      if [ -n "$BRANCH" ] && [ "$BRANCH" != HEAD ]; then  # NOSONAR: POSIX sh
        wt_warn "  git -C $(sh_quote "$MAIN") branch -d $(sh_quote "$BRANCH")"
      fi
      wt_warn "Do not rerun /worktree-remove afterwards: with the worktree gone it stops with \"No live worktree\"." ;;
    *"modified or untracked files"*)
      wt_warn "Uncommitted or untracked changes are listed above. Commit or stash them (or remove with --force yourself if you're sure), then retry." ;;
    *) ;;
  esac
  exit 1
fi

# --- branch --------------------------------------------------------------------------------
# A worktree on a detached HEAD has no branch to delete (rev-parse yields the literal 'HEAD', or
# empty on failure) — skip the delete rather than mislabel 'HEAD' as an unmerged branch.
if [ -z "$BRANCH" ] || [ "$BRANCH" = HEAD ]; then  # NOSONAR: POSIX sh
  BRANCH_RESULT=detached
elif git -C "$MAIN" branch -d "$BRANCH" >/dev/null 2>&1; then
  BRANCH_RESULT=deleted
else
  BRANCH_RESULT=kept
fi
git -C "$MAIN" worktree prune

# --- report --------------------------------------------------------------------------------
wt_say "Removed worktree: $WT"
case "$BRANCH_RESULT" in
  detached)
    wt_say "The worktree was on a detached HEAD → no branch to delete." ;;
  deleted)
    wt_say "Branch '$BRANCH' was merged into trunk → deleted." ;;
  kept)
    wt_say "Branch '$BRANCH' is NOT merged → KEPT (commits are safe). Delete it later with"
    wt_say "  git branch -d $(sh_quote "$BRANCH")   (after it merges)   or   git branch -D $(sh_quote "$BRANCH")   (if you're sure)."
    wt_say "The remote branch was not touched." ;;
  *) ;;   # detached/deleted/kept above are exhaustive; defensive default (S131)
esac
if wt_inside_worktree; then
  wt_say "You ran this from inside the worktree — its folder is now gone. If this session was"
  wt_say "started inside it, close it and continue from the main checkout: $MAIN"
fi
