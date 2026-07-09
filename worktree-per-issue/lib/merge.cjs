#!/usr/bin/env node
/**
 * Additive JSON merge helper for the worktree-toolbox installer. Never clobbers existing values:
 * it only adds keys/array entries that are absent. Each mode reads a JSON file (or treats a
 * missing file as {}), applies its additions, and writes it back with 2-space indentation.
 *
 * Usage:
 *   node merge.cjs settings <path>              # .claude/settings.json
 *   node merge.cjs vscode   <path> <scanDepth>  # .vscode/settings.json
 *
 * Exit codes: 0 = merged (prints notes to stdout). 2 = file exists but is not parseable JSON
 * (prints a warning + the snippet to add by hand; the installer treats this as non-fatal).
 */
const fs = require('node:fs');
const path = require('node:path');

const [, , mode, filePath, arg] = process.argv;

if (!mode || !filePath) {
  console.error('usage: merge.cjs <settings|vscode> <path> [arg]');
  process.exit(1);
}

function readJson(p) {
  if (!fs.existsSync(p)) return { obj: {}, existed: false };
  const raw = fs.readFileSync(p, 'utf8');
  try {
    return { obj: raw.trim() === '' ? {} : JSON.parse(raw), existed: true };
  } catch {
    return { obj: null, existed: true, raw };
  }
}

function writeJson(p, obj) {
  fs.mkdirSync(path.dirname(p), { recursive: true }); // e.g. .vscode/ may not exist yet
  fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n');
}

function pushUnique(arr, value) {
  const key = JSON.stringify(value);
  if (arr.some((e) => JSON.stringify(e) === key)) return false;
  arr.push(value);
  return true;
}

const notes = [];
const { obj } = readJson(filePath);

function bailUnparseable(snippet) {
  console.log(`WARN: ${filePath} exists but is not valid JSON — leaving it untouched.`);
  console.log('Add the following by hand:');
  console.log(snippet);
  process.exit(2);
}

if (mode === 'settings') {
  // Bash(git -C:*) covers /worktree-remove running `git -C "<main>" worktree remove …` from inside a worktree.
  const allow = ['Bash(git worktree *)', 'Bash(git -C:*)'];
  if (obj === null) {
    bailUnparseable(allow.map((p) => `  permissions.allow += "${p}"`).join('\n'));
  }
  // permissions.allow
  obj.permissions = obj.permissions || {};
  obj.permissions.allow = obj.permissions.allow || [];
  for (const p of allow) {
    if (pushUnique(obj.permissions.allow, p)) {
      notes.push(`added permissions.allow "${p}"`);
    } else {
      notes.push(`permissions.allow already had "${p}"`);
    }
  }
  writeJson(filePath, obj);
} else if (mode === 'vscode') {
  const scanDepth = Number(arg || '4');
  if (obj === null) {
    bailUnparseable(`  "git.detectWorktrees": true,\n  "git.repositoryScanMaxDepth": ${scanDepth}`);
  }
  if (obj['git.detectWorktrees'] === undefined) {
    obj['git.detectWorktrees'] = true;
    notes.push('set git.detectWorktrees = true');
  } else {
    notes.push('git.detectWorktrees already set');
  }
  if (obj['git.repositoryScanMaxDepth'] === undefined) {
    obj['git.repositoryScanMaxDepth'] = scanDepth;
    notes.push(`set git.repositoryScanMaxDepth = ${scanDepth}`);
  } else {
    notes.push('git.repositoryScanMaxDepth already set');
  }
  writeJson(filePath, obj);
} else {
  console.error(`unknown mode: ${mode}`);
  process.exit(1);
}

for (const n of notes) console.log(n);
