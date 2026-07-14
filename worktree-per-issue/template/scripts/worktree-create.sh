#!/usr/bin/env sh
# Create a git worktree for a branch (new or existing) under .claude/worktrees/<flat> and provision
# it. git itself forces new-vs-existing, so nothing is guessed. This script never enters the worktree
# — relocating the Claude session is not a shell operation; the caller does it (EnterWorktree).
# Full narrative: docs/worktrees.md.

. "$(dirname "$0")/worktree-common.sh"
MAIN="$(wt_main_or_die)" || exit 1

ARG="${1:-}"

# --- validate ------------------------------------------------------------------------------
if [ -z "$ARG" ]; then  # NOSONAR: POSIX sh
  wt_warn "Run /worktree-create <full-branch-name>, e.g. feature/<initials>/<TICKET>/<slug>."
  exit 1
fi
wt_validate "$ARG" || exit 1
FLAT="$(wt_flat "$ARG")"
WT="$MAIN/.claude/worktrees/$FLAT"

# --- preflight -----------------------------------------------------------------------------
git -C "$MAIN" fetch origin >/dev/null 2>&1 || wt_warn "warn: 'git fetch origin' failed; continuing with local refs."
git -C "$MAIN" worktree prune

# --- resolve -------------------------------------------------------------------------------
EXISTS=0
if git -C "$MAIN" rev-parse --verify --quiet "refs/heads/$ARG" >/dev/null 2>&1; then
  EXISTS=1
elif git -C "$MAIN" ls-remote --exit-code --heads origin "$ARG" >/dev/null 2>&1; then
  EXISTS=1
fi

# --- create --------------------------------------------------------------------------------
if [ "$EXISTS" = 0 ]; then  # NOSONAR: POSIX sh
  # NEW branch: base it on freshly-fetched trunk, resolved (not assumed) from the remote.
  BASE="$(git -C "$MAIN" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
  if ! err="$(git -C "$MAIN" worktree add -b "$ARG" "$WT" "$BASE" 2>&1)"; then
    wt_warn "STOP — could not create the worktree:"
    wt_warn "$err"
    exit 1
  fi
  ACTION=NEW
else
  # EXISTING branch (local or remote; a remote-only branch makes git DWIM a tracking branch).
  if ! err="$(git -C "$MAIN" worktree add "$WT" "$ARG" 2>&1)"; then
    wt_warn "STOP — could not create the worktree (is the branch already checked out elsewhere?):"
    wt_warn "$err"
    exit 1
  fi
  ACTION=EXISTING
fi

# Provision by running the MAIN checkout's setup script with the worktree as cwd — so it works even
# when the branch predates the toolbox install, and always uses the latest install-templated copy
# (setup.sh keys off pwd + git-common-dir, not off its own location). Idempotent, marker-guarded.
( cd "$WT" && sh "$MAIN/scripts/worktree-setup.sh" ) || wt_warn "warn: provisioning reported a failure (see above); the worktree still exists."

# The WORKTREE_PATH line is machine-read by the caller to EnterWorktree.
wt_say "WORKTREE_PATH=$WT"
if [ "$ACTION" = NEW ]; then  # NOSONAR: POSIX sh
  wt_say "Branch not found on local/origin → created NEW branch '$ARG' off trunk ($BASE)."
else
  wt_say "Found '$ARG' (local/remote) → checked out EXISTING SHARED branch (do NOT force-push or 'git branch -D' it without coordinating)."
fi
