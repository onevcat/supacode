const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

function getInput(name) {
  const envName = `INPUT_${name.replace(/ /g, '_').toUpperCase()}`;
  return process.env[envName] || '';
}

function splitLines(value) {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);
}

function expandPath(p) {
  if (p.startsWith('~')) {
    return path.join(os.homedir(), p.slice(1));
  }
  if (path.isAbsolute(p)) {
    return p;
  }
  const workspace = process.env.GITHUB_WORKSPACE || process.cwd();
  return path.resolve(workspace, p);
}

function encodePath(p) {
  return Buffer.from(p)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function rsyncDir(src, dest) {
  execFileSync('rsync', ['-a', `${src}/`, `${dest}/`], { stdio: 'inherit' });
}

function rsyncFile(src, dest) {
  execFileSync('rsync', ['-a', src, dest], { stdio: 'inherit' });
}

const cacheBase = getInput('cache-base') || '/Volumes/My Shared Files/gha-cache';
const key = getInput('key');
const paths = splitLines(getInput('path'));

if (!key || paths.length === 0) {
  process.exit(0);
}

try {
  fs.mkdirSync(cacheBase, { recursive: true });
} catch {
  console.log('cache base unavailable');
  process.exit(0);
}

const cacheRoot = path.join(cacheBase, key);
if (fs.existsSync(cacheRoot)) {
  console.log('cache already exists');
  process.exit(0);
}

const tmpRoot = path.join(cacheBase, `${key}.tmp-${process.pid}-${Date.now()}`);
const tmpPathsRoot = path.join(tmpRoot, 'paths');
fs.mkdirSync(tmpPathsRoot, { recursive: true });

let saved = false;

for (const p of paths) {
  const src = expandPath(p);
  if (!fs.existsSync(src)) {
    continue;
  }
  const encoded = encodePath(p);
  const dest = path.join(tmpPathsRoot, encoded);
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    rsyncDir(src, dest);
  } else {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    rsyncFile(src, dest);
  }
  saved = true;
}

if (!saved) {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
  process.exit(0);
}

try {
  fs.renameSync(tmpRoot, cacheRoot);
  console.log(`cache saved: ${cacheRoot}`);
} catch {
  fs.rmSync(tmpRoot, { recursive: true, force: true });
}
