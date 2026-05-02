const { app, BrowserWindow, Menu, Tray, nativeImage, globalShortcut, clipboard, ipcMain, shell, dialog } = require('electron');
const { spawn } = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');

let mainWindow = null;
let hotkeyWindow = null;
let tray = null;
let launcherProcess = null;

const councilUiUrl = process.env.NOTION2COUNCIL_UI_URL || 'http://127.0.0.1:5173/';
const notionApiUrl = process.env.NOTION2API_URL || 'http://127.0.0.1:8000/';
const notionDocsUrl = process.env.NOTION2API_DOCS_URL || 'http://127.0.0.1:8000/docs';

const defaultHotkeys = {
  toggleWindow: 'Alt+Space',
  openChat: 'CommandOrControl+Shift+L',
  clipboardToChat: 'CommandOrControl+Shift+V',
  openHotkeySettings: 'CommandOrControl+Shift+H',
};

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function getLogsDir() {
  return ensureDir(path.join(app.getPath('userData'), 'logs'));
}

function appendLog(message) {
  try {
    fs.appendFileSync(path.join(getLogsDir(), 'desktop-launcher.log'), `[${new Date().toISOString()}] ${message}\n`, 'utf8');
  } catch {
    // Logging must not crash the shell.
  }
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
  candidates.push(path.resolve(__dirname, '..'));
  candidates.push(process.cwd());

  for (const candidate of candidates) {
    if (directoryHasLaunchScript(candidate)) return candidate;
  }

  return candidates.find(Boolean) || process.cwd();
}

function getScriptPath(scriptName) {
  return path.join(getAppRoot(), 'scripts', scriptName);
}

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

function getHotkeyConfigPath() {
  return path.join(app.getPath('userData'), 'hotkeys.json');
}

function readHotkeys() {
  try {
    const file = getHotkeyConfigPath();
    if (!fs.existsSync(file)) return { ...defaultHotkeys };
    return { ...defaultHotkeys, ...JSON.parse(fs.readFileSync(file, 'utf8')) };
  } catch {
    return { ...defaultHotkeys };
  }
}

function writeHotkeys(hotkeys) {
  const file = getHotkeyConfigPath();
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, JSON.stringify({ ...defaultHotkeys, ...hotkeys }, null, 2), 'utf8');
}

function waitForUrl(url, timeoutMs = 90000) {
  const started = Date.now();
  return new Promise((resolve, reject) => {
    const retry = () => {
      if (Date.now() - started > timeoutMs) return reject(new Error(`Timed out waiting for ${url}`));
      setTimeout(tick, 750);
    };
    const tick = () => {
      const request = http.get(url, response => {
        response.resume();
        if (response.statusCode >= 200 && response.statusCode < 500) return resolve(true);
        retry();
      });
      request.on('error', retry);
      request.setTimeout(2500, () => {
        request.destroy();
        retry();
      });
    };
    tick();
  });
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
      `Could not find ${scriptPath}\n\nSet NOTION2COUNCIL_ROOT to the folder containing scripts\\launch.ps1, or install from the source/runtime bundle.`
    );
    return null;
  }

  const powerShellPath = resolvePowerShellPath();
  const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args];
  const cwd = getAppRoot();
  const env = { ...process.env, NOTION2COUNCIL_LOG_DIR: getLogsDir() };

  appendLog(`Starting: ${powerShellPath} ${psArgs.join(' ')}`);
  appendLog(`cwd=${cwd}`);

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
  child.stderr?.on('data', chunk => appendLog(`ERROR: ${chunk.toString().trimEnd()}`));
  child.on('error', error => {
    const detail = `${error.message}\nTried: ${powerShellPath}`;
    if (error.code === 'ENOENT') showError('PowerShell not found', detail);
    else showError('PowerShell process error', detail);
    if (launcherProcess === child) launcherProcess = null;
  });
  child.on('exit', code => {
    appendLog(`PowerShell exited with code ${code}`);
    if (launcherProcess === child) launcherProcess = null;
  });

  return child;
}

function startStack({ noBrowser = true } = {}) {
  if (launcherProcess && !launcherProcess.killed) return launcherProcess;
  launcherProcess = runPowerShell(getScriptPath('launch.ps1'), noBrowser ? ['-NoBrowser'] : []);
  return launcherProcess;
}

