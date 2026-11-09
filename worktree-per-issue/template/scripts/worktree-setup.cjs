#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const MODES = ['copy', 'hardlink', 'link'];
const KEYS = [...MODES, 'steps'];
const RESERVED = [['.git'], ['.claude', 'worktrees']];
const HARDLINK_UNSUPPORTED = ['EXDEV', 'EPERM', 'ENOTSUP', 'EOPNOTSUPP'];
const COPY_OPTIONS = {
  recursive: true,
  force: false,
  errorOnExist: true,
  preserveTimestamps: true,
  verbatimSymlinks: true,
  mode: fs.constants.COPYFILE_FICLONE,
};

const warn = (message) => console.error(`worktree: ${message}`);
const exitCode = (results) => (results.every(Boolean) ? 0 : 1);

class ExitError extends Error {
  constructor(code) {
    super(`exit ${code}`);
    this.code = code;
  }
}

const sameSegment = (a, b) => a.toLowerCase() === b.toLowerCase();
const isPrefix = (a, b) => a.length <= b.length && a.every((seg, i) => sameSegment(seg, b[i]));
const overlaps = (a, b) => isPrefix(a, b) || isPrefix(b, a);
const isPlainSegment = (seg) => seg !== '' && seg !== '.' && seg !== '..';

function pathProblem(entry, segs) {
  if (entry === '') return 'is empty';
  if (/^([/\\]|[A-Za-z]:)/.test(entry)) return 'must be relative to the repo root';
  if (entry.includes('\\')) return 'must use / as the separator';
  if (!segs.every(isPlainSegment)) return "must not contain empty, '.' or '..' segments";
  const reserved = RESERVED.find((r) => overlaps(r, segs));
  return reserved ? `overlaps ${reserved.join('/')}` : null;
}

function parseConfig(raw) {
  const errors = [];
  let config;
  try {
    config = JSON.parse(raw);
  } catch (e) {
    return { errors: [`not valid JSON: ${e.message}`], entries: [], steps: [] };
  }
  if (config === null || typeof config !== 'object' || Array.isArray(config)) {
    return { errors: [`must be a JSON object with the keys ${KEYS.join(', ')}`], entries: [], steps: [] };
  }
  for (const key of Object.keys(config)) {
    if (!KEYS.includes(key)) errors.push(`unknown key "${key}" (allowed: ${KEYS.join(', ')})`);
  }
  const lists = {};
  for (const key of KEYS) {
    const value = config[key] === undefined ? [] : config[key];
    if (!Array.isArray(value)) {
      errors.push(`"${key}" must be an array of strings`);
      lists[key] = [];
      continue;
    }
    lists[key] = value.filter((item, i) => {
      if (typeof item === 'string') return true;
      errors.push(`${key}[${i}] must be a string`);
      return false;
    });
  }

  const entries = [];
  for (const mode of MODES) {
    for (const entry of lists[mode]) {
      const segs = entry.split('/');
      const problem = pathProblem(entry, segs);
      if (problem) {
        errors.push(`${mode} "${entry}": ${problem}`);
        continue;
      }
      const clash = entries.find((p) => overlaps(p.segs, segs));
      if (clash) errors.push(`${mode} "${entry}": overlaps ${clash.mode} "${clash.entry}"`);
      else entries.push({ mode, entry, segs });
    }
  }

  lists.steps.forEach((step, i) => {
    if (step.trim() === '') errors.push(`steps[${i}]: is empty`);
  });

  return { errors, entries, steps: lists.steps };
}

function readConfig(file) {
  const absolute = path.resolve(file);
  let raw;
  try {
    raw = fs.readFileSync(absolute, 'utf8');
  } catch (e) {
    warn(`cannot read ${absolute}: ${e.message}`);
    return null;
  }
  const config = parseConfig(raw);
  if (config.errors.length === 0) return config;
  warn(`${absolute} has errors:`);
  for (const error of config.errors) console.error(`  ${error}`);
  return null;
}

function exists(p) {
  try {
    return fs.lstatSync(p, { throwIfNoEntry: false }) !== undefined;
  } catch (e) {
    if (e.code === 'ENOTDIR') return false;
    throw e;
  }
}
const removeTree = (p) => fs.rmSync(p, { recursive: true, force: true });

function copyEntry(src, dst) {
  try {
    fs.cpSync(src, dst, COPY_OPTIONS);
  } catch (e) {
    removeTree(dst);
    throw e;
  }
}

function hardlinkTree(src, dst) {
  const stat = fs.lstatSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dst);
    for (const name of fs.readdirSync(src)) hardlinkTree(path.join(src, name), path.join(dst, name));
  } else if (stat.isFile()) {
    fs.linkSync(src, dst);
  } else {
    fs.cpSync(src, dst, COPY_OPTIONS);
  }
}

function hardlinkEntry(src, dst) {
  try {
    hardlinkTree(src, dst);
  } catch (e) {
    removeTree(dst);
    if (!HARDLINK_UNSUPPORTED.includes(e.code)) throw e;
    warn(`hardlinks are not supported for ${dst} (${e.code}); copying instead.`);
    copyEntry(src, dst);
  }
}

function linkEntry(src, dst) {
  if (process.platform !== 'win32') return fs.symlinkSync(src, dst);
  // Windows: a symlink needs admin or developer mode, a junction does not but takes only directories.
  if (fs.statSync(src).isDirectory()) return fs.symlinkSync(src, dst, 'junction');
  warn(`links to files are not supported on Windows for ${dst}; copying instead.`);
  return copyEntry(src, dst);
}

