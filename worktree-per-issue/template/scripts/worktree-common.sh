#!/usr/bin/env sh
# Shared helpers for the worktree scripts, sourced not executed:
# `. "$(dirname "$0")/worktree-common.sh"`. Single source of truth for the rules the three
# commands share (branch-name validation, the flat-name rule, locating the main checkout) —
# edit a shared rule HERE, once. Full narrative: docs/worktrees.md.

# Use these instead of `echo`: dash's echo (Linux /bin/sh) interprets backslash escapes, bash's
# (Windows Git Bash) does not, so `echo "$name"` mangles any backslash in a branch name or git
# error message on Linux. printf '%s' is identical on both.
wt_say()  { printf '%s\n' "$*"; }
wt_warn() { printf '%s\n' "$*" >&2; }

# Validate against git's own rule (rejects spaces, `..`, `~^:?*`, and a leading `-` that could be
# mistaken for a git option). A short or unusual name (e.g. `hotfix`, `feature/tst`) is a valid,
# deliberate choice — never a reason to stop.
wt_validate() {
  local branch="$1"
  if [ -z "$branch" ]; then  # NOSONAR: POSIX sh
    wt_warn "No branch name given."
    return 1
  fi
  if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
    wt_warn "\"$branch\" is not a legal git branch name (git rejects spaces, '..', '~^:?*', and a leading '-')."
    return 1
  fi
  return 0
}

# The worktree directory is .claude/worktrees/<flat>; the branch keeps its real `/` separators.
wt_flat() {
  local branch="$1"
  printf '%s' "$branch" | tr '/' '+'
}

# Reverse of wt_flat: the flat name for a path inside a worktree. Empty if the path isn't under one.
wt_flat_from_path() {
  local path="$1"
  local rest="${path#*/.claude/worktrees/}"
  printf '%s' "${rest%%/*}"
}

# The first `worktree <path>` line of `git worktree list --porcelain` is always the primary
# checkout. Space-safe.
wt_main() {
  git worktree list --porcelain | sed -n '1s/^worktree //p'
}

# `exit` inside `$(...)` only kills the subshell, so callers must propagate:
# `MAIN="$(wt_main_or_die)" || exit 1`.
wt_main_or_die() {
  m="$(wt_main)"
  [ -n "$m" ] || { wt_warn "Could not locate the main checkout (git worktree list)."; return 1; }  # NOSONAR: POSIX sh
  printf '%s' "$m"
}

# Honors WT_ORIGIN_PWD so a script that re-execs itself (see worktree-remove.sh) still tests the
# ORIGINAL location.
wt_inside_worktree() {
  case "${WT_ORIGIN_PWD:-$PWD}" in
    */.claude/worktrees/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Matches the absolute path so a substring can't false-match.
wt_assert_live() {
  local main="$1" flat="$2"
  git -C "$main" worktree list --porcelain \
    | grep -qxF "worktree $main/.claude/worktrees/$flat"
}
