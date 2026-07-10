#!/usr/bin/env node
/**
 * Generate a VS Code keybinding that opens `claude` as an editor-area terminal tab for the primary
 * checkout and every linked git worktree — one tab each. Regenerated from `git worktree list`, so
 * run it whenever worktrees change. Idempotent and self-migrating (replaces only the binding it
 * manages, detected by signature). Config via env: CLAUDE_WT_KEY, CLAUDE_WT_COMMAND,
 * VSCODE_KEYBINDINGS_PATH. See README.md for the rationale (why a keybinding, WSL, caveats).
 */
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const KEY = process.env.CLAUDE_WT_KEY || 'ctrl+alt+w';
const CLAUDE_CMD = process.env.CLAUDE_WT_COMMAND || 'claude';
const HEADER = '// Place your key bindings in this file to override the defaults';

function sh(cmd, args) {
  // Ignore stderr: cmd.exe emits a harmless "UNC paths are not supported" warning when launched
  // from a WSL cwd, which would otherwise clutter output.
  return execFileSync(cmd, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
}

function isWSL() {
  if (process.env.WSL_DISTRO_NAME) return true;
  try {
    return fs.readFileSync('/proc/version', 'utf8').toLowerCase().includes('microsoft');
  } catch {
    return false;
  }
}

// --- keybindings path ---------------------------------------------------------------------
function resolveKeybindingsPath() {
  if (process.env.VSCODE_KEYBINDINGS_PATH) return process.env.VSCODE_KEYBINDINGS_PATH;
  if (isWSL()) {
    const winUser = sh('cmd.exe', ['/c', 'echo %USERNAME%']).replaceAll('\r', '');
    if (!winUser || winUser.includes('%')) {
      throw new Error('Could not resolve the Windows username via cmd.exe. Set VSCODE_KEYBINDINGS_PATH.');
    }
    return `/mnt/c/Users/${winUser}/AppData/Roaming/Code/User/keybindings.json`;
  }
  switch (process.platform) {
    case 'darwin':
      return path.join(os.homedir(), 'Library', 'Application Support', 'Code', 'User', 'keybindings.json');
    case 'win32':
      return path.join(
        process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming'),
        'Code', 'User', 'keybindings.json',
      );
    default:
      return path.join(os.homedir(), '.config', 'Code', 'User', 'keybindings.json');
  }
}

// --- enumerate worktrees ------------------------------------------------------------------
// Skip `prunable`/missing worktrees — a dead path makes `cd` fail so `claude` never runs.
function listWorktrees() {
  const out = sh('git', ['worktree', 'list', '--porcelain']);
  const worktrees = [];
  // --porcelain emits one blank-line-separated record per worktree; primary checkout first.
  for (const record of out.split('\n\n')) {
    const lines = record.split('\n');
    const wtLine = lines.find((l) => l.startsWith('worktree '));
    if (!wtLine) continue;
    const wt = wtLine.slice('worktree '.length).trim();
    if (!wt) continue;
    if (lines.some((l) => l === 'prunable' || l.startsWith('prunable '))) continue;
    if (!fs.existsSync(wt)) continue; // belt-and-suspenders: dir removed before git marks it prunable
    worktrees.push(wt);
  }
  return worktrees;
}

// --- build binding ------------------------------------------------------------------------
function buildBinding(worktrees) {
  const commands = [];
  for (const wt of worktrees) {
    commands.push('workbench.action.createTerminalEditor', {
      command: 'workbench.action.terminal.sendSequence',
      // \r (0x0D) submits the line. Double-quote the path to tolerate special chars.
      args: { text: `cd "${wt}" && ${CLAUDE_CMD}\r` },
    });
  }
  return { key: KEY, command: 'runCommands', args: { commands } };
}

// --- recognise managed --------------------------------------------------------------------
function isManaged(b) {
  if (!b || b.command !== 'runCommands') return false;
  const cmds = Array.isArray(b.args?.commands) ? b.args.commands : [];
  return cmds.includes('workbench.action.createTerminalEditor');
}

// --- parse jsonc --------------------------------------------------------------------------
function parseBindings(text) {
  if (!text.trim()) return [];
  const stripped = text
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/[^\n]*/g, '$1'); // keep `://` (e.g. urls) intact
  const parsed = JSON.parse(stripped);
  if (!Array.isArray(parsed)) throw new Error('keybindings.json is not a JSON array.');
  return parsed;
}

function main() {
  const kbPath = resolveKeybindingsPath();
  const worktrees = listWorktrees();
  if (worktrees.length === 0) {
    console.error('No worktrees found (run inside a git repo). Aborting.');
    process.exit(1);
  }

  let existing = [];
  if (fs.existsSync(kbPath)) {
    try {
      existing = parseBindings(fs.readFileSync(kbPath, 'utf8'));
    } catch (err) {
      console.error(`Could not parse ${kbPath}: ${err.message}`);
      console.error('Refusing to overwrite. Fix or remove the file, then re-run.');
      process.exit(1);
    }
  } else {
    fs.mkdirSync(path.dirname(kbPath), { recursive: true });
  }

  // Drop our managed entry (old key included), keep everything else, append the fresh one.
  const kept = existing.filter((b) => b && b.key !== KEY && !isManaged(b));
  kept.push(buildBinding(worktrees));

  const output = `${HEADER}\n${JSON.stringify(kept, null, '\t')}\n`;
  fs.writeFileSync(kbPath, output, 'utf8');

  console.log(`✔ Wrote ${KEY} binding for ${worktrees.length} worktree(s) to:`);
  console.log(`  ${kbPath}`);
  worktrees.forEach((wt) => console.log(`    • ${wt}`));
  console.log(`Reload VS Code, then press ${KEY} to open a ${CLAUDE_CMD} editor tab per worktree.`);
}

main();
