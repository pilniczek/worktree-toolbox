#!/usr/bin/env sh
# Adds the worktree-per-issue Claude Code toolbox to a project. Run from the ROOT of the target repo:
#   curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/worktree-per-issue/install.sh | sh
# Env overrides (WORKTREE_TOOLBOX_*): see ../AGENTS.md.
set -eu

REPO="${WORKTREE_TOOLBOX_REPO:-pilniczek/worktree-toolbox}"
REF="${WORKTREE_TOOLBOX_REF:-main}"
SUBDIR="worktree-per-issue"   # this tool's folder within the repo

say()  { printf '%s\n' "$*"; return 0; }
warn() { printf 'WARN: %s\n' "$*" >&2; return 0; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- preflight -----------------------------------------------------------------------------
command -v git  >/dev/null 2>&1 || die "git is required."
command -v node >/dev/null 2>&1 || die "node is required (used to merge JSON config safely)."

TARGET="$(git rev-parse --show-toplevel 2>/dev/null)" || die "run this from inside a git repository."
cd "$TARGET"
say "Target project: $TARGET"

# --- source --------------------------------------------------------------------------------
# Prefer an explicit local source, then a checkout next to this script, else download a tarball.
SRC=""
if [ -n "${WORKTREE_TOOLBOX_SRC:-}" ]; then  # NOSONAR: POSIX sh
  SRC="$WORKTREE_TOOLBOX_SRC"
else
  SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"
  if [ -n "$SELF_DIR" ] && [ -d "$SELF_DIR/template" ]; then  # NOSONAR: POSIX sh
    SRC="$SELF_DIR"
  fi
fi

TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }  # NOSONAR: POSIX sh; never let the trap flip the exit status
trap cleanup EXIT INT TERM

if [ -z "$SRC" ]; then  # NOSONAR: POSIX sh
  command -v curl >/dev/null 2>&1 || die "curl is required to download the toolbox."
  command -v tar  >/dev/null 2>&1 || die "tar is required to unpack the toolbox."
  TMP="$(mktemp -d)"
  say "Fetching worktree-toolbox ($REPO@$REF)…"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xz -C "$TMP" \
    || die "download failed. Check WORKTREE_TOOLBOX_REPO / WORKTREE_TOOLBOX_REF."
  SRC="$TMP/$(ls "$TMP")/$SUBDIR"   # extracted root is <repo>-<ref>/; this tool sits one level deeper
fi
[ -d "$SRC/template" ] || die "toolbox source is missing template/ at $SRC."  # NOSONAR: POSIX sh

# --- prompts -------------------------------------------------------------------------------
# Detect a usable controlling terminal by actually opening /dev/tty — the device node can
# exist yet fail to open (ENXIO) under pipes/CI, so a plain -r test is not enough. The open
# is done in a SUBSHELL: in dash a failed redirection on a compound command is fatal to the
# whole shell, so isolating it keeps only the subshell dying and lets us branch on its status.
if ( : >/dev/tty ) 2>/dev/null; then INTERACTIVE=1; else INTERACTIVE=0; fi
[ "$INTERACTIVE" = 0 ] && warn "no TTY available - no prompts, writing an empty config."  # NOSONAR: POSIX sh

ask() { # ask "<prompt>" -> echoes the answer
  local _a
  printf '%s: ' "$1" >/dev/tty
  IFS= read -r _a </dev/tty || _a=""
  printf '%s' "$_a"
  return 0
}

# --- worktree config -----------------------------------------------------------------------
CONFIG=".claude/worktree.json"
set --
if [ "$INTERACTIVE" = 1 ] && [ ! -f "$CONFIG" ]; then  # NOSONAR: POSIX sh
  say ""
  say "Worktree setup, saved to $CONFIG. One entry per line, a blank line moves to the next key:"
  say "  copy      paths copied into each worktree (e.g. .env)"
  say "  hardlink  paths rebuilt from hardlinks (e.g. node_modules)"
  say "  link      links to the main checkout (e.g. fixtures/big)"
  say "  repos     folders of repos next to this one, reachable as ../<name> from every worktree (e.g. other-repo)"
  say "  steps     commands run once per worktree (e.g. npm run generate)"
  for key in copy hardlink link repos steps; do
    while entry="$(ask "  $key")" && [ -n "$entry" ]; do  # NOSONAR: POSIX sh
      set -- "$@" "$key" "$entry"
    done
  done
