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
# test. Detach from the controlling terminal so /dev/tty can't be opened and the installer skips
# its prompts. `setsid -w` waits and forwards the child's exit status; plain `setsid` may
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
assert_grep()    { grep -qF -e "$1" "$2" 2>/dev/null || fail "expected '$1' in ${3:-$2}"; }
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
  assert_absent "$TARGET/scripts/worktree-setup.sh" "worktree-setup.sh should not be installed"
  assert_file "$TARGET/docs/worktrees.md"
  assert_grep '--repo' "$TARGET/.claude/commands/worktree-create.md"
  assert_grep 'Worktrees in other repos' "$TARGET/docs/worktrees.md"
  assert_file "$TARGET/.claude/worktree.json"
  assert_file "$TARGET/scripts/worktree-setup.cjs"
  assert_absent "$TARGET/.worktreeinclude" ".worktreeinclude should not be installed"
  grep -qF '{{' "$TARGET/docs/worktrees.md" && fail "template token left in docs/worktrees.md"
  assert_grep 'Bash(git worktree *)'  "$TARGET/.claude/settings.json"   # kept for manual use
  assert_grep 'git.detectWorktrees'   "$TARGET/.vscode/settings.json"
  [ "$(count_lines '.claude/worktrees/' "$TARGET/.gitignore")" = 1 ] \
    || fail ".claude/worktrees/ not exactly once in .gitignore"
}

# --- cases ---------------------------------------------------------------------------------
TMP_DIRS=""
cleanup() { for d in $TMP_DIRS; do rm -rf "$d"; done; }
trap cleanup EXIT INT TERM

if [ -n "${TEST_SH:-}" ]; then
  TEST_SH_PATH="$(command -v "$TEST_SH")" || { echo "TEST_SH '$TEST_SH' not found." >&2; exit 1; }
  SH_SHIM="$(mktemp -d)"; TMP_DIRS="$TMP_DIRS $SH_SHIM"
  ln -s "$TEST_SH_PATH" "$SH_SHIM/sh"
  PATH="$SH_SHIM:$PATH"; export PATH
fi

git_init_repo() {  # $1 = dir — throwaway repo with one commit (rev-parse / worktree list need it).
  ( cd "$1" \
      && git init -q \
      && git config user.email test@example.invalid \
      && git config user.name  smoke-test \
      && : > placeholder && git add -A && git commit -qm init ) 2>/dev/null
}

