#!/usr/bin/env sh
# Install-combination smoke test for worktree-toolbox.
#
# The three tools (worktree-per-issue=W, work-report=R, vscode-claude-tabs=V) are advertised as
# independently installable — "use any alone or together." This test installs each of the 7
# non-empty combinations into a throwaway git repo and asserts they do not collide: expected
# artifacts land, no installer clobbers another's file (a *.bak would prove it did), the shared
# .gitignore gets each entry exactly once, V stays user-global, and re-runs are idempotent.
#
# Fully OFFLINE — installs from the local checkout via each installer's WORKTREE_TOOLBOX_SRC
# override, so nothing is downloaded. Fully SANDBOXED — HOME, the vscode-claude-tabs INSTALL_DIR,
# and the VS Code keybindings path are all redirected to temp dirs, so your real ~/.claude and
# VS Code config are never touched.
#
# Requires: git, node, sh.  Run from anywhere:  sh test/install-matrix.sh
set -u

# ---------------------------------------------------------------------------- locate the repo
# This script lives in <repo>/test/.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
W_SRC="$REPO/worktree-per-issue"
R_SRC="$REPO/work-report"
V_SRC="$REPO/vscode-claude-tabs"

command -v git  >/dev/null 2>&1 || { echo "git is required."  >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node is required." >&2; exit 1; }

# ---------------------------------------------------------------------------- non-interactive runner
# worktree-per-issue's installer prompts when it can open /dev/tty; on a developer terminal that
# would hang the test. Detach from the controlling terminal so /dev/tty can't be opened and the
# installer falls back to its defaults. `setsid -w` waits and forwards the child's exit status;
# plain `setsid` may fork and lose it, so a silent install failure is instead caught by the
# artifact assertions below. With no setsid (rare), a CI runner has no tty anyway.
HAVE_SETSID=0; HAVE_SETSID_W=0
if command -v setsid >/dev/null 2>&1; then
  HAVE_SETSID=1
  setsid -w true >/dev/null 2>&1 && HAVE_SETSID_W=1
fi

LOG=""  # set per combo
run_installer() {  # $1 = installer path; returns its exit status; output appended to $LOG
  if [ "$HAVE_SETSID_W" = 1 ]; then setsid -w sh "$1" </dev/null >>"$LOG" 2>&1
  elif [ "$HAVE_SETSID" = 1 ]; then setsid    sh "$1" </dev/null >>"$LOG" 2>&1
  else                                         sh "$1" </dev/null >>"$LOG" 2>&1
  fi
}
# WORKTREE_TOOLBOX_SRC is exported for the duration of each call so the installer uses the local
# checkout instead of downloading. INSTALL_DIR / VSCODE_KEYBINDINGS_PATH / HOME are exported once
# per combo (below) and inherited by the setsid child.
install_W() { WORKTREE_TOOLBOX_SRC="$W_SRC" run_installer "$W_SRC/install.sh"; }
install_R() { WORKTREE_TOOLBOX_SRC="$R_SRC" run_installer "$R_SRC/install.sh"; }
install_V() { WORKTREE_TOOLBOX_SRC="$V_SRC" run_installer "$V_SRC/install.sh"; }

# ---------------------------------------------------------------------------- assertions
FAILED=0        # any combo failed (process exit code)
COMBO_FAIL=0    # current combo failed
fail() { echo "    x $1"; COMBO_FAIL=1; FAILED=1; }

assert_file()    { [ -f "$1" ] || fail "expected file missing: ${2:-$1}"; }
assert_absent()  { [ -e "$1" ] && fail "unexpected path present: ${2:-$1}"; return 0; }
assert_grep()    { grep -qF "$1" "$2" 2>/dev/null || fail "expected '$1' in ${3:-$2}"; }
count_lines()    { [ -f "$2" ] && grep -cxF "$1" "$2" || echo 0; }  # exact whole-line matches

assert_no_bak() {  # a *.bak proves an installer overwrote a differing existing file → collision
  baks="$(find "$TARGET" -name '*.bak' 2>/dev/null)"
  [ -z "$baks" ] || fail "unexpected .bak files (collision): $(echo "$baks" | tr '\n' ' ')"
}

assert_W() {  # worktree-per-issue artifacts (installed into the target project)
  for f in worktree-create worktree-heal worktree-remove; do
    assert_file "$TARGET/.claude/commands/$f.md"
    # the shared block is inlined at install — each command must be self-contained…
    assert_grep '**Flat name.**'           "$TARGET/.claude/commands/$f.md"
    assert_grep 'Code vs context isolation' "$TARGET/.claude/commands/$f.md"
    # …with no unsubstituted marker and no runtime cat-injection left behind
    grep -qF '{{WORKTREE_SHARED}}' "$TARGET/.claude/commands/$f.md" && fail "unsubstituted {{WORKTREE_SHARED}} in $f.md"
    grep -qF '!`cat'               "$TARGET/.claude/commands/$f.md" && fail "leftover !\`cat injection in $f.md"
  done
  # the shared block is a toolbox-side build input — it must NOT be shipped into the target
  assert_absent "$TARGET/.claude/worktree-shared.md" "worktree-shared.md should not be installed"
  assert_file "$TARGET/.husky/post-checkout"
  assert_file "$TARGET/scripts/worktree-setup.sh"
  assert_file "$TARGET/docs/worktrees.md"
  assert_file "$TARGET/.worktreeinclude"
  assert_grep 'Bash(git worktree *)' "$TARGET/.claude/settings.json"
  assert_grep 'git.detectWorktrees'  "$TARGET/.vscode/settings.json"
  [ "$(count_lines '.claude/worktrees/' "$TARGET/.gitignore")" = 1 ] \
    || fail ".claude/worktrees/ not exactly once in .gitignore"
}
assert_R() {  # work-report artifacts
  assert_file "$TARGET/.claude/commands/work-report.md"
  [ "$(count_lines '/WORK-REPORT.md' "$TARGET/.gitignore")" = 1 ] \
    || fail "/WORK-REPORT.md not exactly once in .gitignore"
}
assert_V() {  # vscode-claude-tabs artifacts (user-global, sandboxed)
  assert_file "$SANDBOX_SCRIPTS/gen-claude-tabs-keybinding.js"
  assert_file "$SANDBOX_KEYBINDINGS"
  assert_grep 'runCommands' "$SANDBOX_KEYBINDINGS"
}

# ---------------------------------------------------------------------------- combo runner
TMP_DIRS=""
cleanup() { for d in $TMP_DIRS; do rm -rf "$d"; done; }
trap cleanup EXIT INT TERM

git_init_repo() {  # $1 = dir — throwaway repo with one commit (rev-parse / worktree list need it).
  ( cd "$1" \
      && git init -q \
      && git config user.email test@example.invalid \
      && git config user.name  smoke-test \
      && : > placeholder && git add -A && git commit -qm init ) 2>/dev/null
}

begin_combo() {  # fresh sandboxed target repo + per-combo env; sets TARGET/LOG, resets COMBO_FAIL, cds in.
  TARGET="$(mktemp -d)"; SANDBOX_HOME="$(mktemp -d)"; LOG="$(mktemp)"
  TMP_DIRS="$TMP_DIRS $TARGET $SANDBOX_HOME $LOG"
  SANDBOX_SCRIPTS="$SANDBOX_HOME/.claude/scripts"
  SANDBOX_KEYBINDINGS="$SANDBOX_HOME/keybindings.json"
  export HOME="$SANDBOX_HOME"
  export INSTALL_DIR="$SANDBOX_SCRIPTS"
  export VSCODE_KEYBINDINGS_PATH="$SANDBOX_KEYBINDINGS"
  COMBO_FAIL=0
  # No .gitignore yet, so we can prove V-alone creates none and that W/R create theirs.
  git_init_repo "$TARGET" || fail "throwaway repo init failed"
  cd "$TARGET" || fail "cannot cd into target"
}

report_combo() {  # $1 = label — back to the repo, print PASS/FAIL, and on failure tail the installer log.
  cd "$REPO" || true
  if [ "$COMBO_FAIL" = 0 ]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n' "$1"
    echo   "      --- installer log (tail) ---"
    tail -n 20 "$LOG" 2>/dev/null | sed 's/^/      /'
  fi
}

run_combo() {  # $1 = human label, $2 = install-order string of letters (e.g. "WR")
  label="$1"; order="$2"
  begin_combo

  # install in the requested order
  i=1
  while [ "$i" -le "${#order}" ]; do
    case "$(printf '%s' "$order" | cut -c "$i")" in
      W) install_W || fail "worktree-per-issue installer exited nonzero" ;;
      R) install_R || fail "work-report installer exited nonzero" ;;
      V) install_V || fail "vscode-claude-tabs installer exited nonzero" ;;
    esac
    i=$((i + 1))
  done

  # per-tool artifact assertions
  case "$order" in *W*) assert_W ;; esac
  case "$order" in *R*) assert_R ;; esac
  case "$order" in *V*) assert_V ;; esac
  assert_no_bak
  # V installed alone must leave the project completely untouched
  if [ "$order" = "V" ]; then
    assert_absent "$TARGET/.claude"        "V wrote into the project (.claude)"
    assert_absent "$TARGET/.worktreeinclude" "V wrote .worktreeinclude"
    assert_absent "$TARGET/.gitignore"     "V created a .gitignore"
  fi

  # idempotency: reinstall every tool in the combo once more — no clobbers, no duplicate ignores
  case "$order" in *W*) install_W || fail "worktree-per-issue reinstall exited nonzero" ;; esac
  case "$order" in *R*) install_R || fail "work-report reinstall exited nonzero" ;; esac
  case "$order" in *V*) install_V || fail "vscode-claude-tabs reinstall exited nonzero" ;; esac
  assert_no_bak
  case "$order" in *W*) [ "$(count_lines '.claude/worktrees/' "$TARGET/.gitignore")" = 1 ] \
      || fail ".claude/worktrees/ duplicated in .gitignore after reinstall" ;; esac
  case "$order" in *R*) [ "$(count_lines '/WORK-REPORT.md' "$TARGET/.gitignore")" = 1 ] \
      || fail "/WORK-REPORT.md duplicated in .gitignore after reinstall" ;; esac

  report_combo "$label"
}

