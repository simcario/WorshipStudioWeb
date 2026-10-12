// Run after `flutter build web`: node tool/postbuild.js
//
// Writes the list of built files into build/web/sw.js so the service worker
// can precache the whole app on first visit (it then works offline straight
// away), and stamps the cache name with a hash of the build so a new deploy
// replaces the old cache. Then copies the build into server/public.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const root = path.join(__dirname, '..', 'build', 'web');

// Not needed at runtime, or only by engines this build does not use.
const skip = [
  /^sw\.js$/, /^flutter_service_worker\.js$/, /^version\.json$/, /^\.last_build_id$/,
  /\.symbols$/, /\.map$/, /NOTICES$/, /^canvaskit\/(skwasm|wimp)/, /^canvaskit\/experimental_webparagraph\//,
  /^canvaskit\/webparagraph\//,
];

function walk(dir, out = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else out.push(path.relative(root, full).split(path.sep).join('/'));
  }
  return out;
}

const files = walk(root).filter((f) => !skip.some((re) => re.test(f))).sort();
const hash = crypto.createHash('sha256');
for (const f of files) hash.update(f).update(fs.readFileSync(path.join(root, f)));
const version = hash.digest('hex').slice(0, 12);

const swPath = path.join(root, 'sw.js');
let sw = fs.readFileSync(swPath, 'utf8');
const before = sw;
sw = sw.replace(/const CACHE = '[^']*';/, `const CACHE = 'worship-studio-${version}';`);
sw = sw.replace(/const SHELL = \[[^\]]*\];/, `const SHELL = ${JSON.stringify(['./', ...files])};`);
if (sw === before) throw new Error('sw.js: CACHE / SHELL declarations not found');
fs.writeFileSync(swPath, sw);

const bytes = files.reduce((n, f) => n + fs.statSync(path.join(root, f)).size, 0);
console.log(`sw.js: ${files.length} files precached (${(bytes / 1048576).toFixed(1)} MB), cache worship-studio-${version}`);

// The backend deployed on Firebase App Hosting serves the app from server/public.
const publicDir = path.join(__dirname, '..', 'server', 'public');
fs.rmSync(publicDir, { recursive: true, force: true });
fs.cpSync(root, publicDir, { recursive: true });
console.log(`server/public: copy of build/web`);
