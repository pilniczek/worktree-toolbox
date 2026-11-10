# 0002 - Repos next to main get their own `repos` key

**Status:** accepted, 2026-11-11

## Context

Projects refer to a repo next to the main checkout as `../other-repo`. A worktree sits at
`<main>/.claude/worktrees/<flat>`, so its `../other-repo` points into `.claude/worktrees/`. A
`link` entry cannot fix this: it maps `<main>/<path>` to `<worktree>/<path>` and refuses `..`.

## Decision

A separate key, `repos`, takes folder names only. For each name, setup keeps one link
`<main>/.claude/worktrees/<name>` to `<main>/../<name>`, shared by every worktree. Setup and heal
replace that link when it is broken. `/worktree-remove` never touches it. `/worktree-create` stops
on a branch whose worktree folder already exists, which covers a name clash with the link.

## Rejected

Accepting `..` in `link`. The entry would then be per-worktree or shared depending on its first
segment, and unlink, relink and remove would each need that hidden special case.

## Reopen when

A project needs a repo that is not next to the main checkout, or worktrees move out of
`.claude/worktrees/`.
