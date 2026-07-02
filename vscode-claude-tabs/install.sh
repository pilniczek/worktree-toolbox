#!/usr/bin/env sh
# vscode-claude-tabs installer — installs the keybinding generator that opens a `claude`
# editor tab per git worktree, and generates the binding now. Installs USER-GLOBAL
# (~/.claude/scripts + your VS Code keybindings.json), not into a project.
#
#   curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/vscode-claude-tabs/install.sh | sh
#
# Overridable via env:
#   INSTALL_DIR               where to install the generator (default: ~/.claude/scripts)
#   CLAUDE_WT_KEY             keybinding chord for the generator      (default: ctrl+alt+w)
#   CLAUDE_WT_COMMAND         command run in each tab                 (default: claude)
#   VSCODE_KEYBINDINGS_PATH   full path to keybindings.json           (default: auto-detected)
#   WORKTREE_TOOLBOX_REPO     owner/repo to fetch                     (default: pilniczek/worktree-toolbox)
#   WORKTREE_TOOLBOX_REF      branch/tag/sha                          (default: main)
#   WORKTREE_TOOLBOX_SRC      local source dir containing the generator (skips the download)
set -eu

REPO="${WORKTREE_TOOLBOX_REPO:-pilniczek/worktree-toolbox}"
REF="${WORKTREE_TOOLBOX_REF:-main}"
SUBDIR="vscode-claude-tabs"   # this tool's folder within the repo
SCRIPT="gen-claude-tabs-keybinding.js"

say()  { printf '%s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v node >/dev/null 2>&1 || die "node is required but was not found on PATH."

# ---------------------------------------------------------------------------- locate source
# Prefer an explicit local source, then a checkout next to this script, else download a tarball.
SRC=""
if [ -n "${WORKTREE_TOOLBOX_SRC:-}" ]; then
  SRC="$WORKTREE_TOOLBOX_SRC"
else
  SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"
  if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/$SCRIPT" ]; then
    SRC="$SELF_DIR"
  fi
fi

TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }  # never let the trap flip the exit status
trap cleanup EXIT INT TERM

if [ -z "$SRC" ]; then
  command -v curl >/dev/null 2>&1 || die "curl is required to download the tool."
  command -v tar  >/dev/null 2>&1 || die "tar is required to unpack the tool."
  TMP="$(mktemp -d)"
  say "Fetching vscode-claude-tabs ($REPO@$REF)…"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xz -C "$TMP" \
    || die "download failed. Check WORKTREE_TOOLBOX_REPO / WORKTREE_TOOLBOX_REF."
  SRC="$TMP/$(ls "$TMP")/$SUBDIR"   # extracted root is <repo>-<ref>/; this tool sits one level deeper
fi
[ -f "$SRC/$SCRIPT" ] || die "generator not found at $SRC/$SCRIPT."

# ---------------------------------------------------------------------------- install
DEST="${INSTALL_DIR:-$HOME/.claude/scripts}"
mkdir -p "$DEST"
cp "$SRC/$SCRIPT" "$DEST/$SCRIPT"
chmod +x "$DEST/$SCRIPT"
say "✔ Installed $DEST/$SCRIPT"

# ---------------------------------------------------------------------------- generate now
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  node "$DEST/$SCRIPT"
else
  say "ℹ Not inside a git repo — skipped generating the binding."
  say "  From a repo checkout, run:  node \"$DEST/$SCRIPT\""
fi

cat <<EOF

Next:
  1. Reload VS Code (Command Palette → "Developer: Reload Window").
  2. Press ${CLAUDE_WT_KEY:-ctrl+alt+w} to open a claude editor tab per worktree.

Optional — refresh automatically when Claude Code's native worktree creation runs:
  point ~/.claude/scripts/open-worktree-terminal.sh at the installed generator, e.g.
    #!/usr/bin/env sh
    exec node "$DEST/$SCRIPT"
EOF
