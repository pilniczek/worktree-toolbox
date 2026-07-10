#!/usr/bin/env sh
# Adds the worktree-per-issue Claude Code toolbox to a project. Run from the ROOT of the target repo:
#   curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/worktree-per-issue/install.sh | sh
# Env overrides: see ../AGENTS.md (shared WORKTREE_TOOLBOX_*) and ./AGENTS.md (PM_INSTALL, PROVISION).
set -eu

REPO="${WORKTREE_TOOLBOX_REPO:-pilniczek/worktree-toolbox}"
REF="${WORKTREE_TOOLBOX_REF:-main}"
SUBDIR="worktree-per-issue"   # this tool's folder within the repo

say()  { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
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

# --- prompts -------------------------------------------------------------------------------
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

# --- package manager -----------------------------------------------------------------------
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

# --- provisioning --------------------------------------------------------------------------
STEPS_FILE="$(mktemp)"
add_step() { # $1 = provisioning command — appends the guarded command to STEPS_FILE
  printf '( cd "$WT" && %s ) || echo "worktree: '\''%s'\'' failed; run it manually in the worktree." >&2\n' "$1" "$1" >> "$STEPS_FILE"
}
say ""
say "Per-worktree provisioning commands (e.g. a codegen step). They run once when a worktree is"
say "created, and again on '/worktree-heal' (worktree heal). Leave the command blank to finish."
# Non-interactive escape hatch: one command per line in WORKTREE_TOOLBOX_PROVISION. Honored
# regardless of TTY — the only way to configure provisioning steps under curl | sh. Fed via a
# heredoc (not a pipe) so the loop runs in this shell and the steps land in STEPS_FILE.
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

# --- worktreeinclude -----------------------------------------------------------------------
INCLUDE_FILE="$(mktemp)"
say ""
say "Gitignored files to copy into each new worktree (e.g. .env, local settings)."
say "Leave the path blank to finish."
[ -f .env ] && { printf '%s\n' ".env" >> "$INCLUDE_FILE"; say "    added: .env"; }
if [ "$INTERACTIVE" = 1 ]; then
  inc_default=".claude/settings.local.json"
  while :; do
    entry="$(ask "  file to copy (blank = done)" "$inc_default")"
    inc_default=""                       # default is offered on the first line only
    [ -z "$entry" ] && break
    printf '%s\n' "$entry" >> "$INCLUDE_FILE"; say "    added: $entry"
  done
else
  printf '%s\n' ".claude/settings.local.json" >> "$INCLUDE_FILE"
fi

# --- write files ---------------------------------------------------------------------------
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

# Static copies (no install-time templating): the hook, the three command wrappers, the scripts.
install_file "$SRC/template/.husky/post-checkout"          ".husky/post-checkout"
for cmd in worktree-create worktree-heal worktree-remove; do
  install_file "$SRC/template/.claude/commands/$cmd.md"    ".claude/commands/$cmd.md"
done
for s in worktree-common worktree-create worktree-heal worktree-remove; do
  install_file "$SRC/template/scripts/$s.sh"               "scripts/$s.sh"
done

GEN="$(mktemp)"

# tmpl SRC DST — copy SRC to DST substituting the install-time template tokens: {{PM_INSTALL}}
# everywhere, and {{PROVISION_STEPS}} where present (absent in docs/worktrees.md — a no-op there).
tmpl() {
  PM_INSTALL="$PM_INSTALL" STEPS_FILE="$STEPS_FILE" node -e '
    const fs=require("fs");
    let s=fs.readFileSync(process.argv[1],"utf8");
    s=s.split("{{PM_INSTALL}}").join(process.env.PM_INSTALL);
    s=s.split("{{PROVISION_STEPS}}").join(fs.readFileSync(process.env.STEPS_FILE,"utf8").trimEnd());
    fs.writeFileSync(process.argv[2],s);
  ' "$1" "$2"
}

tmpl "$SRC/template/scripts/worktree-setup.sh" "$GEN"; install_file "$GEN" "scripts/worktree-setup.sh"
tmpl "$SRC/template/docs/worktrees.md"          "$GEN"; install_file "$GEN" "docs/worktrees.md"
rm -f "$GEN"

chmod +x .husky/post-checkout scripts/worktree-*.sh 2>/dev/null || true

# --- merge config --------------------------------------------------------------------------
say ""
say "Merging config (additive — existing values are preserved):"
MERGE="$SRC/lib/merge.cjs"
node "$MERGE" settings ".claude/settings.json" | sed 's/^/  settings: /' || warn "settings.json merge reported an issue (see above)."
node "$MERGE" vscode   ".vscode/settings.json" '4'                                               | sed 's/^/  vscode:   /' || warn "vscode settings merge reported an issue (see above)."

# --- gitignore -----------------------------------------------------------------------------
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
  cat "$INCLUDE_FILE"
} > "$TMP_INC"
install_file "$TMP_INC" ".worktreeinclude"
rm -f "$TMP_INC" "$STEPS_FILE" "$INCLUDE_FILE"

# --- husky ---------------------------------------------------------------------------------
if [ ! -d .husky ] || ! { [ -f package.json ] && grep -q '"husky"' package.json; }; then
  say ""
  warn "husky was not detected. The .husky/post-checkout hook (a convenience that provisions a"
  warn "worktree created via a bare 'git worktree add' on the CLI) only fires when husky is"
  warn "installed (core.hooksPath=.husky, plus a \"prepare\" script). This is optional: the Claude"
  warn "/worktree-create and /worktree-heal commands run scripts/worktree-setup.sh explicitly, so provisioning"
  warn "works with or without husky."
fi

# --- summary -------------------------------------------------------------------------------
say ""
say "Done. worktree-toolbox installed."
say ""
say "Next steps:"
say "  1. Review the changes (git diff)."
say "  2. Run '$PM_INSTALL' once to wire up the husky hook (if you use husky)."
say "  3. For a sibling-repo link (shared library / knowledge base), edit the marked block in"
say "     scripts/worktree-setup.sh — see the 'Project-specific sibling links' section of docs/worktrees.md."
say "  4. Create a worktree from Claude Code:  /worktree-create feature/<initials>/<TICKET>/<slug>"
