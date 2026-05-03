const { app } = require('electron');
const fs = require('fs');
const http = require('http');
const path = require('path');

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  return dir;
}

function directoryHasLaunchScript(dir) {
  try {
    return !!dir && fs.existsSync(path.join(dir, 'scripts', 'launch.ps1'));
  } catch {
    return false;
  }
}

function getAppRoot() {
  const candidates = [];
  if (process.env.NOTION2COUNCIL_ROOT) candidates.push(process.env.NOTION2COUNCIL_ROOT);

  if (app.isPackaged) {
    candidates.push(path.join(process.resourcesPath, 'app.asar.unpacked'));
    candidates.push(path.join(process.resourcesPath, 'app'));
  }

  try { candidates.push(app.getAppPath()); } catch {}
  candidates.push(path.resolve(__dirname, '..', '..')); // Adjusted for nested lib folder
  candidates.push(process.cwd());

  const validRoot = candidates.find(candidate => directoryHasLaunchScript(candidate));
  if (validRoot) return validRoot;

  throw new Error('Could not find application root directory (scripts/launch.ps1 missing in candidates)');
}

function waitForUrl(url, timeoutMs = 90000, options = {}) {
  const started = Date.now();
  let finished = false;

  return new Promise((resolve, reject) => {
    const cleanup = () => { finished = true; };

    const retry = () => {
      if (finished) return;
      if (Date.now() - started > timeoutMs) {
        cleanup();
        return reject(new Error(`Timed out waiting for ${url}`));
      }
      setTimeout(tick, 750);
    };

    const tick = () => {
      if (finished) return;
      const request = http.get(url, response => {
        if (finished) return;
        response.resume();
        if (response.statusCode >= 200 && response.statusCode < 500) {
          cleanup();
          return resolve(true);
        }
        retry();
      });

      request.on('error', (err) => {
        if (finished) return;
        retry();
      });
      request.setTimeout(2500, () => {
        request.destroy();
        retry();
      });
    };

    if (options.signal) {
      options.signal.addEventListener('abort', () => {
        cleanup();
        reject(new Error('Operation aborted'));
      });
    }

    tick();
  });
}

module.exports = {
  ensureDir,
  getAppRoot,
  waitForUrl
};