begin_case() {  # fresh sandboxed target repo + per-case env; sets PARENT/TARGET/LOG, resets CASE_FAIL, cds in.
  PARENT="$(cd "$(mktemp -d)" && pwd -P)"; TARGET="$PARENT/repo"; mkdir "$TARGET"
  SANDBOX_HOME="$(mktemp -d)"; LOG="$(mktemp)"
  TMP_DIRS="$TMP_DIRS $PARENT $SANDBOX_HOME $LOG"
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

# Git Bash: git prints C:/... and node prints C:\... for a path the shell sees as /tmp/...
if command -v cygpath >/dev/null 2>&1; then
  git_path()  { cygpath -m "$1"; }
  node_path() { cygpath -w "$1"; }
else
  git_path()  { printf '%s' "$1"; }
  node_path() { printf '%s' "$1"; }
fi

json_equals() {
  node -e 'const fs=require("fs"); const a=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.exit(JSON.stringify(a)===JSON.stringify(JSON.parse(process.argv[2]))?0:1)' "$1" "$2" 2>/dev/null
}

run_install_test() {
  label="INSTALL  (empty config, reinstall is idempotent and keeps the config)"
  begin_case

  install_W || fail "worktree-per-issue installer exited nonzero"
  assert_W
  assert_no_clobber
  json_equals .claude/worktree.json '{"copy":[],"hardlink":[],"link":[],"steps":[]}' \
    || fail "new config is not empty: $(tr '\n' ' ' < .claude/worktree.json)"

  # idempotency: reinstall once more — no clobbers, no duplicate ignores
  install_W || fail "worktree-per-issue reinstall exited nonzero"
  assert_no_clobber
  [ "$(count_lines '.claude/worktrees/' "$TARGET/.gitignore")" = 1 ] \
    || fail ".claude/worktrees/ duplicated in .gitignore after reinstall"

  printf '{ "steps": ["make gen"] }\n' > .claude/worktree.json; cp .claude/worktree.json "$PARENT/edited"
  install_W || fail "reinstall over an edited config exited nonzero"
  cmp -s .claude/worktree.json "$PARENT/edited" || fail "reinstall changed an existing config"
  assert_grep 'edit .claude/worktree.json to change worktree setup' "$LOG" "installer log"

  report_case "$label"
}

# --- setup ---------------------------------------------------------------------------------
assert_clean() {  # $1 = step label
  st="$(git -C "$TARGET" status --porcelain 2>&1)"
  [ -z "$st" ] || fail "git status not clean after $1: $(echo "$st" | tr '\n' ' ')"
}

resolves_to() {
  [ "$(cd "$1" 2>/dev/null && pwd -P)" = "$2" ]
}

run_setup_test() {
  label="SETUP    (copy/hardlink/link/steps, marker, --force; create/heal/remove keep status clean)"
  begin_case

  printf 'main\n' > .env
  mkdir -p cfg node_modules/pkg fixtures/big .claude
  printf '{}\n' > cfg/local.json; : > node_modules/pkg/index.js; : > fixtures/big/data
  printf '%s\n' .env cfg/ node_modules/ fixtures/ step-ran > .gitignore
  cat > .claude/worktree.json <<'JSON'
{
  "copy": [".env", "cfg/local.json", "absent.txt"],
  "hardlink": ["node_modules"],
  "link": ["fixtures/big"],
  "steps": ["printf x >> step-ran", "false"]
}
JSON
  install_W || fail "installer exited nonzero"

  git add -A && git commit -qm install
  add_origin "$TARGET" || fail "origin setup failed"
  git config core.hooksPath .husky
  assert_clean "install"

  branch="feature/t/T-1/setup"; wt="$TARGET/.claude/worktrees/feature+t+T-1+setup"
  sh scripts/worktree-create.sh "$branch" >>"$LOG" 2>&1 || fail "worktree-create exited nonzero"
  [ -f "$wt/.env" ] && [ ! -L "$wt/.env" ] && [ ! "$wt/.env" -ef .env ] || fail ".env is not a real copy"
  [ -f "$wt/cfg/local.json" ] && [ ! "$wt/cfg/local.json" -ef cfg/local.json ] || fail "cfg/local.json is not a real copy"
  [ -d "$wt/node_modules" ] && [ ! -L "$wt/node_modules" ] || fail "node_modules is not a real dir"
  [ "$wt/node_modules/pkg/index.js" -ef node_modules/pkg/index.js ] || fail "node_modules files are not hardlinked"
  [ -L "$wt/fixtures/big" ] && resolves_to "$wt/fixtures/big" "$TARGET/fixtures/big" || fail "fixtures/big is not a link to main"
  assert_grep 'absent.txt' "$LOG" "create output (missing source)"
  assert_grep "'false' failed" "$LOG" "create output (failing step)"
  [ "$(cat "$wt/step-ran" 2>/dev/null)" = x ] || fail "steps did not run exactly once on create"
  assert_file "$(git -C "$wt" rev-parse --git-dir)/wt-provisioned" "run-once marker"
  assert_clean "create"

  printf 'edited\n' > "$wt/.env"; rm "$wt/cfg/local.json"
  node "$TARGET/scripts/worktree-setup.cjs" setup "$wt" >>"$LOG" 2>&1 || fail "plain setup rerun exited nonzero"
  [ "$(cat "$wt/.env")" = edited ] || fail "setup overwrote an existing target"
  assert_file "$wt/cfg/local.json" "cfg/local.json recreated on rerun"
  [ "$(cat "$wt/step-ran")" = x ] || fail "steps re-ran without --force"

  node "$TARGET/scripts/worktree-setup.cjs" setup "$PARENT/typo/wt" >"$PARENT/setup.out" 2>&1 \
    && fail "setup accepted a path that is not a worktree"
  assert_absent "$PARENT/typo" "setup target outside any worktree"
  assert_grep 'is not a worktree of' "$PARENT/setup.out" "setup output (not a worktree)"
  grep -qF '    at ' "$PARENT/setup.out" && fail "setup printed a stack trace"
  node "$TARGET/scripts/worktree-setup.cjs" setup "$TARGET" >>"$LOG" 2>&1 && fail "setup accepted the main checkout"
  assert_absent "$TARGET/step-ran" "steps run in the main checkout"
  assert_absent "$TARGET/.git/wt-provisioned" "marker in the main checkout"

  git worktree add -q "$TARGET/.claude/worktrees/bare-cli" -b feature/t/T-1/bare-cli >"$PARENT/hook.out" 2>&1
  grep -qF "'false' failed" "$PARENT/hook.out" || fail "hook did not run the setup: $(tr '\n' ' ' < "$PARENT/hook.out")"
  grep -qF 'worktree ready.' "$PARENT/hook.out" && fail "hook reported ready after a failed step"
  node "$TARGET/scripts/worktree-setup.cjs" unlink "$TARGET/.claude/worktrees/bare-cli" >>"$LOG" 2>&1
  git worktree remove --force "$TARGET/.claude/worktrees/bare-cli" 2>/dev/null

  rm "$wt/fixtures/big"
  sh scripts/worktree-heal.sh "$branch" >>"$LOG" 2>&1 && fail "worktree-heal exited zero despite a failing step"
  [ "$(cat "$wt/step-ran")" = xx ] || fail "heal did not re-run the steps"
  [ -L "$wt/fixtures/big" ] || fail "heal did not recreate the fixtures/big link"
  assert_clean "heal"

  node "$TARGET/scripts/worktree-setup.cjs" unlink "$wt" >>"$LOG" 2>&1 || fail "unlink exited nonzero"
  assert_absent "$wt/fixtures/big" "fixtures/big link after unlink"
  assert_file "$TARGET/fixtures/big/data" "main's linked data after unlink"
  : > "$wt/untracked"; rm "$wt/cfg/local.json"
  sh scripts/worktree-remove.sh "$branch" >>"$LOG" 2>&1 && fail "worktree-remove removed a dirty worktree"
  [ -L "$wt/fixtures/big" ] || fail "stopped remove did not restore the fixtures/big link"
  assert_absent "$wt/cfg/local.json" "copy entry recreated by a stopped remove"
  rm "$wt/untracked"

  sh scripts/worktree-remove.sh "$branch" >>"$LOG" 2>&1 || fail "worktree-remove exited nonzero"
  assert_absent "$wt" "worktree dir after remove"
  assert_file "$TARGET/fixtures/big/data" "main's linked data after remove"
  assert_clean "remove"

  report_case "$label"
}

# --- other repos ---------------------------------------------------------------------------
add_origin() {  # $1 = repo dir - bare clone beside it as origin, with origin/HEAD set.
  git clone -q --bare "$1" "$1.git" \
    && git -C "$1" remote add origin "$1.git" \
    && git -C "$1" fetch -q origin \
    && git -C "$1" remote set-head -a origin >/dev/null
}

make_repo() {  # $1 = dir (may already hold files to commit) - committed repo with a bare origin.
  mkdir -p "$1" && git_init_repo "$1" && add_origin "$1"
}

run_repo_test() {
  label="REPO     (create --repo: minimal mode, relative path, hand-off by config file, STOP paths)"
  begin_case

  : > .env; mkdir .claude
  printf '{"copy":[".env"]}\n' > .claude/worktree.json
  install_W || fail "installer (A) exited nonzero"
  printf '%s\n' .env >> .gitignore
  git add -A && git commit -qm install && add_origin "$TARGET" || fail "repo A setup failed"

  shim="$PARENT/shim"; mkdir "$shim"
  printf '#!/bin/sh\npwd > npm-ran\n' > "$shim/npm"; chmod +x "$shim/npm"
  saved_path="$PATH"; PATH="$shim:$PATH"; export PATH

  B="$PARENT/b repo"; mkdir "$B"; printf '{}\n' > "$B/package-lock.json"
  make_repo "$B" || fail "repo B setup failed"
  : > "$B/.env"

  C="$PARENT/c"; mkdir "$C"; git_init_repo "$C" || fail "repo C init failed"
  ( cd "$C" && install_W ) || fail "installer (C) exited nonzero"
  ( cd "$C" && git add -A && git commit -qm install ) && add_origin "$C" || fail "repo C setup failed"

  D="$PARENT/d"; mkdir -p "$D/scripts/worktree"
  cat > "$D/scripts/worktree/create.sh" <<'STUB'
pwd > "$PWD/stub-cwd"; printf '%s\n' "$1" > "$PWD/stub-arg"; printf 'WORKTREE_PATH=stub\n'
STUB
  make_repo "$D" || fail "repo D setup failed"

  E="$PARENT/e"; mkdir -p "$E/.claude"; printf '{}\n' > "$E/.claude/worktree.json"
  make_repo "$E" || fail "repo E setup failed"

  mkdir "$PARENT/not-a-repo"

  branch="feature/t/T-2/multi"; flat="feature+t+T-2+multi"
  create() { sh scripts/worktree-create.sh "$@" >>"$LOG" 2>&1; }
  minimal_lines() { grep -c '^MINIMAL WORKTREE:' "$LOG"; }

  bwt="$B/.claude/worktrees/$flat"
  create "$branch" --repo "$B" || fail "create --repo B exited nonzero"
  [ -d "$bwt" ] || fail "B worktree missing"
  [ "$(git -C "$bwt" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "$branch" ] || fail "B worktree not on $branch"
  assert_absent "$bwt/npm-ran" "package install in minimal worktree"
  assert_grep 'MINIMAL WORKTREE:' "$LOG" "create output"
  assert_grep "WORKTREE_PATH=$(git_path "$bwt")" "$LOG" "create output"
  assert_absent "$bwt/.env" ".env copied into minimal worktree"

  create --repo "$bwt" feature/t/T-3/other || fail "create --repo <B worktree> exited nonzero"
  [ -d "$B/.claude/worktrees/feature+t+T-3+other" ] || fail "--repo <B worktree> did not resolve to B main"

  before="$(minimal_lines)"
  create "$branch" --repo "$C" || fail "create --repo C exited nonzero"
  assert_grep "WORKTREE_PATH=$(git_path "$C/.claude/worktrees/$flat")" "$LOG" "create output"
  [ "$(minimal_lines)" = "$before" ] || fail "toolbox repo C got a minimal worktree"

  before="$(minimal_lines)"
  create "$branch" --repo "$D" || fail "create --repo D exited nonzero"
  [ "$(minimal_lines)" = "$((before + 1))" ] || fail "repo without worktree.json did not get a minimal worktree"
  assert_absent "$D/stub-arg" "older-layout script ran"
  [ -d "$D/.claude/worktrees/$flat" ] || fail "D worktree missing"

  create "$branch" --repo "$E" && fail "--repo <config without script> did not STOP"
  assert_grep 'no scripts/worktree-create.sh' "$LOG" "create output"
  assert_absent "$E/.claude/worktrees/$flat" "E worktree after STOP"

  git -C "$B" worktree add -q "$PARENT/stray" -b feature/t/T-4/x 2>/dev/null
  create feature/t/T-4/x --repo "$B" && fail "branch checked out elsewhere did not STOP"
  assert_absent "$B/.claude/worktrees/feature+t+T-4+x" "worktree dir after STOP"

  create "$branch" --repo "$TARGET" && fail "--repo <A main> did not STOP"
  git worktree add -q "$TARGET/.claude/worktrees/own" -b feature/t/T-5/own 2>/dev/null
  create "$branch" --repo "$TARGET/.claude/worktrees/own" && fail "--repo <A worktree> did not STOP"
  assert_absent "$TARGET/.claude/worktrees/$flat" "A worktree after --repo A STOP"
  ( cd "$TARGET/.claude/worktrees/own" && sh scripts/worktree-create.sh feature/t/T-6/rel --repo "../b repo" ) >>"$LOG" 2>&1 \
    || fail "relative --repo from an A worktree exited nonzero"
  [ -d "$B/.claude/worktrees/feature+t+T-6+rel" ] || fail "relative --repo did not resolve against A main"
  create "$branch" --repo "$PARENT/not-a-repo" && fail "--repo <not a repo> did not STOP"
  create "$branch" --repo && fail "--repo without a path did not STOP"
  create feature/t/T-7/twice --repo "$B" --repo "$C" && fail "a second --repo did not STOP"
  assert_absent "$B/.claude/worktrees/feature+t+T-7+twice" "B worktree after a second --repo STOP"
  git clone -q --bare "$B" "$PARENT/bare.git" \
    && git -C "$PARENT/bare.git" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' \
    && git -C "$PARENT/bare.git" fetch -q origin || fail "bare repo setup failed"
  create "$branch" --repo "$PARENT/bare.git" && fail "--repo <bare repo> did not STOP"
  assert_absent "$PARENT/bare.git/.claude" "worktree inside a bare repo"

  assert_clean "create --repo"
  st="$(git -C "$C" status --porcelain 2>&1)"
  [ -z "$st" ] || fail "C status not clean: $(echo "$st" | tr '\n' ' ')"

  PATH="$saved_path"; export PATH
  report_case "$label"
}

run_fallback_test() {
  label="FALLBACK (dir copy, partial copy removed, steps keep stdin)"
  begin_case

  mkdir -p data/sub .claude; : > data/sub/f
  printf '%s\n' data/ got > .gitignore
  printf '%s\n' '{"copy":["data"],"steps":["read x || x=none; printf %s \"$x\" > got"]}' > .claude/worktree.json
  install_W || fail "installer exited nonzero"
  git add -A && git commit -qm install && add_origin "$TARGET" || fail "repo setup failed"

  wt="$TARGET/.claude/worktrees/feature+t+T-8+fb"
  printf 'z\n' | sh scripts/worktree-create.sh feature/t/T-8/fb >>"$LOG" 2>&1 || fail "worktree-create exited nonzero"
  assert_file "$wt/data/sub/f" "copied dir"
  assert_absent "$wt/data/data" "source nested inside the target"
  [ "$(cat "$wt/got" 2>/dev/null)" = z ] || fail "step did not get stdin"

  : > data/sub/locked; chmod 000 data/sub/locked
  if [ -r data/sub/locked ]; then
    echo "      note: running as root, unreadable-file copy failure not checked."
  else
    rm -rf "$wt/data"
    node "$TARGET/scripts/worktree-setup.cjs" setup "$wt" >>"$LOG" 2>&1 && fail "setup exited zero after a failed copy"
    assert_absent "$wt/data" "partial target after a failed copy"
    assert_grep 'could not create' "$LOG" "setup output"
  fi
  chmod 600 data/sub/locked

  report_case "$label"
}

# --- config --------------------------------------------------------------------------------
SETUP_CJS="$W_SRC/template/scripts/worktree-setup.cjs"

bad_config() {  # $1 = config JSON, $2 = expected stderr fragment
  printf '%s\n' "$1" > "$PARENT/worktree.json"
  if node "$SETUP_CJS" check "$PARENT/worktree.json" 2> "$PARENT/err"; then
    fail "config accepted: $1"
    return
  fi
  grep -qF -e "$2" "$PARENT/err" || fail "config '$1': expected '$2' in: $(tr '\n' ' ' < "$PARENT/err")"
  grep -qF -e "$(node_path "$PARENT/worktree.json")" "$PARENT/err" || fail "config '$1': error does not name the file"
}

run_config_test() {
  label="CONFIG   (worktree.json check: valid config silent, every config error rejected)"
  begin_case

  printf '%s\n' '{"copy":[".env","cfg/a b.json"],"hardlink":["node_modules"],"link":["fixtures/big"],"steps":["npm run gen"]}' > "$PARENT/worktree.json"
  node "$SETUP_CJS" check "$PARENT/worktree.json" > "$PARENT/out" 2>&1 && [ ! -s "$PARENT/out" ] || fail "valid config not accepted silently: $(cat "$PARENT/out")"
  printf '{}\n' > "$PARENT/worktree.json"
  node "$SETUP_CJS" check "$PARENT/worktree.json" > "$PARENT/out" 2>&1 && [ ! -s "$PARENT/out" ] || fail "empty config not accepted silently"

  bad_config '{'                                         'not valid JSON'
  bad_config '[]'                                        'must be a JSON object'
  bad_config '{"copyy":[]}'                              'unknown key "copyy"'
  bad_config '{"copy":".env"}'                           '"copy" must be an array of strings'
  bad_config '{"copy":[1]}'                              'copy[0] must be a string'
  bad_config '{"copy":[""]}'                             'copy "": is empty'
  bad_config '{"copy":["/abs"]}'                         'copy "/abs": must be relative'
  bad_config '{"copy":["a/../b"]}'                       'copy "a/../b": must not contain'
  bad_config '{"copy":["./a"]}'                          'copy "./a": must not contain'
  bad_config '{"copy":["a//b"]}'                         'copy "a//b": must not contain'
  bad_config '{"copy":["../x"]}'                         'copy "../x": must not contain'
  bad_config '{"link":["../x"]}'                         'link "../x": must not contain'
  bad_config '{"copy":[".git/config"]}'                  'copy ".git/config": overlaps .git'
  bad_config '{"hardlink":[".git"]}'                     'hardlink ".git": overlaps .git'
  bad_config '{"copy":[".claude/worktrees/x"]}'          'copy ".claude/worktrees/x": overlaps .claude/worktrees'
  bad_config '{"copy":[".claude"]}'                      'copy ".claude": overlaps .claude/worktrees'
  bad_config '{"copy":["a"],"link":["a"]}'               'link "a": overlaps copy "a"'
  bad_config '{"copy":["fixtures"],"hardlink":["fixtures/a.json"]}' 'hardlink "fixtures/a.json": overlaps copy "fixtures"'
  bad_config '{"hardlink":["node_modules","node_modules/.cache"]}'  'hardlink "node_modules/.cache": overlaps hardlink "node_modules"'
  bad_config '{"copy":["a\\..\\b"]}'                       'copy "a\..\b": must use / as the separator'
  bad_config '{"copy":[".Git/config"]}'                  'copy ".Git/config": overlaps .git'
  bad_config '{"copy":[".CLAUDE/Worktrees/x"]}'          'copy ".CLAUDE/Worktrees/x": overlaps .claude/worktrees'
  bad_config '{"copy":["Fixtures"],"link":["fixtures/a"]}' 'link "fixtures/a": overlaps copy "Fixtures"'
  bad_config '{"steps":[""]}'                            'steps[0]: is empty'
  bad_config '{"copy":["/x","y"],"steps":"z"}'           'copy "/x": must be relative'
  grep -qF '"steps" must be an array of strings' "$PARENT/err" || fail "errors are not all collected"
  rm -f "$PARENT/init.json"
  node "$SETUP_CJS" init "$PARENT/init.json" copy 'a b.env' steps 'echo "x"' copy .env \
    && json_equals "$PARENT/init.json" '{"copy":["a b.env",".env"],"hardlink":[],"link":[],"steps":["echo \"x\""]}' \
    || fail "init did not write the entries in order: $(tr '\n' ' ' < "$PARENT/init.json")"
  node "$SETUP_CJS" init "$PARENT/init.json" 2>/dev/null && fail "init overwrote an existing file"
  for args in '' --frce 'setup' "setup $PARENT --frce" 'unlink' "unlink $PARENT x" 'bogus x' 'check' "init $PARENT/new.json copy" "init $PARENT/new.json bogus x"; do
    ( cd "$PARENT" && node "$SETUP_CJS" $args ) 2> "$PARENT/err"
    [ $? = 2 ] || fail "'$args' did not exit 2"
    grep -qF 'usage:' "$PARENT/err" || fail "'$args' printed no usage"
  done

  install_W || fail "installer exited nonzero"
  git add -A && git commit -qm install && add_origin "$TARGET" || fail "repo setup failed"
  sh scripts/worktree-create.sh feature/t/T-7/cfg >>"$LOG" 2>&1 || fail "worktree-create exited nonzero"
  wt="$TARGET/.claude/worktrees/feature+t+T-7+cfg"
  : > .env
  printf '{"copy":[".env","/abs"]}\n' > .claude/worktree.json
  node "$TARGET/scripts/worktree-setup.cjs" setup "$wt" --force > "$PARENT/setup.out" 2>&1 \
    && fail "setup ran with a bad config"
  assert_grep "$(node_path "$TARGET/.claude/worktree.json")" "$PARENT/setup.out" "setup output (config path)"
  assert_grep 'copy "/abs"' "$PARENT/setup.out" "setup output (offending entry)"
  assert_absent "$wt/.env" ".env created despite a config error"

  mkdir -p blocked && : > blocked/x && : > "$wt/blocked"
  printf '{"copy":["blocked/x"]}\n' > .claude/worktree.json
  node "$TARGET/scripts/worktree-setup.cjs" setup "$wt" --force > "$PARENT/setup.out" 2>&1 \
    && fail "setup exited zero on an entry it cannot create"
  grep -qE 'copy blocked/x: could not create .*: .+' "$PARENT/setup.out" \
    || fail "unplaceable entry warning lacks the reason: $(tr '\n' ' ' < "$PARENT/setup.out")"

  rm .claude/worktree.json
  node "$TARGET/scripts/worktree-setup.cjs" setup "$wt" --force > "$PARENT/setup.out" 2>&1 \
    || fail "setup failed without a config"
  [ "$(grep -c 'no .claude/worktree.json' "$PARENT/setup.out")" = 1 ] || fail "missing config did not warn exactly once"
  assert_absent "$wt/.env" ".env created without a config"

  printf '{"copy":["../x"]}\n' > .claude/worktree.json
  install_W || fail "installer blocked on a bad config"
  assert_grep 'WARN:' "$LOG" "installer log"
  assert_grep 'copy "../x"' "$LOG" "installer log"
  [ "$(cat .claude/worktree.json)" = '{"copy":["../x"]}' ] || fail "installer changed the bad config"

  report_case "$label"
}

# --- run -----------------------------------------------------------------------------------
echo "worktree-toolbox install smoke test"
[ "$HAVE_SETSID" = 1 ] || echo "  note: setsid not found — relying on the absence of a controlling terminal."
echo ""

run_install_test
run_setup_test
run_repo_test
run_config_test
run_fallback_test

echo ""
if [ "$FAILED" = 0 ]; then
  echo "All cases passed."
  exit 0
else
  echo "Some cases FAILED (see above)."
  exit 1
fi
