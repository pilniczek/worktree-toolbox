#!/usr/bin/env sh
# worktree-toolbox installer — adds the worktree-per-issue Claude Code toolbox to a project.
# Run from the ROOT of the target git repo:
#
#   curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/worktree-per-issue/install.sh | sh
#
# Overridable via env:
#   WORKTREE_TOOLBOX_REPO   owner/repo to fetch (default below)
#   WORKTREE_TOOLBOX_REF    branch/tag/sha    (default: main)
#   WORKTREE_TOOLBOX_SRC    local source dir with template/ and lib/ (skips the download)
set -eu

REPO="${WORKTREE_TOOLBOX_REPO:-pilniczek/worktree-toolbox}"
REF="${WORKTREE_TOOLBOX_REF:-main}"
SUBDIR="worktree-per-issue"   # this tool's folder within the repo

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------- preflight
command -v git  >/dev/null 2>&1 || die "git is required."
command -v node >/dev/null 2>&1 || die "node is required (used to merge JSON config safely)."

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
  if [ -n "$SELF_DIR" ] && [ -d "$SELF_DIR/template" ]; then
    SRC="$SELF_DIR"
  fi
fi

TMP=""
cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; return 0; }  # never let the trap flip the exit status
trap cleanup EXIT INT TERM

if [ -z "$SRC" ]; then
  command -v curl >/dev/null 2>&1 || die "curl is required to download the toolbox."
  command -v tar  >/dev/null 2>&1 || die "tar is required to unpack the toolbox."
  TMP="$(mktemp -d)"
  say "Fetching worktree-toolbox ($REPO@$REF)…"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" | tar -xz -C "$TMP" \
    || die "download failed. Check WORKTREE_TOOLBOX_REPO / WORKTREE_TOOLBOX_REF."
  SRC="$TMP/$(ls "$TMP")/$SUBDIR"   # extracted root is <repo>-<ref>/; this tool sits one level deeper
fi
[ -d "$SRC/template" ] || die "toolbox source is missing template/ at $SRC."

# ---------------------------------------------------------------------------- prompt plumbing
# Detect a usable controlling terminal by actually opening /dev/tty — the device node can
# exist yet fail to open (ENXIO) under pipes/CI, so a plain -r test is not enough. The open
# is done in a SUBSHELL: in dash a failed redirection on a compound command is fatal to the
# whole shell, so isolating it keeps only the subshell dying and lets us branch on its status.
if ( : >/dev/tty ) 2>/dev/null; then INTERACTIVE=1; else INTERACTIVE=0; fi
[ "$INTERACTIVE" = 0 ] && warn "no TTY available — using defaults, no prompts."

ask() { # ask "<prompt>" "<default>" -> echoes the answer
  _p="$1"; _d="${2:-}"
  if [ "$INTERACTIVE" = 0 ]; then printf '%s' "$_d"; return; fi
  if [ -n "$_d" ]; then printf '%s [%s]: ' "$_p" "$_d" >/dev/tty
  else printf '%s: ' "$_p" >/dev/tty; fi
  IFS= read -r _a </dev/tty || _a=""
  [ -z "$_a" ] && _a="$_d"
  printf '%s' "$_a"
}

# ---------------------------------------------------------------------------- package manager
PM_DEFAULT=npm
if   [ -f pnpm-lock.yaml ]; then PM_DEFAULT=pnpm
elif [ -f yarn.lock ];      then PM_DEFAULT=yarn
elif [ -f package-lock.json ]; then PM_DEFAULT=npm
fi
PM="$(ask "Package manager (npm/pnpm/yarn)" "$PM_DEFAULT")"
case "$PM" in
  npm)  PM_INSTALL="npm install" ;;
  pnpm) PM_INSTALL="pnpm install" ;;
  yarn) PM_INSTALL="yarn install" ;;
  *)    PM_INSTALL="$PM install"; warn "unrecognized package manager '$PM'; using '$PM_INSTALL'." ;;
esac
# Escape hatch for repos whose install command isn't the PM default (e.g. 'npm run init').
# Honored in both interactive and non-interactive runs — the only way to set it under curl | sh.
PM_INSTALL="${WORKTREE_TOOLBOX_PM_INSTALL:-$PM_INSTALL}"

