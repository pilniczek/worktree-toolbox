# work-report

A one-line installer that adds a **`/work-report`** slash command to any git repo run with
[Claude Code](https://claude.com/claude-code). It writes a standardized **work report** —
`WORK-REPORT.md` — summarizing what an agent did.

> Part of [worktree-toolbox](../README.md). Installs INTO a target project
> (`.claude/commands/work-report.md` + a `.gitignore` entry).

When an agent declares work "done," `/work-report` leaves a real file on disk that another
agent (a reviewer, or a fresh session continuing the work) can read *instead of* re-deriving
intent from the raw diff. The point is **efficiency**: a concise report is a faster substrate
for the next step than studying the changes.

It works **anywhere** - a git worktree, the main checkout, or any git repo. It does **not**
require a worktree, so it's useful on its own or alongside any worktree-based workflow.

## One living report per working tree

There is **one report per working tree** - `WORK-REPORT.md` at its root
(`git rev-parse --show-toplevel`) - and each run **overwrites** it, so it always reflects the
current state, never a pile of fragments:

- **Resumed over time** (day 1 unfinished → day 2 → day 3): each run replaces the last, so a
  reviewer at the end reads exactly **one** report. No cleanup step.
- **Resuming and reviewing are just *reading*** it - a session picking the work back up reads
  it to regain context; a reviewer reads it to assess. Neither needs a command; only
  `/work-report` writes.

## The six sections

The report has six sections — **Goal**, **Problem → Solution**, **Verification**, **Follow-ups**,
**Suggested skills**, and **Abandoned approaches** (omitted if none). The
exact contract for each — what belongs in it and how it's written — lives in the command itself
([`template/.claude/commands/work-report.md`](template/.claude/commands/work-report.md)),
which is the single source of truth; this README only names them.

The report references artifacts (PRs, diffs, ADRs) rather than duplicating them - it deliberately
does **not** restate the git diff (commits, changed files); a reader gets those from git/the PR.
Its value is the intent, reasoning, verification, and next steps the diff **cannot** show. Each run
reads the existing report first and builds on it. Secrets are **redacted** - any API key, password,
token, credential, or PII is noted by name and location, never reproduced by value.

## Install

Run from **inside the target git repo**:

```sh
curl -fsSL https://raw.githubusercontent.com/pilniczek/worktree-toolbox/main/work-report/install.sh | sh
```

On native Windows, run this in **Git Bash** (not CMD/PowerShell). See the [toolbox README](../README.md#install).

It adds `.claude/commands/work-report.md` and a `WORK-REPORT.md` entry to `.gitignore`. An
existing command file it replaces is overwritten in place (review with `git diff`);
re-running changes nothing twice.

## Where it lives, and git

`WORK-REPORT.md` is **gitignored by default** so it stays a local working artifact and never
pollutes the branch diff. To hand it to a reviewer working from the PR (not the working-tree
filesystem), commit it deliberately with `git add -f WORK-REPORT.md`.

## It is a self-report, not proof

The report is the author's account of intent and reasoning, built for **efficiency of the next
step** - a fast, trustworthy-enough summary that points *at* the changes, not an audit and not a
substitute for reviewing the diff when correctness matters.

## Requirements

- `git`; `curl` + `tar` for the hosted one-liner.

## Local development / testing

```sh
# from a checkout of this repo, against some target project (run inside it):
WORKTREE_TOOLBOX_SRC="$(pwd)/work-report" sh work-report/install.sh
```

Env overrides: `WORKTREE_TOOLBOX_REPO` (owner/repo), `WORKTREE_TOOLBOX_REF` (branch/tag),
`WORKTREE_TOOLBOX_SRC` (local source dir, skips the download).
