const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const { appendLog } = require('./logger');
const { getAppRoot } = require('./utils');
const { dialog } = require('electron');

let launcherProcess = null;

function resolvePowerShellPath() {
  const windir = process.env.SystemRoot || process.env.WINDIR || 'C:\\Windows';
  const candidates = [
    process.env.NOTION2COUNCIL_POWERSHELL,
    path.join(windir, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
    path.join(windir, 'Sysnative', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
    'powershell.exe',
    'pwsh.exe',
  ].filter(Boolean);

  for (const candidate of candidates) {
    try {
      if (path.isAbsolute(candidate) && fs.existsSync(candidate)) return candidate;
    } catch {}
  }

  return 'powershell.exe';
}

function showError(title, message) {
  appendLog(`${title}: ${message || 'Unknown error'}`);
  try {
    dialog.showErrorBox(title, message || 'Unknown error');
  } catch {}
}

function runPowerShell(scriptPath, args = []) {
  if (!fs.existsSync(scriptPath)) {
    showError(
      'Launcher script not found',
      `Could not find ${scriptPath}\n\nSet NOTION2COUNCIL_ROOT to the folder containing scripts\\launch.ps1.`
    );
    return null;
  }

  const powerShellPath = resolvePowerShellPath();
  const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args];
  const cwd = getAppRoot();
  
  appendLog(`Starting PowerShell: ${powerShellPath} ${psArgs.join(' ')} (cwd: ${cwd})`);

  let child;
  try {
    child = spawn(powerShellPath, psArgs, {
      cwd,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: false,
      env: { ...process.env },
    });
  } catch (error) {
    showError('Failed to start PowerShell', `${error.message}\nTried: ${powerShellPath}`);
    return null;
  }

  child.stdout?.on('data', chunk => appendLog(chunk.toString().trimEnd()));
  child.stderr?.on('data', chunk => appendLog(`PS ERROR: ${chunk.toString().trimEnd()}`));
  
  child.on('error', error => {
    appendLog(`PowerShell Process Error: ${error.message}`);
    if (launcherProcess === child) launcherProcess = null;
  });

  child.on('exit', code => {
    appendLog(`PowerShell exited with code ${code}`);
    if (launcherProcess === child) launcherProcess = null;
  });

  return child;
}

function getScriptPath(scriptName) {
  return path.join(getAppRoot(), 'scripts', scriptName);
}

function startStack({ noBrowser = true } = {}) {
  if (launcherProcess && !launcherProcess.killed) return launcherProcess;
  const args = [];
  if (process.env.NOTION2COUNCIL_CONFIG) args.push('-ConfigPath', process.env.NOTION2COUNCIL_CONFIG);
  if (noBrowser) args.push('-NoBrowser');
  launcherProcess = runPowerShell(getScriptPath('launch.ps1'), args);
  return launcherProcess;
}

function stopStack() {
  appendLog('[launcher] stopStack: dispatching launch.ps1 -Stop');
  const args = [];
  if (process.env.NOTION2COUNCIL_CONFIG) args.push('-ConfigPath', process.env.NOTION2COUNCIL_CONFIG);
  args.push('-Stop');
  return runPowerShell(getScriptPath('launch.ps1'), args);
}

module.exports = {
  startStack,
  stopStack
};
