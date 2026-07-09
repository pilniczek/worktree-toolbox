<!--
  Single source of truth for behavior shared by the /worktree-create, /worktree-heal, and /worktree-remove slash commands
  (Validation, the flat-name rule, the worktree setup, the code-vs-context isolation note).

  This is a BUILD INPUT, not a file that ships to targets. At install, install.sh substitutes {{WORKTREE_SETUP_SUMMARY}}
  below and then inlines this whole block in place of the {{WORKTREE_SHARED}} placeholder at the bottom of each command
  file (see worktree-per-issue/install.sh). The installed commands are therefore self-contained — this file is never copied
  into the target repo.

  Edit shared worktree behavior HERE, once, then re-run the installer. Full narrative: docs/worktrees.md.
-->

The numbered steps above rely on these shared conventions — apply them exactly.

**Validation.** `$ARGUMENTS` must be non-empty and look like a branch path (contains `/`, no spaces). If not, STOP and
ask me for the full branch name.

**Flat name.** The worktree directory is `.claude/worktrees/<flat>`, where `<flat>` is `$ARGUMENTS` with every `/`
replaced by `+` (e.g. `feature/abc/TICKET-123/some-slug` → `feature+abc+TICKET-123+some-slug`). Leave the directory name
exactly as produced — never rename the folder.

**Worktree setup.** Provisioning runs `scripts/worktree-setup.sh`: {{WORKTREE_SETUP_SUMMARY}} It also copies your
gitignored local config listed in `.worktreeinclude` into the worktree (plain `git worktree add` does not do this
itself). It runs **once when the worktree is created** — `/worktree-create` invokes it as its **Provision** step, and
`.husky/post-checkout` runs it too for a bare-CLI `git worktree add`. A run-once marker makes a repeat trigger a no-op,
so re-entering an existing worktree does **not** re-provision. If a worktree is broken or stale, run `/worktree-heal` (worktree
heal) to force a full rebuild (`scripts/worktree-setup.sh --force`).

**Code vs context isolation.** Creating the worktree gives **code** isolation (its own dir + branch); `/worktree-create` then uses
`EnterWorktree` to move you into it so you can start working right away. That relocation is _not_ context isolation — it
is the same session. For a **separate** context (e.g. a different issue in parallel), open a separate Claude session in
that worktree dir (`cd .claude/worktrees/<flat>` and start Claude there). Do **not** open a new VS Code window
(`code <path>`) or launch a terminal on my behalf.

See `docs/worktrees.md` for the full flow.
