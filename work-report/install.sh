#!/usr/bin/env sh
# work-report installer — adds the /work-report Claude Code command to a project.
# Run from inside the target git repo:
#
#   curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/work-report/install.sh | sh
#
# Overridable via env:
#   WORKTREE_TOOLBOX_REPO   owner/repo to fetch (default below)
#   WORKTREE_TOOLBOX_REF    branch/tag/sha    (default: main)
#   WORKTREE_TOOLBOX_SRC    local source dir with template/ (skips the download)
set -eu

REPO="${WORKTREE_TOOLBOX_REPO:-pilniczek/worktree-toolbox}"
REF="${WORKTREE_TOOLBOX_REF:-main}"
SUBDIR="work-report"   # this tool's folder within the repo
CMD="template/.claude/commands/work-report.md"

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------- preflight
command -v git >/dev/null 2>&1 || die "git is required."
TARGET="$(git rev-parse --show-toplevel 2>/dev/null)" || die "run this from inside a git repository."
cd "$TARGET"
say "Target project: $TARGET"

# ---------------------------------------------------------------------------- locate source
# Prefer an explicit local source, then a checkout next to this script, else download a tarball.
SRC=""
if [ -n "${WORKTREE_TOOLBOX_SRC:-}" ]; then
  SRC="$WORKTREE_TOOLBOX_SRC"
else
  SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)"
  if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/$CMD" ]; then SRC="$SELF_DIR"; fi
fi

TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }  # never let the trap flip the exit status
trap cleanup EXIT INT TERM

if [ -z "$SRC" ]; then
  command -v curl >/dev/null 2>&1 || die "curl is required to download the tool."
  command -v tar  >/dev/null 2>&1 || die "tar is required to unpack the tool."
  TMP="$(mktemp -d)"
  say "Fetching work-report ($REPO@$REF)…"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xz -C "$TMP" \
    || die "download failed. Check WORKTREE_TOOLBOX_REPO / WORKTREE_TOOLBOX_REF."
  SRC="$TMP/$(ls "$TMP")/$SUBDIR"   # extracted root is <repo>-<ref>/; this tool sits one level deeper
fi
[ -f "$SRC/$CMD" ] || die "command not found at $SRC/$CMD."

# ---------------------------------------------------------------------------- install
say ""
say "Installing files:"
mkdir -p .claude/commands
DEST=".claude/commands/work-report.md"
if [ -f "$DEST" ]; then
  if cmp -s "$SRC/$CMD" "$DEST"; then say "  = $DEST (unchanged)";
  else cp "$SRC/$CMD" "$DEST"; say "  ~ $DEST (replaced; review with git diff)"; fi
else
  cp "$SRC/$CMD" "$DEST"; say "  + $DEST"
fi

# ---------------------------------------------------------------------------- gitignore
# WORK-REPORT.md lives at the working tree's root. Anchor the rule with a leading slash so it
# ignores only the root report — a bare 'WORK-REPORT.md' matches by basename at any depth and,
# on a case-insensitive FS (core.ignorecase=true, the Windows/macOS default), also matches the
# command file we just wrote at .claude/commands/work-report.md, silently un-tracking it. The
# leading slash still covers worktree roots, since ignores resolve relative to each working tree.
# NB: fresh installs only — a re-run does not rewrite a stale unanchored line left by an old install.
if [ -f .gitignore ] && grep -qxF '/WORK-REPORT.md' .gitignore; then
  say "  gitignore: /WORK-REPORT.md already ignored"
else
  { [ -f .gitignore ] && [ -n "$(tail -c1 .gitignore 2>/dev/null)" ] && printf '\n'; :; } >> .gitignore
  printf '# Work report (worktree-toolbox / work-report) — git add -f to commit it\n/WORK-REPORT.md\n' >> .gitignore
  say "  gitignore: added /WORK-REPORT.md"
fi

say ""
say "Done. work-report installed."
say ""
say "Use it from Claude Code:  /work-report"
