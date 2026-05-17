const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const { appendLog, getLogsDir } = require('./logger');
const { getAppRoot } = require('./utils');
const { getIntegrationConfig } = require('./integration-config');
const { dialog } = require('electron');

let launcherProcess = null;
let loginProcess = null;

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

function readEnvValue(filePath, name) {
  try {
    if (!fs.existsSync(filePath)) return '';
    const prefix = `${name}=`;
    const line = fs.readFileSync(filePath, 'utf8')
      .split(/\r?\n/)
      .find(item => item.trimStart().startsWith(prefix));
    if (!line) return '';
    return line.trim().slice(prefix.length).replace(/^["']|["']$/g, '');
  } catch {
    return '';
  }
}

function hasSavedNotionAccount(integration) {
  if (process.env.NOTION_ACCOUNTS) return true;

  const accountsPath = path.join(integration.notionRoot, 'accounts.json');
  try {
    if (fs.existsSync(accountsPath)) {
      const parsed = JSON.parse(fs.readFileSync(accountsPath, 'utf8'));
      if (Array.isArray(parsed) && parsed.length > 0) return true;
    }
  } catch (error) {
    appendLog(`accounts.json is present but invalid: ${error.message}`);
  }

  const envAccounts = readEnvValue(path.join(integration.notionRoot, '.env'), 'NOTION_ACCOUNTS');
  return !!envAccounts;
}

function runPowerShell(scriptPath, args = []) {
  if (!fs.existsSync(scriptPath)) {
    showError(
      'Launcher script not found',
      `Could not find ${scriptPath}\n\nSet NOTION2COUNCIL_ROOT to the folder containing scripts\\launch.ps1.`
    );
    return null;
  }

  const integration = getIntegrationConfig();
  const powerShellPath = resolvePowerShellPath();
  const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args];
  const cwd = getAppRoot();
  const env = {
    ...process.env,
    NOTION2COUNCIL_CONFIG: integration.configPath,
    NOTION2COUNCIL_LOG_DIR: getLogsDir(),
    NOTION2COUNCIL_RUNTIME_ROOT: path.dirname(path.dirname(integration.notionRoot)),
  };
  
  appendLog(`Starting PowerShell: ${powerShellPath} ${psArgs.join(' ')} (cwd: ${cwd})`);

  let child;
  try {
    child = spawn(powerShellPath, psArgs, {
      cwd,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: false,
      env,
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

function runVisibleNotionLogin(integration, afterLogin) {
  const loginScript = path.join(integration.notionRoot, 'login.py');
  if (!fs.existsSync(loginScript)) {
    appendLog(`Notion login helper not found yet: ${loginScript}`);
    return false;
  }

  if (loginProcess && !loginProcess.killed) {
    appendLog('Notion login helper is already running.');
    return true;
  }

  const powerShellPath = resolvePowerShellPath();
  const command = [
    '$ErrorActionPreference = "Stop"',
    `Set-Location -LiteralPath ${JSON.stringify(integration.notionRoot)}`,
    'Write-Host "Notion2Council needs a Notion account profile before the local API can start."',
    'Write-Host "A browser window will open. Sign in to Notion, then return here if prompted."',
    '& python .\\login.py --timeout 300',
    'if ($LASTEXITCODE -ne 0) { Write-Host ""; Write-Host "Notion login failed. Press Enter to close."; Read-Host; exit $LASTEXITCODE }',
    'Write-Host ""',
    'Write-Host "Notion login complete. Starting Notion2Council..."',
    'Start-Sleep -Seconds 2',
  ].join('; ');

  appendLog(`Launching visible Notion login helper: ${loginScript}`);
  try {
    loginProcess = spawn(powerShellPath, ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], {
      cwd: integration.notionRoot,
      windowsHide: false,
      detached: false,
      stdio: 'ignore',
      env: {
        ...process.env,
        NOTION2COUNCIL_CONFIG: integration.configPath,
        NOTION2COUNCIL_LOG_DIR: getLogsDir(),
      },
    });
  } catch (error) {
    showError('Failed to start Notion login', `${error.message}\nTried: ${powerShellPath}`);
    return true;
  }

  loginProcess.on('exit', code => {
    appendLog(`Notion login helper exited with code ${code}`);
    loginProcess = null;
    if (code === 0 && typeof afterLogin === 'function') {
      afterLogin();
    } else if (code !== 0) {
      showError('Notion login failed', 'The Notion account profile was not created. Start Stack again to retry login.');
    }
  });

  loginProcess.on('error', error => {
    appendLog(`Notion login helper process error: ${error.message}`);
    loginProcess = null;
    showError('Notion login failed', error.message);
  });

  return true;
}

function getScriptPath(scriptName) {
  return path.join(getAppRoot(), 'scripts', scriptName);
}

function getBaseLaunchArgs() {
  const integration = getIntegrationConfig();
  return [
    '-ConfigPath', integration.configPath,
    '-NotionRoot', integration.notionRoot,
    '-CouncilRoot', integration.councilRoot,
    '-NotionPort', `${integration.notionPort}`,
    '-CouncilBackendPort', `${integration.councilBackendPort}`,
    '-CouncilFrontendPort', `${integration.councilFrontendPort}`,
  ];
}

function startStack({ noBrowser = true } = {}) {
  if (launcherProcess && !launcherProcess.killed) return launcherProcess;

  const integration = getIntegrationConfig();
  if (!hasSavedNotionAccount(integration)) {
    const handled = runVisibleNotionLogin(integration, () => startStack({ noBrowser }));
    if (handled) return loginProcess;
  }

  const args = getBaseLaunchArgs();
  if (noBrowser) args.push('-NoBrowser');
  launcherProcess = runPowerShell(getScriptPath('launch.ps1'), args);
  return launcherProcess;
}

function stopStack() {
  appendLog('[launcher] stopStack: dispatching launch.ps1 -Stop');
  const args = getBaseLaunchArgs();
  args.push('-Stop');
  return runPowerShell(getScriptPath('launch.ps1'), args);
}

module.exports = {
  startStack,
  stopStack
};