function stopStack() {
  runPowerShell(getScriptPath('launch.ps1'), ['-Stop']);
}

function showMainWindow() {
  if (!mainWindow) createMainWindow();
  mainWindow.show();
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
}

function toggleMainWindow() {
  if (!mainWindow) return createMainWindow();
  if (mainWindow.isVisible() && mainWindow.isFocused()) mainWindow.hide();
  else showMainWindow();
}

function createMainWindow() {
  const iconPng = path.join(__dirname, 'icon.png');
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 980,
    minHeight: 650,
    show: false,
    backgroundColor: '#060a12',
    title: 'Notion2Council',
    icon: fs.existsSync(iconPng) ? iconPng : undefined,
    webPreferences: { nodeIntegration: false, contextIsolation: true },
  });

  mainWindow.on('close', event => {
    if (!app.isQuitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.loadURL(councilUiUrl);
}

async function focusChatInput(text) {
  if (!mainWindow) return;
  const safeText = JSON.stringify(text || '');
  await mainWindow.webContents.executeJavaScript(`
    (() => {
      const input = document.querySelector('textarea.message-input, textarea, [contenteditable="true"]');
      if (!input) return false;
      input.focus();
      const text = ${safeText};
      if (text) {
        if ('value' in input) {
          input.value = text;
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
        } else {
          input.textContent = text;
          input.dispatchEvent(new InputEvent('input', { bubbles: true, data: text, inputType: 'insertText' }));
        }
      }
      return true;
    })();
  `).catch(error => appendLog(`focusChatInput failed: ${error.message}`));
}

async function openChat() {
  startStack({ noBrowser: true });
  showMainWindow();
  try {
    await waitForUrl(councilUiUrl, 90000);
    if (mainWindow && mainWindow.webContents.getURL() !== councilUiUrl) await mainWindow.loadURL(councilUiUrl);
    showMainWindow();
    await focusChatInput('');
  } catch (error) {
    appendLog(`Could not open chat: ${error.message}`);
  }
}

async function openChatWithClipboard() {
  const text = clipboard.readText() || '';
  await openChat();
  await focusChatInput(text);
}

function openNotionChat() {
  startStack({ noBrowser: true });
  shell.openExternal(notionApiUrl);
}

function openNotionDocs() {
  startStack({ noBrowser: true });
  shell.openExternal(notionDocsUrl);
}

function openCouncilUiExternal() {
  startStack({ noBrowser: true });
  shell.openExternal(councilUiUrl);
}

function openConfigFolder() {
  const appConfig = path.join(getAppRoot(), 'config');
  const userConfig = ensureDir(path.join(app.getPath('userData'), 'config'));
  shell.openPath(fs.existsSync(appConfig) ? appConfig : userConfig).then(errorMessage => {
    if (errorMessage) showError('Could not open config folder', errorMessage);
  });
}

function openLogsFolder() {
  shell.openPath(getLogsDir()).then(errorMessage => {
    if (errorMessage) showError('Could not open logs folder', errorMessage);
  });
}

function createTray() {
  const iconPng = path.join(__dirname, 'icon.png');
  const icon = fs.existsSync(iconPng) ? nativeImage.createFromPath(iconPng) : nativeImage.createEmpty();
  tray = new Tray(icon);
  tray.setToolTip('Notion2Council');
  tray.on('click', toggleMainWindow);
  refreshTrayMenu();
}

function refreshTrayMenu() {
  if (!tray) return;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Show / Hide', click: toggleMainWindow },
    { label: 'Open Chat', click: openChat },
    { label: 'Clipboard to Chat', click: openChatWithClipboard },
    { type: 'separator' },
    { label: 'Hotkey Settings', click: openHotkeySettings },
    { label: 'Open Notion2API Chat', click: openNotionChat },
    { label: 'Open Notion2API Docs', click: openNotionDocs },
    { label: 'Open Logs', click: openLogsFolder },
    { type: 'separator' },
    { label: 'Start Stack', click: () => startStack({ noBrowser: true }) },
    { label: 'Stop Stack', click: stopStack },
    { type: 'separator' },
    { label: 'Quit', click: () => { app.isQuitting = true; stopStack(); app.quit(); } },
  ]));
}

