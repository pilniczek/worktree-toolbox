#!/usr/bin/env sh
# Create a git worktree for a branch (new or existing) under .claude/worktrees/<flat> and provision
# it. git itself forces new-vs-existing, so nothing is guessed. This script never enters the worktree
# — relocating the Claude session is not a shell operation; the caller does it (EnterWorktree).
# Full narrative: docs/worktrees.md.

. "$(dirname "$0")/worktree-common.sh"
MAIN="$(wt_main_or_die)" || exit 1

usage() {
  wt_warn "Run /worktree-create <full-branch-name> [--repo <path-to-other-repo>], e.g. feature/<initials>/<TICKET>/<slug>."
  return 0
}

resolve_repo() {
  local repo="$1" target
  case "$repo" in
    /*) ;;
    *) repo="$MAIN/$repo" ;;
  esac
  target="$(wt_main "$repo" 2>/dev/null)"
  if [ -z "$target" ]; then  # NOSONAR: POSIX sh
    wt_warn "STOP - '$repo' is not inside a git repo."
    return 1
  fi
  if [ "$(cd "$target" && pwd -P)" = "$(cd "$MAIN" && pwd -P)" ]; then  # NOSONAR: POSIX sh
    wt_warn "STOP - '$repo' is this repo. Drop --repo to create the worktree here."
    return 1
  fi
  if [ "$(git -C "$target" rev-parse --is-bare-repository)" = true ]; then  # NOSONAR: POSIX sh
    wt_warn "STOP - '$repo' is a bare repo. Create its worktree by hand, by its own layout."
    return 1
  fi
  printf '%s' "$target"
  return 0
}

hand_off() {
  local target="$1" branch="$2"
  if [ ! -f "$target/scripts/worktree-create.sh" ]; then  # NOSONAR: POSIX sh
    wt_warn "STOP - '$target' has .claude/worktree.json but no scripts/worktree-create.sh. Reinstall the toolbox there."
    return 1
  fi
  ( cd "$target" && sh scripts/worktree-create.sh "$branch" )
  return $?
}

sh_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
  return 0
}

branch_exists() {  # local branch or on origin
  local main="$1" branch="$2"
  git -C "$main" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null 2>&1 \
    || git -C "$main" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
  return $?
}

# Adds worktree $3 for branch $2 in the repo whose main checkout is $1. Prints the report lines for
# the caller to show last; the WORKTREE_PATH line is machine-read by the caller to EnterWorktree.
add_worktree() {
  local main="$1" branch="$2" wt="$3" base err
  git -C "$main" fetch origin >/dev/null 2>&1 || wt_warn "warn: 'git fetch origin' failed; continuing with local refs."
  git -C "$main" worktree prune

  if branch_exists "$main" "$branch"; then
    # EXISTING branch (local or remote; a remote-only branch makes git DWIM a tracking branch).
    if ! err="$(git -C "$main" -c core.hooksPath=/dev/null worktree add "$wt" "$branch" 2>&1)"; then
      wt_warn "STOP — could not create the worktree (is the branch already checked out elsewhere?):"
      wt_warn "$err"
      return 1
    fi
    wt_say "WORKTREE_PATH=$wt"
    wt_say "Found '$branch' (local/remote) → checked out EXISTING SHARED branch (do NOT force-push or 'git branch -D' it without coordinating)."
    return 0
  fi

  # NEW branch: base it on freshly-fetched trunk, resolved (not assumed) from the remote.
  base="$(git -C "$main" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
  if ! err="$(git -C "$main" -c core.hooksPath=/dev/null worktree add -b "$branch" "$wt" "$base" 2>&1)"; then
    wt_warn "STOP — could not create the worktree:"
    wt_warn "$err"
    return 1
  fi
  wt_say "WORKTREE_PATH=$wt"
  wt_say "Branch not found on local/origin → created NEW branch '$branch' off trunk ($base)."
  return 0
}

create_here() {
  local branch="$1" wt report
  wt="$MAIN/.claude/worktrees/$(wt_flat "$branch")"
  report="$(add_worktree "$MAIN" "$branch" "$wt")" || return 1
  wt_setup_cjs "$MAIN" setup "$wt" || wt_warn "warn: provisioning reported a failure (see above); the worktree still exists."
  wt_say "$report"
  return 0
}

create_minimal() {
  local root="$1" branch="$2" wt report
  wt="$root/.claude/worktrees/$(wt_flat "$branch")"
  report="$(add_worktree "$root" "$branch" "$wt")" || return 1
  wt_say "$report"
  wt_say "MINIMAL WORKTREE: $root has no worktree toolbox, so it has no setup: no package install, no .env or other local config, no setup steps."
  wt_say "Remove it yourself: git -C $(sh_quote "$root") worktree remove $(sh_quote "$wt"). Install the toolbox in that repo for the full setup."
  return 0
}

ARG=""
REPO_ARG=""
while [ $# -gt 0 ]; do  # NOSONAR: POSIX sh
  case "$1" in
    --repo)
      if [ $# -lt 2 ] || [ -z "$2" ]; then  # NOSONAR: POSIX sh
        wt_warn "--repo needs a path to another repo."
        usage
        exit 1
      fi
      if [ -n "$REPO_ARG" ]; then  # NOSONAR: POSIX sh
        wt_warn "Only one --repo per call; run the command once per repo."
        usage
        exit 1
      fi
      REPO_ARG="$2"
      shift 2
      ;;
    *)
      if [ -n "$ARG" ]; then  # NOSONAR: POSIX sh
        wt_warn "Unexpected extra argument: $1"
        usage
        exit 1
      fi
      ARG="$1"
      shift
      ;;
  esac
done

# --- validate ------------------------------------------------------------------------------
if [ -z "$ARG" ]; then  # NOSONAR: POSIX sh
  usage
  exit 1
fi
wt_validate "$ARG" || exit 1

# --- create --------------------------------------------------------------------------------
if [ -z "$REPO_ARG" ]; then  # NOSONAR: POSIX sh
  create_here "$ARG"
else
  ROOT="$(resolve_repo "$REPO_ARG")" || exit 1
  if [ -f "$ROOT/.claude/worktree.json" ]; then  # NOSONAR: POSIX sh
    hand_off "$ROOT" "$ARG"
  else
    create_minimal "$ROOT" "$ARG"
  fi
fi
exit $?
