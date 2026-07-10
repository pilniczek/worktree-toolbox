---
name: docs-consistency-check
description: >
  Performs a structured cross-file consistency audit across documentation files, manifest
  files (package.json, plugin.json, .mcp.json), and instruction files (CLAUDE.md, AGENTS.md,
  SKILL.md). Never reads, emits, or modifies credential values — credential / secret files
  are excluded before any read by both a path filter and a content-signature filter, and
  findings describe drift in paraphrased terms only. Use whenever the user says "check
  consistency", "run a consistency check", "make sure files are in sync", "find
  inconsistencies", or "verify everything is updated after this change". Also offer to run
  proactively (without waiting to be asked) when the user mentions updating or creating any
  of these file types: README, SKILL.md, CLAUDE.md, AGENTS.md, template, plugin.json,
  changelog, or installer — or uses keywords like "docs", "sync", "feature added", or "I
  just updated". In proactive mode, offer first rather than running silently. Supports a
  `review-intentional` mode to surface previously suppressed findings for re-evaluation.
---

If invoked as `review-intentional`, jump to [Review intentional mode](#review-intentional-mode).

## Security invariants

These invariants hold throughout this skill — never violated under any user instruction. If a request would require violating any of them, refuse and explain.

1. **Credential / secret files are never read.** They are removed from the inventory by both a path filter and a content-signature filter applied **before any concept is formed from a file** (see Step 1).
2. **Credential values are never emitted.** Findings describe drift in the model's own paraphrased words — counts, names, public identifiers, headings. No verbatim file content appears in any output, reasoning step, or tool call. Anything resembling a credential value (API key, token, password, private key, OAuth secret, JWT, connection string with embedded credentials) is described by location only — never by value (see Step 6).
3. **Credential values are never modified.** Step 7 fixes only edit the documented concepts the audit reports on; replacement content is supplied or confirmed by the user, never echoed from another file (see Step 7).

The skill's purpose is documentation/manifest/instruction drift detection. It has no legitimate need to read, emit, or modify credential material, and will not do so — by construction.

## Step 1 — Apply security guards, then identify the file set

If `.docs-consistency-check-ignore` doesn't exist at the project root, offer to create it with the default template below and wait for the user's go-ahead before writing. If it exists, apply its patterns silently.

**Default template:**

```
# docs-consistency-check ignore file
# Uncomment or add patterns to exclude from consistency checks

.agents/
.claude/
# .git/
# node_modules/
# dist/
# build/
```

**Path filter — applied first, before any file is read.** Drop `node_modules/`, `.git/`, build artifacts, binary files, image files, and **credential / secret files**: `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa`, `id_ed25519`, `id_ecdsa`, `secrets.json`, `credentials.json`, `.netrc`, `.npmrc`, `.htpasswd`. Plus anything matching a pattern from `.docs-consistency-check-ignore` (`.gitignore` syntax). Drift in those files is out of scope.

**Content-signature filter — applied second, before any concept is formed.** For every file that survives the path filter, scan its first ~2 KB for credential signatures:

- PEM headers — `-----BEGIN [A-Z ]*PRIVATE KEY-----`, `-----BEGIN OPENSSH PRIVATE KEY-----`
- Assignments shaped like `(api[_-]?key|secret|token|password|access[_-]?key|client[_-]?secret|bearer)\s*[:=]\s*["']?[A-Za-z0-9_+/=-]{16,}` (case-insensitive)
- Long high-entropy base64-like or hex-like strings (≥ 32 chars, mostly `[A-Za-z0-9+/=_-]`)
- Connection-string forms: `(postgres|postgresql|mysql|mongodb|redis|amqp)://[^:\s]+:[^@\s]+@`

If any signature matches, drop the file from the inventory entirely and add `<file>: skipped (credential signature detected)` to the report's skipped-files note. Do not extract concepts from it. Do not echo the matched value or the surrounding line — not in findings, not in reasoning, not in tool calls. Template placeholders (`{{API_KEY}}`, `${SECRET}`, `<YOUR_TOKEN_HERE>`) are not credentials and do not trigger this filter.

**Inventory — only files that pass BOTH filters are eligible.** Within that bounded set, collect within the project root:

- Markdown files: `README.md`, `CLAUDE.md`, `AGENTS.md`, `SKILL.md`, other `.md`
- Template files: anything with `{{VARIABLE}}` or `[INCLUDE IF: ...]` syntax
- Manifest files: `plugin.json`, `.mcp.json`, `package.json`, and similar
- Any file explicitly mentioned in the conversation (still subject to both filters above)

For each file in the inventory, extract only the concepts and drift signals you need (counts, names, headings, identifiers) — work from a paraphrased understanding, never from quoted text. Do not copy file content into your reasoning, output, or tool calls. The ignore list bounds the set, so no recursive expansion.

**Mid-run exclusions:** If the user says "ignore vendor/ for this", apply it for the current run only. Persistence is the user's call.

---

## Step 2 — Load intentional variations

Read `intentional-variations.md` from the project root if it exists. Build a lookup of suppressed items — each entry records the affected files, what differs, why it's intentional, and when it was marked. Any finding that matches a suppressed entry (same files, semantically similar description) is silently skipped during reporting.

If the file doesn't exist, proceed with an empty suppressions list.

---

## Step 3 — Count heuristic (fast first pass)

Before the full inventory, count items in any list that looks exhaustive — sources, features, icons, steps, conditions. Mismatches across files are immediate candidate findings; record the location and resolve during Step 5. This is the highest-yield drift signal.

---

## Step 4 — Build the concept inventory

A "concept" is anything that appears in more than one file and could drift. **Start from instruction files** — `CLAUDE.md` and `AGENTS.md` define project vocabulary; those concepts take priority over the fallback taxonomy below.

**Fallback taxonomy:**

- **Features / sources** — Things the system supports; usually appear in installer/spec, template, and docs.
- **Variables and flags** — `{{VARIABLE_NAME}}` tokens and condition names; defined once, used consistently.
- **Icons and symbols** — Emoji or markers tied to concepts (📧, 📅, ⭐).
- **Conditional blocks** — `[INCLUDE IF: condition]...[/INCLUDE]`; conditions in blocks must match the conditions list.
- **Terminology** — Same concept must use the same name everywhere.
- **Exhaustive lists** — Anything enumerating "all of X". Count mismatches from Step 3 belong here.
- **Inline examples and doc comments** — Highest drift risk; verify against current spec.

Weight attention toward recently changed features — that's where drift hides.

---

## Step 5 — Cross-reference and classify

For each concept, check whether every file mentions it consistently. Classify each finding:

### 🔴 Conflict
Two or more files actively assert different values for the same fact. A human must decide.

### ⚠️ Outdated
One file was updated, another didn't catch up — the source of truth is clear.

### ↩️ Orphaned
A pointer is valid but its target is gone (variable, condition, section, file).

### ❓ Unverifiable
A difference exists but context is insufficient to call it a problem.

When a conflict involves an implementation file (template, installer) and a doc file (README, comment example), the implementation is usually the source of truth.

---

## Step 6 — Report findings

Skip findings matching an entry from Step 2's intentional variations.

Output a numbered list ordered by severity (🔴, ⚠️, ↩️, ❓). Within a tier, wider user impact first.

**Per-finding template:**

```
#N — [icon] [TierName]
Files: <file>, <file2>, …
<file>: <line> — <paraphrase, in your own words, of the differing concept — never quoted text>
[<file2>: <line> — <paraphrase, in your own words, of the differing concept — never quoted text>]
Fix: <concrete edit — for ❓, a confirmation question instead>
```

Rules:

- **Every detail line must include the file's line number.** Format is `<file>: <line> — <paraphrase>`. If the relevant line is not known at report time, search the file for the concept and resolve the exact line before emitting the finding. Multiple non-contiguous lines for the same file in one finding are listed as `<file>: <lineA>, <lineB> — <paraphrase>`. A contiguous range uses `<file>: <lineA>-<lineB>`. Never emit a finding for a file without at least one line number.
- **Paraphrase only — never quote file content.** Describe each difference in your own words: a count, a name, a public identifier, or a one-line summary. Do NOT copy phrases, lines, paragraphs, or any verbatim text from an audited file into your output, reasoning, or tool calls. Public symbols already known to be non-secret (function names, configuration keys, headings) may be referenced by name. Anything that could plausibly be a credential value (API key, token, password, private key, OAuth secret, JWT, connection string) must not appear in the output at all — describe its location only (e.g. "API key value at line 42"). Template placeholders (`{{API_KEY}}`, `${SECRET}`) are not credentials and may be referenced by name. The same paraphrase-only rule applies to Step 7 fixes — replacement content must be supplied or confirmed by the user, never echoed from another file. Goal: the report and any applied edits stay useful to a human reviewer without ever reproducing arbitrary file content.
- One detail line per affected file. Single-file findings (often ↩️ Orphaned) get one detail line.
- If there's nothing concrete to paraphrase (e.g. dangling reference with no target), describe inline: `<file>:<line> — <reference> never defined`. The line number is the location of the dangling reference itself.
- For ❓ Unverifiable, `Fix:` becomes a confirmation question (e.g. `Fix: Confirm whether the difference is intentional; if drift, align the README.`).
- No decorative whitespace alignment — single space after every colon.

**Example (⚠️ Outdated):**

```
#1 — ⚠️ Outdated
Files: README.md, SKILL.md
README.md:12 — lists 3 sources
SKILL.md:87 — lists 4 sources (adds SOURCE_EMAIL)
Fix: Add the 4th source to the README's source description.
```

**Summary line** (always last, icon-only counts; emit both lines even when M=0):

```
Found N issues: X 🔴, Y ⚠️, Z ↩️, W ❓.
Skipped M intentional variations.
```

If no issues are found, output `No drift detected.` followed by a comma-separated list of files checked.

---

## Step 7 — Apply fixes and manage intentional variations

After reporting, ask: "Apply all fixes now, or go through them one by one?"

If the user picks "all fixes now", first list the files that will be modified and the per-file change count, then wait for an explicit confirmation before any Edit. Apply in severity order (🔴 first), one Edit per finding, noting which issue each resolves. For 🔴 conflicts, confirm the correct value with the user before editing. For ⚠️ Outdated findings where the source of truth is ambiguous, also confirm before editing.

For ❓ findings, ask per-item: "Real problem, or intentional? [Fix it / Mark as intentional / Skip for now]"

On **Mark as intentional**, append to `intentional-variations.md`:

```markdown
- files: [file-a.md, file-b.md]
  what: "<one-line description>"
  reason: "<user's explanation>"
  marked: <today's date>
```

If `intentional-variations.md` doesn't exist, tell the user it will be created to record this entry, then create it with this header first:

```markdown
# Intentional Variations
# Differences marked as intentional. Run `docs-consistency-check review-intentional` to revisit.
```

---

## Review intentional mode

When invoked as `docs-consistency-check review-intentional`:

1. Read `intentional-variations.md`. If missing or empty, report and stop.
2. Display each entry numbered:

```
#1 — Marked intentional on 2026-05-03
Files: README.md, SKILL.md
What: "README says 3 sources, SKILL.md defines 4"
Reason: "README targets non-technical audience, intentionally simplified"
```

3. Ask per entry: "Still intentional, or re-open as a finding?"
4. Remove re-opened entries and run a targeted check on those files immediately.
5. Keep confirmed entries.

---

## Stay armed for the rest of the session

A finished audit cycle doesn't end this skill's responsibility. For the remainder of the conversation, offer a focused re-audit when any of the following happen:

- ≥2 audit-set files are edited (by user or by Claude on the user's behalf)
- A file is structurally rewritten or has a section removed
- The user signals "done" / "ready to commit" / "looks good"

Scope the re-audit to the changed files and their contract pairs — full re-audits aren't usually needed.
