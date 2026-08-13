#!/usr/bin/env sh
# Install smoke test for worktree-toolbox (worktree-per-issue).
# Offline and sandboxed; see "How to test" in ../AGENTS.md for the contract.
# Requires: git, node, sh.  Run from anywhere:  sh test/install-matrix.sh
set -u

# --- locate repo ---------------------------------------------------------------------------
# This script lives in <repo>/test/.
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
W_SRC="$REPO/worktree-per-issue"

command -v git  >/dev/null 2>&1 || { echo "git is required."  >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node is required." >&2; exit 1; }

# --- runner --------------------------------------------------------------------------------
# The installer prompts when it can open /dev/tty; on a developer terminal that would hang the
# test. Detach from the controlling terminal so /dev/tty can't be opened and the installer falls
# back to its defaults. `setsid -w` waits and forwards the child's exit status; plain `setsid` may
# fork and lose it, so a silent install failure is instead caught by the artifact assertions below.
# With no setsid (rare), a CI runner has no tty anyway.
HAVE_SETSID=0; HAVE_SETSID_W=0
if command -v setsid >/dev/null 2>&1; then
  HAVE_SETSID=1
  setsid -w true >/dev/null 2>&1 && HAVE_SETSID_W=1
fi

LOG=""  # set per case
run_installer() {  # $1 = installer path; returns its exit status; output appended to $LOG
  if [ "$HAVE_SETSID_W" = 1 ]; then setsid -w sh "$1" </dev/null >>"$LOG" 2>&1
  elif [ "$HAVE_SETSID" = 1 ]; then setsid    sh "$1" </dev/null >>"$LOG" 2>&1
  else                                         sh "$1" </dev/null >>"$LOG" 2>&1
  fi
}
# WORKTREE_TOOLBOX_SRC is exported for the duration of each call so the installer uses the local
# checkout instead of downloading. INSTALL_DIR / HOME are exported once per case (below) and
# inherited by the setsid child.
install_W() { WORKTREE_TOOLBOX_SRC="$W_SRC" run_installer "$W_SRC/install.sh"; }

# --- assertions ----------------------------------------------------------------------------
FAILED=0       # any case failed (process exit code)
CASE_FAIL=0    # current case failed
fail() { echo "    x $1"; CASE_FAIL=1; FAILED=1; }

assert_file()    { [ -f "$1" ] || fail "expected file missing: ${2:-$1}"; }
assert_absent()  { [ -e "$1" ] && fail "unexpected path present: ${2:-$1}"; return 0; }
assert_grep()    { grep -qF "$1" "$2" 2>/dev/null || fail "expected '$1' in ${3:-$2}"; }
count_lines()    { [ -f "$2" ] && grep -cxF "$1" "$2" || echo 0; }  # exact whole-line matches

assert_no_clobber() {  # a "~ (replaced)" line proves the installer overwrote a differing existing file
  clob="$(grep -F '  ~ ' "$LOG" 2>/dev/null || true)"
  [ -z "$clob" ] || fail "installer clobbered a differing existing file: $(echo "$clob" | tr '\n' ' ')"
}

assert_W() {  # worktree-per-issue artifacts (installed into the target project)
  for f in worktree-create worktree-heal worktree-remove; do
    assert_file "$TARGET/.claude/commands/$f.md"
    # each command is a thin wrapper that invokes its script and relays the output
    assert_grep "sh scripts/$f.sh" "$TARGET/.claude/commands/$f.md"
    # the logic lives in scripts, not the prompt — the old inlined shared block must be gone
    grep -qF '{{WORKTREE_SHARED}}' "$TARGET/.claude/commands/$f.md" && fail "unsubstituted {{WORKTREE_SHARED}} in $f.md"
    grep -qF '**Flat name.**'      "$TARGET/.claude/commands/$f.md" && fail "shared block leaked into $f.md (should be script-only)"
    # the matching script must ship, and its permission entry must be granted (one per command)
    assert_file "$TARGET/scripts/$f.sh"
    assert_grep "Bash(sh scripts/$f.sh*)" "$TARGET/.claude/settings.json"
  done
  assert_file "$TARGET/scripts/worktree-common.sh"      # shared rules sourced by the three scripts
  # the shared markdown is a deleted build input — it must NOT be shipped into the target
  assert_absent "$TARGET/.claude/worktree-shared.md" "worktree-shared.md should not be installed"
  assert_file "$TARGET/.husky/post-checkout"
  assert_file "$TARGET/scripts/worktree-setup.sh"
  assert_file "$TARGET/docs/worktrees.md"
  assert_file "$TARGET/.worktreeinclude"
  assert_grep 'Bash(git worktree *)'  "$TARGET/.claude/settings.json"   # kept for manual use
  assert_grep 'git.detectWorktrees'   "$TARGET/.vscode/settings.json"
  [ "$(count_lines '.claude/worktrees/' "$TARGET/.gitignore")" = 1 ] \
    || fail ".claude/worktrees/ not exactly once in .gitignore"
}

# --- cases ---------------------------------------------------------------------------------
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

begin_case() {  # fresh sandboxed target repo + per-case env; sets TARGET/LOG, resets CASE_FAIL, cds in.
  TARGET="$(mktemp -d)"; SANDBOX_HOME="$(mktemp -d)"; LOG="$(mktemp)"
  TMP_DIRS="$TMP_DIRS $TARGET $SANDBOX_HOME $LOG"
  export HOME="$SANDBOX_HOME"
  export INSTALL_DIR="$SANDBOX_HOME/.claude/scripts"
  CASE_FAIL=0
  # No .gitignore yet, so we can prove the installer creates its own.
  git_init_repo "$TARGET" || fail "throwaway repo init failed"
  cd "$TARGET" || fail "cannot cd into target"
}

report_case() {  # $1 = label — back to the repo, print PASS/FAIL, and on failure tail the installer log.
  cd "$REPO" || true
  if [ "$CASE_FAIL" = 0 ]; then
    printf 'PASS  %s\n' "$1"
  else
    printf 'FAIL  %s\n' "$1"
    echo   "      --- installer log (tail) ---"
    tail -n 20 "$LOG" 2>/dev/null | sed 's/^/      /'
  fi
}

run_install_test() {
  label="INSTALL  (worktree-per-issue install + reinstall is idempotent)"
  begin_case

  install_W || fail "worktree-per-issue installer exited nonzero"
  assert_W
  assert_no_clobber

  # idempotency: reinstall once more — no clobbers, no duplicate ignores
  install_W || fail "worktree-per-issue reinstall exited nonzero"
  assert_no_clobber
  [ "$(count_lines '.claude/worktrees/' "$TARGET/.gitignore")" = 1 ] \
    || fail ".claude/worktrees/ duplicated in .gitignore after reinstall"

  report_case "$label"
}

# --- env override --------------------------------------------------------------------------
# The non-interactive escape hatches are the ONLY way to configure a `curl | sh` install (no TTY),
# so they need explicit coverage. Install with both set and assert the overrides reached the
# templated output — this guards the two things that had to be hand-corrected downstream.
run_env_override_test() {
  label="ENV      (worktree-per-issue honors WORKTREE_TOOLBOX_PM_INSTALL / _PROVISION)"
  begin_case

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

  report_case "$label"
}

# --- run -----------------------------------------------------------------------------------
echo "worktree-toolbox install smoke test"
[ "$HAVE_SETSID" = 1 ] || echo "  note: setsid not found — relying on the absence of a controlling terminal."
echo ""

run_install_test
run_env_override_test

echo ""
if [ "$FAILED" = 0 ]; then
  echo "All cases passed."
  exit 0
else
  echo "Some cases FAILED (see above)."
  exit 1
fi