function setApplicationMenu() {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: 'Notion2Council', submenu: [
      { label: 'Open Chat', click: openChat },
      { label: 'Clipboard to Chat', click: openChatWithClipboard },
      { label: 'Hotkey Settings', click: openHotkeySettings },
      { type: 'separator' },
      { label: 'Open Notion2API Chat', click: openNotionChat },
      { label: 'Open Notion2API Docs', click: openNotionDocs },
      { label: 'Open Council in Browser', click: openCouncilUiExternal },
      { type: 'separator' },
      { label: 'Open Config Folder', click: openConfigFolder },
      { label: 'Open Logs Folder', click: openLogsFolder },
      { type: 'separator' },
      { label: 'Start Stack', click: () => startStack({ noBrowser: true }) },
      { label: 'Stop Stack', click: stopStack },
      { type: 'separator' },
      { label: 'Quit', click: () => { app.isQuitting = true; stopStack(); app.quit(); } },
    ] },
    { label: 'View', submenu: [
      { role: 'reload' },
      { role: 'toggleDevTools' },
      { role: 'resetZoom' },
      { role: 'zoomIn' },
      { role: 'zoomOut' },
    ] },
  ]));
}

function registerHotkeys() {
  globalShortcut.unregisterAll();
  const hotkeys = readHotkeys();
  const registrations = [];
  const bind = (name, accelerator, handler) => {
    if (!accelerator) return;
    const ok = globalShortcut.register(accelerator, handler);
    registrations.push({ name, accelerator, ok });
    if (!ok) appendLog(`Failed to register hotkey ${name}: ${accelerator}`);
  };
  bind('toggleWindow', hotkeys.toggleWindow, toggleMainWindow);
  bind('openChat', hotkeys.openChat, openChat);
  bind('clipboardToChat', hotkeys.clipboardToChat, openChatWithClipboard);
  bind('openHotkeySettings', hotkeys.openHotkeySettings, openHotkeySettings);
  return registrations;
}

function openHotkeySettings() {
  if (hotkeyWindow && !hotkeyWindow.isDestroyed()) {
    hotkeyWindow.show();
    hotkeyWindow.focus();
    return;
  }
  hotkeyWindow = new BrowserWindow({
    width: 720,
    height: 620,
    minWidth: 620,
    minHeight: 520,
    title: 'Notion2Council Hotkeys',
    backgroundColor: '#111827',
    parent: mainWindow || undefined,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), nodeIntegration: false, contextIsolation: true },
  });
  hotkeyWindow.on('closed', () => { hotkeyWindow = null; });
  hotkeyWindow.loadFile(path.join(__dirname, 'hotkeys.html'));
}

ipcMain.handle('hotkeys:get', () => ({ defaults: defaultHotkeys, current: readHotkeys(), configPath: getHotkeyConfigPath() }));
ipcMain.handle('hotkeys:save', (_event, hotkeys) => {
  writeHotkeys(hotkeys);
  const registrations = registerHotkeys();
  return { ok: registrations.every(item => item.ok), registrations, current: readHotkeys() };
});
ipcMain.handle('hotkeys:reset', () => {
  writeHotkeys(defaultHotkeys);
  const registrations = registerHotkeys();
  return { ok: registrations.every(item => item.ok), registrations, current: readHotkeys() };
});
ipcMain.handle('hotkeys:testClipboardToChat', async () => {
  await openChatWithClipboard();
  return { ok: true };
});

process.on('uncaughtException', error => {
  appendLog(`Uncaught exception: ${error.stack || error.message}`);
  if (error.code === 'ENOENT') showError('Process launch failed', error.message);
});

app.whenReady().then(async () => {
  appendLog(`App ready. appRoot=${getAppRoot()}`);
  createMainWindow();
  createTray();
  setApplicationMenu();
  registerHotkeys();
  startStack({ noBrowser: true });

  try {
    await waitForUrl(councilUiUrl, 90000);
    await mainWindow.loadURL(councilUiUrl);
  } catch (error) {
    appendLog(`Council UI not ready yet: ${error.message}`);
  }

  mainWindow.show();
});

app.on('window-all-closed', event => { event.preventDefault(); });
app.on('will-quit', () => { globalShortcut.unregisterAll(); });
