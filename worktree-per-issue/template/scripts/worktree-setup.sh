#!/usr/bin/env sh
# Per-worktree setup. Runs once when a worktree is created (via /worktree-create or the post-checkout
# hook on a bare `git worktree add`); a marker file gates the provisioning steps so re-triggering is a
# fast no-op. `--force` (used by /worktree-heal) ignores the marker and re-runs every step.
set -e

FORCE=0
[ "$1" = "--force" ] && FORCE=1  # NOSONAR: POSIX sh

WT="$(pwd)"
case "$WT" in
  */.claude/worktrees/*) : ;;
  *)
    # Main checkout: nothing to set up, but reconcile stale worktree bookkeeping on open.
    # `git worktree prune` drops only dead records, never a live worktree or branch, so it's
    # safe unconditionally. Guard to the main tree (git-dir == git-common-dir) so a linked
    # worktree outside .claude/worktrees/ no-ops.
    if [ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then  # NOSONAR: POSIX sh
      git worktree prune 2>/dev/null || true
    fi
    exit 0
    ;;
esac

REPO="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"   # main checkout root
WT_PARENT="$(dirname "$WT")"

make_junction() {  # $1 = link path, $2 = absolute target
  case "$(uname -s)" in
    *MINGW*|*MSYS*|*CYGWIN*)
      cmd //c mklink //J "$(cygpath -w "$1")" "$(cygpath -w "$2")" ;;
    *)
      ln -s "$2" "$1" ;;
  esac
}

# --- sibling links -------------------------------------------------------------------------
# See "Project-specific sibling links" in docs/worktrees.md. Uncomment and adapt:
#
#   sibling_target="$(cd "$REPO/.." && pwd)/my-sibling-repo"
#   if [ ! -e "$WT_PARENT/my-sibling-repo" ] && [ -d "$sibling_target" ]; then
#     make_junction "$WT_PARENT/my-sibling-repo" "$sibling_target" 2>/dev/null || true
#   fi

# Copy the gitignored files listed in `.worktreeinclude` from the main checkout. This flow uses plain
# `git worktree add`, which does NOT honor Claude's native `.worktreeinclude`, so we do the copy
# ourselves — never clobbering a file the worktree already has.
if [ -f "$REPO/.worktreeinclude" ]; then  # NOSONAR: POSIX sh
  while IFS= read -r entry || [ -n "$entry" ]; do  # NOSONAR: POSIX sh
    case "$entry" in ''|\#*) continue ;; esac
    [ -f "$REPO/$entry" ] || continue  # NOSONAR: POSIX sh
    [ -e "$WT/$entry" ] && continue  # NOSONAR: POSIX sh
    mkdir -p "$WT/$(dirname "$entry")"
    cp "$REPO/$entry" "$WT/$entry" 2>/dev/null || true
  done < "$REPO/.worktreeinclude"
fi

# node_modules: hardlink-copy the main checkout's install (near-instant, ~no extra disk, files
# shared by inode). A later install in the worktree isolates automatically — the package manager
# replaces packages by atomic rename, so the main checkout's tree is never mutated; new deps land
# only in the worktree. `-e` follows into a real dir, so this is a no-op once provisioned.
# Fallbacks: a full copy (cross-filesystem / Windows, where hardlinks can fail), then a real
# install if the main checkout has none yet.
if [ ! -e "$WT/node_modules" ]; then  # NOSONAR: POSIX sh
  if [ -d "$REPO/node_modules" ]; then  # NOSONAR: POSIX sh
    cp -al "$REPO/node_modules" "$WT/node_modules" 2>/dev/null \
      || cp -a "$REPO/node_modules" "$WT/node_modules" 2>/dev/null \
      || ( cd "$WT" && {{PM_INSTALL}} )
  else
    ( cd "$WT" && {{PM_INSTALL}} )
  fi
fi

MARKER="$WT/node_modules/.wt-provisioned"
if [ "$FORCE" = 1 ] || [ ! -e "$MARKER" ]; then  # NOSONAR: POSIX sh
{{PROVISION_STEPS}}
  # Write the marker only if its node_modules parent exists. A failed redirect on ':' (a POSIX
  # special builtin) aborts a non-interactive dash (Linux /bin/sh) despite '|| true'; bash does
  # not. If node_modules is absent (no deps / a non-node repo), skip it so setup simply re-runs.
  [ -d "$WT/node_modules" ] && { : > "$MARKER" 2>/dev/null || true; }  # NOSONAR: POSIX sh
fi
