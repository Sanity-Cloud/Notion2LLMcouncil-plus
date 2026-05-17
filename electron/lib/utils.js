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

function isInsideAsar(value) {
  return !!value && /(^|[\\/])app\.asar([\\/]|$)/i.test(value);
}

function toUnpackedAsarPath(value) {
  if (!value) return value;
  return value.replace(/([\\/])app\.asar([\\/]|$)/i, '$1app.asar.unpacked$2');
}

function directoryHasLaunchScript(dir) {
  try {
    return !!dir && !isInsideAsar(dir) && fs.existsSync(path.join(dir, 'scripts', 'launch.ps1'));
  } catch {
    return false;
  }
}

function getUserDataRoot() {
  try {
    return ensureDir(app.getPath('userData'));
  } catch {
    return ensureDir(path.join(process.cwd(), '.notion2council-userdata'));
  }
}

function getRuntimeRoot() {
  return ensureDir(path.join(getUserDataRoot(), 'runtime'));
}

function getAppRoot() {
  const candidates = [];
  if (process.env.NOTION2COUNCIL_ROOT) candidates.push(process.env.NOTION2COUNCIL_ROOT);

  if (app.isPackaged) {
    candidates.push(path.join(process.resourcesPath, 'app.asar.unpacked'));
    candidates.push(path.join(process.resourcesPath, 'app'));
  }

  try {
    const appPath = app.getAppPath();
    candidates.push(toUnpackedAsarPath(appPath));
    candidates.push(appPath);
  } catch {}

  candidates.push(path.resolve(__dirname, '..', '..')); // Adjusted for nested lib folder
  candidates.push(process.cwd());

  const validRoot = candidates.find(candidate => directoryHasLaunchScript(candidate));
  if (validRoot) return validRoot;

  if (app.isPackaged) {
    return getRuntimeRoot();
  }

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
        let body = '';
        response.setEncoding('utf8');
        response.on('data', chunk => {
          if (body.length < 12000) body += chunk;
        });
        response.on('end', () => {
          if (finished) return;
          const statusOk = response.statusCode >= 200 && response.statusCode < 500;
          const contentOk = options.expectedContent ? body.includes(options.expectedContent) : true;
          const titleMatch = /<title>(.*?)<\/title>/is.exec(body);
          const titleOk = options.expectedTitle ? !!(titleMatch && titleMatch[1].includes(options.expectedTitle)) : true;
          if (statusOk && contentOk && titleOk) {
            cleanup();
            return resolve(true);
          }
          retry();
        });
      });

      request.on('error', () => {
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
  getRuntimeRoot,
  getUserDataRoot,
  isInsideAsar,
  toUnpackedAsarPath,
  waitForUrl
};