# ---------------------------------------------------------------------------- provisioning steps
STEPS_FILE="$(mktemp)"; SUMMARY_STEPS=""
add_step() { # $1 = provisioning command — appends to STEPS_FILE and grows SUMMARY_STEPS
  printf '( cd "$WT" && %s ) || echo "worktree: '\''%s'\'' failed; run it manually in the worktree." >&2\n' "$1" "$1" >> "$STEPS_FILE"
  if [ -z "$SUMMARY_STEPS" ]; then SUMMARY_STEPS="\`$1\`"; else SUMMARY_STEPS="$SUMMARY_STEPS, \`$1\`"; fi
}
say ""
say "Per-worktree provisioning commands (e.g. a codegen step). They run once when a worktree is"
say "created, and again on '/worktree-heal' (worktree heal). Leave the command blank to finish."
# Non-interactive escape hatch: one command per line in WORKTREE_TOOLBOX_PROVISION. Honored
# regardless of TTY — the only way to configure provisioning steps under curl | sh. Fed via a
# heredoc (not a pipe) so the loop runs in this shell and SUMMARY_STEPS survives.
if [ -n "${WORKTREE_TOOLBOX_PROVISION:-}" ]; then
  say "  Preloading provisioning steps from WORKTREE_TOOLBOX_PROVISION (any interactive entries are appended):"
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    add_step "$cmd"; say "    added: $cmd"
  done <<EOF
$WORKTREE_TOOLBOX_PROVISION
EOF
fi
while [ "$INTERACTIVE" = 1 ]; do
  cmd="$(ask "  setup command (blank = done)" "")"
  [ -z "$cmd" ] && break
  add_step "$cmd"; say "    added: $cmd"
done
[ -s "$STEPS_FILE" ] || printf '# (no provisioning steps configured)\n' > "$STEPS_FILE"

WT_SUMMARY="it hardlink-copies the main checkout's \`node_modules\`"
if [ -n "$SUMMARY_STEPS" ]; then
  WT_SUMMARY="$WT_SUMMARY and runs your configured provisioning steps ($SUMMARY_STEPS)."
else
  WT_SUMMARY="$WT_SUMMARY."
fi

# ---------------------------------------------------------------------------- worktreeinclude
say ""
INCLUDE_DEFAULT=".claude/settings.local.json"
[ -f .env ] && INCLUDE_DEFAULT=".env $INCLUDE_DEFAULT"
INCLUDE_LIST="$(ask "Gitignored files to copy into each worktree (space-separated)" "$INCLUDE_DEFAULT")"

# ---------------------------------------------------------------------------- write files
say ""
say "Installing files:"
mkdir -p .claude/commands .husky scripts docs

install_file() { # $1 = source, $2 = dest  (overwrites a differing existing file in place)
  if [ -f "$2" ]; then
    if cmp -s "$1" "$2"; then say "  = $2 (unchanged)"; return 0; fi
    say "  ~ $2 (replaced; review with git diff)"
  else
    say "  + $2"
  fi
  cp "$1" "$2"
}

# static copies
install_file "$SRC/template/.husky/post-checkout"     ".husky/post-checkout"

GEN="$(mktemp)"

# templated: the three slash commands each inline the shared block in place of their {{WORKTREE_SHARED}}
# placeholder. The shared block (shared/worktree-shared.md) is a build input — it is NOT copied into the
# target; its {{WORKTREE_SETUP_SUMMARY}} is substituted first, then the whole block is spliced in, so the
# installed commands are self-contained.
for cmd in worktree-create worktree-heal worktree-remove; do
  WT_SUMMARY="$WT_SUMMARY" node -e '
    const fs=require("fs");
    let shared=fs.readFileSync(process.argv[1],"utf8");
    shared=shared.split("{{WORKTREE_SETUP_SUMMARY}}").join(process.env.WT_SUMMARY);
    // drop the build-input HTML comment header so it does not leak into the installed command
    shared=shared.replace(/^<!--[\s\S]*?-->\n*/, "");
    let cmd=fs.readFileSync(process.argv[2],"utf8");
    cmd=cmd.split("{{WORKTREE_SHARED}}").join(shared.trimEnd());
    fs.writeFileSync(process.argv[3],cmd);
  ' "$SRC/shared/worktree-shared.md" "$SRC/template/.claude/commands/$cmd.md" "$GEN"
  install_file "$GEN" ".claude/commands/$cmd.md"