fi

# --- write files ---------------------------------------------------------------------------
say ""
say "Installing files:"
mkdir -p .claude/commands .husky scripts docs

install_file() { # $1 = source, $2 = dest  (overwrites a differing existing file in place)
  local src="$1" dest="$2"
  if [ -f "$dest" ]; then  # NOSONAR: POSIX sh
    if cmp -s "$src" "$dest"; then say "  = $dest (unchanged)"; return 0; fi
    say "  ~ $dest (replaced; review with git diff)"
  else
    say "  + $dest"
  fi
  cp "$src" "$dest"
  return $?
}

# Static copies (no install-time templating): the hook, the three command wrappers, the scripts.
install_file "$SRC/template/.husky/post-checkout"          ".husky/post-checkout"
for cmd in worktree-create worktree-heal worktree-remove; do
  install_file "$SRC/template/.claude/commands/$cmd.md"    ".claude/commands/$cmd.md"
done
for s in worktree-common worktree-create worktree-heal worktree-remove; do
  install_file "$SRC/template/scripts/$s.sh"               "scripts/$s.sh"
done
install_file "$SRC/template/scripts/worktree-setup.cjs"    "scripts/worktree-setup.cjs"
install_file "$SRC/template/docs/worktrees.md"             "docs/worktrees.md"

if [ -f "$CONFIG" ]; then  # NOSONAR: POSIX sh
  say "  = $CONFIG (kept) - edit $CONFIG to change worktree setup"
else
  node "$TARGET/scripts/worktree-setup.cjs" init "$CONFIG" "$@"
  say "  + $CONFIG"
fi
if ! CHECK="$(node "$TARGET/scripts/worktree-setup.cjs" check "$CONFIG" 2>&1 >/dev/null)"; then
  warn "$CONFIG has errors. Worktree setup stops on them until you fix the file:"
  printf '%s\n' "$CHECK" | sed 's/^/WARN: /' >&2
fi

chmod +x .husky/post-checkout scripts/worktree-*.sh 2>/dev/null || true

# --- merge config --------------------------------------------------------------------------
say ""
say "Merging config (additive — existing values are preserved):"
MERGE="$SRC/lib/merge.cjs"
node "$MERGE" settings ".claude/settings.json" | sed 's/^/  settings: /' || warn "settings.json merge reported an issue (see above)."
node "$MERGE" vscode   ".vscode/settings.json" '4'                                               | sed 's/^/  vscode:   /' || warn "vscode settings merge reported an issue (see above)."

# --- gitignore -----------------------------------------------------------------------------
if [ -f .gitignore ] && grep -qxF '.claude/worktrees/' .gitignore; then  # NOSONAR: POSIX sh
  say "  gitignore: .claude/worktrees/ already ignored"
else
  { [ -f .gitignore ] && [ -n "$(tail -c1 .gitignore 2>/dev/null)" ] && printf '\n'; :; } >> .gitignore  # NOSONAR: POSIX sh
  printf '# Claude Code worktrees (worktree-toolbox)\n.claude/worktrees/\n' >> .gitignore
  say "  gitignore: added .claude/worktrees/"
fi

# --- husky ---------------------------------------------------------------------------------
if [ ! -d .husky ] || ! { [ -f package.json ] && grep -q '"husky"' package.json; }; then  # NOSONAR: POSIX sh
  say ""
  warn "husky was not detected. The .husky/post-checkout hook (a convenience that provisions a"
  warn "worktree created via a bare 'git worktree add' on the CLI) only fires when husky is"
  warn "installed (core.hooksPath=.husky, plus a \"prepare\" script). This is optional: the Claude"
  warn "/worktree-create and /worktree-heal commands run scripts/worktree-setup.cjs explicitly, so provisioning"
  warn "works with or without husky."
fi

# --- summary -------------------------------------------------------------------------------
say ""
say "Done. worktree-toolbox installed."
say ""
say "Next steps:"
say "  1. Review the changes (git diff)."
say "  2. Run your package manager's install once to wire up the husky hook (if you use husky)."
say "  3. Edit $CONFIG to change worktree setup - see docs/worktrees.md."
say "  4. Create a worktree from Claude Code:  /worktree-create feature/<initials>/<TICKET>/<slug>"
