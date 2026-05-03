const { app } = require('electron');
const fs = require('fs');
const path = require('path');

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function getLogsDir() {
  // Use app.getPath('userData') only after app is ready, 
  // or use a safe fallback if called prematurely.
  try {
    return ensureDir(path.join(app.getPath('userData'), 'logs'));
  } catch {
    return path.join(process.cwd(), 'logs');
  }
}

function appendLog(message) {
  try {
    const logFile = path.join(getLogsDir(), 'desktop-launcher.log');
    fs.appendFileSync(logFile, `[${new Date().toISOString()}] ${message}\n`, 'utf8');
    console.log(`[LOG] ${message}`);
  } catch (err) {
    // Logging must not crash the app
    console.error(`Failed to write to log: ${err.message}`);
  }
}

module.exports = {
  getLogsDir,
  appendLog
};
