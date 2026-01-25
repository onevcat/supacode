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

function setOutput(name, value) {
  const outputPath = process.env.GITHUB_OUTPUT;
  if (!outputPath) {
    return;
  }
  fs.appendFileSync(outputPath, `${name}=${value}\n`);
}

function listCacheKeys(base, prefix) {
  if (!fs.existsSync(base)) {
    return [];
  }
  return fs
    .readdirSync(base, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.startsWith(prefix))
    .map((entry) => entry.name);
}

function newestKey(base, prefix) {
  const keys = listCacheKeys(base, prefix);
  let best = null;
  let bestTime = -1;
  for (const key of keys) {
    const stat = fs.statSync(path.join(base, key));
    if (stat.mtimeMs > bestTime) {
      bestTime = stat.mtimeMs;
      best = key;
    }
  }
  return best;
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
const restoreKeys = splitLines(getInput('restore-keys'));

if (!key) {
  console.error('cache key is required');
  process.exit(1);
}

if (paths.length === 0) {
  console.error('cache path is required');
  process.exit(1);
}

if (!fs.existsSync(cacheBase)) {
  setOutput('cache-hit', 'false');
  process.exit(0);
}

let matchedKey = null;
let cacheHit = false;
const exactPath = path.join(cacheBase, key);

if (fs.existsSync(exactPath)) {
  matchedKey = key;
  cacheHit = true;
} else {
  for (const prefix of restoreKeys) {
    const match = newestKey(cacheBase, prefix);
    if (match) {
      matchedKey = match;
      break;
    }
  }
}

if (!matchedKey) {
  console.log('cache miss');
  setOutput('cache-hit', 'false');
  process.exit(0);
}

const cacheRoot = path.join(cacheBase, matchedKey, 'paths');

for (const p of paths) {
  const encoded = encodePath(p);
  const src = path.join(cacheRoot, encoded);
  if (!fs.existsSync(src)) {
    continue;
  }
  const dest = expandPath(p);
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    fs.mkdirSync(dest, { recursive: true });
    rsyncDir(src, dest);
  } else {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    rsyncFile(src, dest);
  }
}

console.log(`cache restore: ${matchedKey}`);
setOutput('cache-hit', cacheHit ? 'true' : 'false');
