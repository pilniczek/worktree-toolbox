#!/usr/bin/env sh
# Per-worktree setup. Runs once when a worktree is created (via /worktree-create or the post-checkout
# hook on a bare `git worktree add`). Provisioning steps are gated by a marker file so
# re-triggering is a fast no-op; `--force` (used by /worktree-heal, worktree heal) ignores the marker
# and re-runs every step.
set -e

FORCE=0
[ "$1" = "--force" ] && FORCE=1

WT="$(pwd)"
case "$WT" in
  */.claude/worktrees/*) : ;;       # inside a Claude worktree: run the per-worktree setup below
  *)
    # Main checkout: nothing to set up, but reconcile stale worktree bookkeeping on open.
    # `git worktree prune` drops only dead records, never a live worktree or branch, so it's
    # safe unconditionally. Guard to the main tree (git-dir == git-common-dir) so a linked
    # worktree outside .claude/worktrees/ no-ops.
    if [ "$(git rev-parse --git-dir 2>/dev/null)" = "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then
      git worktree prune 2>/dev/null || true
    fi
    exit 0
    ;;
esac

REPO="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"   # main checkout root
WT_PARENT="$(dirname "$WT")"                                 # .../.claude/worktrees

make_junction() {  # $1 = link path, $2 = absolute target
  case "$(uname -s)" in
    *MINGW*|*MSYS*|*CYGWIN*)
      cmd //c mklink //J "$(cygpath -w "$1")" "$(cygpath -w "$2")" ;;
    *)
      ln -s "$2" "$1" ;;
  esac
}

# --- project-specific sibling links (edit me) ------------------------------------------------
# If your project imports a sibling repo via a relative path (e.g. a shared knowledge base or
# design-system clone that lives next to this repo), link it into the shared worktrees parent so
# every worktree's relative import resolves. Uncomment and adapt:
#
#   sibling_target="$(cd "$REPO/.." && pwd)/my-sibling-repo"
#   if [ ! -e "$WT_PARENT/my-sibling-repo" ] && [ -d "$sibling_target" ]; then
#     make_junction "$WT_PARENT/my-sibling-repo" "$sibling_target" 2>/dev/null || true
#   fi
# ---------------------------------------------------------------------------------------------

# Local gitignored config. Copy the files listed in `.worktreeinclude` from the main checkout into
# the worktree (env files, local settings, …). This flow uses plain `git worktree add`, which does
# NOT honor Claude's native `.worktreeinclude`, so we do the copy ourselves. Skip comments/blank
# lines; create parent dirs; never clobber a file the worktree already has.
if [ -f "$REPO/.worktreeinclude" ]; then
  while IFS= read -r entry || [ -n "$entry" ]; do
    case "$entry" in ''|\#*) continue ;; esac
    [ -f "$REPO/$entry" ] || continue
    [ -e "$WT/$entry" ] && continue
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
if [ ! -e "$WT/node_modules" ]; then
  if [ -d "$REPO/node_modules" ]; then
    cp -al "$REPO/node_modules" "$WT/node_modules" 2>/dev/null \
      || cp -a "$REPO/node_modules" "$WT/node_modules" 2>/dev/null \
      || ( cd "$WT" && {{PM_INSTALL}} )
  else
    ( cd "$WT" && {{PM_INSTALL}} )
  fi
fi

# Per-worktree provisioning steps (configured at install time). They run once — the marker file
# below records that a worktree has been provisioned, so a re-trigger (e.g. post-checkout plus an
# explicit /worktree-create run) is a no-op. `/worktree-heal` passes --force to rebuild everything regardless. The marker
# lives under node_modules (gitignored, always writable, provisioned just above).
MARKER="$WT/node_modules/.wt-provisioned"
if [ "$FORCE" = 1 ] || [ ! -e "$MARKER" ]; then
{{PROVISION_STEPS}}
  : > "$MARKER" 2>/dev/null || true
fi