const PLACE = { copy: copyEntry, hardlink: hardlinkEntry, link: linkEntry };

function place({ mode, entry }, repo, wt) {
  const src = path.join(repo, entry);
  const dst = path.join(wt, entry);
  if (exists(dst)) return true;
  if (!exists(src)) {
    warn(`${mode} ${entry}: ${src} is missing; skipped.`);
    return true;
  }
  try {
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    PLACE[mode](src, dst);
    return true;
  } catch (e) {
    warn(`${mode} ${entry}: could not create ${dst}: ${e.message}; skipped.`);
    return false;
  }
}

function runStep(step, wt) {
  const result = spawnSync('sh', ['-c', step], { cwd: wt, stdio: 'inherit' });
  if (result.status === 0) return true;
  warn(`'${step}' failed; run it manually in the worktree.`);
  return false;
}

const REPO = path.dirname(__dirname);
const CONFIG_FILE = path.join(REPO, '.claude', 'worktree.json');

function worktreeGitDir(wt) {
  const result = spawnSync('git', ['-C', wt, 'rev-parse', '--git-dir', '--git-common-dir'], { encoding: 'utf8' });
  if (result.status !== 0) return null;
  const [gitDir, commonDir] = result.stdout.trim().split('\n').map((dir) => fs.realpathSync(path.resolve(wt, dir)));
  const isLinkedWorktree = gitDir !== commonDir && commonDir === fs.realpathSync(path.join(REPO, '.git'));
  return isLinkedWorktree ? gitDir : null;
}

function loadWorktree(wt, fixHint) {
  const gitDir = worktreeGitDir(wt);
  if (!gitDir) {
    warn(`${wt} is not a worktree of ${REPO}.`);
    throw new ExitError(2);
  }
  if (!fs.statSync(CONFIG_FILE, { throwIfNoEntry: false })?.isFile()) return { gitDir, config: null };
  const config = readConfig(CONFIG_FILE);
  if (config) return { gitDir, config };
  console.error(fixHint);
  throw new ExitError(1);
}

function setup(wt, force) {
  const { gitDir, config } = loadWorktree(wt, 'Fix that file, then run /worktree-heal to finish the worktree setup.');
  if (!config) {
    warn(`no .claude/worktree.json in ${REPO}, nothing to set up. Add one (see docs/worktrees.md), then run /worktree-heal.`);
    return 0;
  }

  const results = config.entries.map((entry) => place(entry, REPO, wt));

  const marker = path.join(gitDir, 'wt-provisioned');
  if (force || !exists(marker)) {
    results.push(...config.steps.map((step) => runStep(step, wt)));
    try {
      fs.writeFileSync(marker, '');
    } catch {
      warn(`could not write ${marker}; the steps will run again next time.`);
    }
  }
  return exitCode(results);
}

const links = (config) => (config ? config.entries.filter(({ mode }) => mode === 'link') : []);

function unlinkEntry({ entry }, wt) {
  const dst = path.join(wt, entry);
  if (!fs.lstatSync(dst, { throwIfNoEntry: false })?.isSymbolicLink()) return true;
  try {
    fs.unlinkSync(dst);
    return true;
  } catch (e) {
    warn(`link ${entry}: could not remove ${dst}: ${e.message}`);
    return false;
  }
}

function unlinkLinks(wt) {
  const { config } = loadWorktree(wt, 'Fix that file, then retry: its links must be dropped before the worktree is removed.');
  return exitCode(links(config).map((entry) => unlinkEntry(entry, wt)));
}

function relinkLinks(wt) {
  const { config } = loadWorktree(wt, "Fix that file, then run /worktree-heal to restore the worktree's links.");
  return exitCode(links(config).map((entry) => place(entry, REPO, wt)));
}

function init(file, pairs) {
  const config = Object.fromEntries(KEYS.map((key) => [key, []]));
  for (let i = 0; i < pairs.length; i += 2) config[pairs[i]].push(pairs[i + 1]);
  fs.writeFileSync(file, `${JSON.stringify(config, null, 2)}\n`, { flag: 'wx' });
  return 0;
}

const isPairList = (rest) => rest.length % 2 === 0 && rest.every((arg, i) => i % 2 === 1 || KEYS.includes(arg));

const USAGE = 'usage: worktree-setup.cjs setup <worktree> [--force] | unlink <worktree> | relink <worktree> | check <worktree.json> | init <worktree.json> [<key> <entry>]...';

function main(args) {
  const [command, file, ...rest] = args;
  if (command === 'setup' && file && rest.length === 0) return setup(path.resolve(file), false);
  if (command === 'setup' && file && rest.length === 1 && rest[0] === '--force') return setup(path.resolve(file), true);
  if (command === 'unlink' && args.length === 2) return unlinkLinks(path.resolve(file));
  if (command === 'relink' && args.length === 2) return relinkLinks(path.resolve(file));
  if (command === 'check' && args.length === 2) return readConfig(file) ? 0 : 1;
  if (command === 'init' && file && isPairList(rest)) return init(file, rest);
  console.error(USAGE);
  return 2;
}

try {
  process.exitCode = main(process.argv.slice(2));
} catch (e) {
  if (!(e instanceof ExitError)) throw e;
  process.exitCode = e.code;
}