done

# templated: worktree-setup.sh
PM_INSTALL="$PM_INSTALL" STEPS_FILE="$STEPS_FILE" node -e '
  const fs=require("fs");
  let s=fs.readFileSync(process.argv[1],"utf8");
  s=s.split("{{PM_INSTALL}}").join(process.env.PM_INSTALL);
  s=s.split("{{PROVISION_STEPS}}").join(fs.readFileSync(process.env.STEPS_FILE,"utf8").trimEnd());
  fs.writeFileSync(process.argv[2],s);
' "$SRC/template/scripts/worktree-setup.sh" "$GEN"
install_file "$GEN" "scripts/worktree-setup.sh"

# templated: docs/worktrees.md
PM_INSTALL="$PM_INSTALL" node -e '
  const fs=require("fs");
  let s=fs.readFileSync(process.argv[1],"utf8");
  s=s.split("{{PM_INSTALL}}").join(process.env.PM_INSTALL);
  fs.writeFileSync(process.argv[2],s);
' "$SRC/template/docs/worktrees.md" "$GEN"
install_file "$GEN" "docs/worktrees.md"
rm -f "$GEN"

chmod +x .husky/post-checkout scripts/worktree-setup.sh 2>/dev/null || true

# ---------------------------------------------------------------------------- merge config
say ""
say "Merging config (additive — existing values are preserved):"
MERGE="$SRC/lib/merge.cjs"
node "$MERGE" settings ".claude/settings.json" | sed 's/^/  settings: /' || warn "settings.json merge reported an issue (see above)."
node "$MERGE" vscode   ".vscode/settings.json" '4'                                               | sed 's/^/  vscode:   /' || warn "vscode settings merge reported an issue (see above)."

# ---------------------------------------------------------------------------- gitignore + worktreeinclude
if [ -f .gitignore ] && grep -qxF '.claude/worktrees/' .gitignore; then
  say "  gitignore: .claude/worktrees/ already ignored"
else
  { [ -f .gitignore ] && [ -n "$(tail -c1 .gitignore 2>/dev/null)" ] && printf '\n'; :; } >> .gitignore
  printf '# Claude Code worktrees (worktree-toolbox)\n.claude/worktrees/\n' >> .gitignore
  say "  gitignore: added .claude/worktrees/"
fi

TMP_INC="$(mktemp)"
{
  printf '# Gitignored files a fresh worktree needs — copied into each new worktree by Claude Code.\n'
  printf '# Syntax is gitignore-style. See docs/worktrees.md.\n'
  for f in $INCLUDE_LIST; do printf '%s\n' "$f"; done
} > "$TMP_INC"
install_file "$TMP_INC" ".worktreeinclude"
rm -f "$TMP_INC" "$STEPS_FILE"

# ---------------------------------------------------------------------------- husky note
if [ ! -d .husky ] || ! { [ -f package.json ] && grep -q '"husky"' package.json; }; then
  say ""
  warn "husky was not detected. The .husky/post-checkout hook (a convenience that provisions a"
  warn "worktree created via a bare 'git worktree add' on the CLI) only fires when husky is"
  warn "installed (core.hooksPath=.husky, plus a \"prepare\" script). This is optional: the Claude"
  warn "/worktree-create and /worktree-heal commands run scripts/worktree-setup.sh explicitly, so provisioning"
  warn "works with or without husky."
fi

# ---------------------------------------------------------------------------- summary
say ""
say "Done. worktree-toolbox installed."
say ""
say "Next steps:"
say "  1. Review the changes (git diff)."
say "  2. Run '$PM_INSTALL' once to wire up the husky hook (if you use husky)."
say "  3. For a sibling-repo link (shared library / knowledge base), edit the marked block in"
say "     scripts/worktree-setup.sh — see the 'Project-specific sibling links' section of docs/worktrees.md."
say "  4. Create a worktree from Claude Code:  /worktree-create feature/<initials>/<TICKET>/<slug>"
