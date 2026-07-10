#!/usr/bin/env sh
# Heal (re-provision) a worktree: force-re-run its setup (`worktree-setup.sh --force`), which ignores
# the run-once marker and rebuilds everything. Two modes: pass a branch name to heal that worktree,
# or omit it to heal the current one. Full narrative: docs/worktrees.md.

. "$(dirname "$0")/worktree-common.sh"
MAIN="$(wt_main_or_die)" || exit 1

ARG="${1:-}"

# --- locate worktree -----------------------------------------------------------------------
if [ -n "$ARG" ]; then
  wt_validate "$ARG" || exit 1
  FLAT="$(wt_flat "$ARG")"
  if ! wt_assert_live "$MAIN" "$FLAT"; then
    wt_warn "No live worktree at .claude/worktrees/$FLAT for branch '$ARG' — create it first with /worktree-create."
    exit 1
  fi
else
  if ! wt_inside_worktree; then
    wt_warn "Not inside a worktree: run /worktree-heal <branch> to name the one to heal."
    exit 1
  fi
  FLAT="$(wt_flat_from_path "$PWD")"
fi
WT="$MAIN/.claude/worktrees/$FLAT"

# Run the MAIN checkout's setup with the worktree as cwd (see worktree-create.sh) — heal means
# "rebuild with the current setup", so the latest install-templated copy is what we want.
wt_say "Healing worktree: $WT"
if ( cd "$WT" && sh "$MAIN/scripts/worktree-setup.sh" --force ); then
  wt_say "Done — re-provisioned $WT (any per-step failures are reported above; re-run them manually if needed)."
else
  wt_warn "Setup reported a failure (see above). The worktree still exists; fix the failing step and re-run /worktree-heal."
  exit 1
fi