# ---------------------------------------------------------------------------- env-override test
# The non-interactive escape hatches are the ONLY way to configure a `curl | sh` install (no TTY),
# so they need explicit coverage. Install W with both set and assert the overrides reached the
# templated output — this guards the two things that had to be hand-corrected downstream.
run_env_override_test() {
  label="ENV      (worktree-per-issue honors WORKTREE_TOOLBOX_PM_INSTALL / _PROVISION)"
  begin_combo

  ov_install="npm run init"; ov_step1="npm run codegen"; ov_step2="npm run build:proto"
  WORKTREE_TOOLBOX_PM_INSTALL="$ov_install" \
  WORKTREE_TOOLBOX_PROVISION="$(printf '%s\n%s\n' "$ov_step1" "$ov_step2")" \
    install_W || fail "worktree-per-issue installer (env overrides) exited nonzero"

  # the overridden install command must be templated in place of the 'npm install' default
  assert_grep "$ov_install" "$TARGET/scripts/worktree-setup.sh"
  assert_grep "$ov_install" "$TARGET/docs/worktrees.md"
  # each provisioning step must land as a guarded ( cd "$WT" && <cmd> ) line
  assert_grep "$ov_step1" "$TARGET/scripts/worktree-setup.sh"
  assert_grep "$ov_step2" "$TARGET/scripts/worktree-setup.sh"

  report_combo "$label"
}

# ---------------------------------------------------------------------------- run the matrix
echo "worktree-toolbox install-combination smoke test"
echo "  W=worktree-per-issue  R=work-report  V=vscode-claude-tabs"
[ "$HAVE_SETSID" = 1 ] || echo "  note: setsid not found — relying on the absence of a controlling terminal."
echo ""

run_combo "W        (worktree-per-issue alone)" "W"
run_combo "R        (work-report alone)"        "R"
run_combo "V        (vscode-claude-tabs alone)" "V"
run_combo "W,R      (install order W -> R)"      "WR"
run_combo "W,R      (install order R -> W)"      "RW"
run_combo "W,V"                                  "WV"
run_combo "R,V"                                  "RV"
run_combo "W,R,V"                                "WRV"
run_env_override_test

echo ""
if [ "$FAILED" = 0 ]; then
  echo "All combinations passed."
  exit 0
else
  echo "Some combinations FAILED (see above)."
  exit 1
fi
