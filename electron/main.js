const { app, BrowserWindow, Menu, Tray, nativeImage, globalShortcut, clipboard, ipcMain, shell, dialog } = require('electron');
const { spawn } = require('child_process');
const fs = require('fs');
const http = require('http');
const path = require('path');

let mainWindow = null;
let hotkeyWindow = null;
let tray = null;
let launcherProcess = null;

const repoRoot = path.resolve(__dirname, '..');
const councilUiUrl = process.env.NOTION2COUNCIL_UI_URL || 'http://127.0.0.1:5173/';
const notionApiUrl = process.env.NOTION2API_URL || 'http://127.0.0.1:8000/';
const notionDocsUrl = process.env.NOTION2API_DOCS_URL || 'http://127.0.0.1:8000/docs';

const defaultHotkeys = {
  toggleWindow: 'Alt+Space',
  openChat: 'CommandOrControl+Shift+L',
  clipboardToChat: 'CommandOrControl+Shift+V',
  openHotkeySettings: 'CommandOrControl+Shift+H',
};

function getHotkeyConfigPath() {
  return path.join(app.getPath('userData'), 'hotkeys.json');
}

function readHotkeys() {
  const file = getHotkeyConfigPath();
  try {
    if (!fs.existsSync(file)) {
      return { ...defaultHotkeys };
    }
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    return { ...defaultHotkeys, ...parsed };
  } catch {
    return { ...defaultHotkeys };
  }
}

function writeHotkeys(hotkeys) {
  const file = getHotkeyConfigPath();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ ...defaultHotkeys, ...hotkeys }, null, 2), 'utf8');
}

function waitForUrl(url, timeoutMs = 90000) {
  const started = Date.now();

  return new Promise((resolve, reject) => {
    const tick = () => {
      const request = http.get(url, response => {
        response.resume();
        if (response.statusCode >= 200 && response.statusCode < 500) {
          resolve(true);
          return;
        }
        retry();
      });

      request.on('error', retry);
      request.setTimeout(2500, () => {
        request.destroy();
        retry();
      });
    };

    const retry = () => {
      if (Date.now() - started > timeoutMs) {
        reject(new Error(`Timed out waiting for ${url}`));
        return;
      }
      setTimeout(tick, 750);
    };

    tick();
  });
}

function runPowerShell(scriptPath, args = []) {
  const psArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, ...args];
  return spawn('powershell.exe', psArgs, {
    cwd: repoRoot,
    windowsHide: true,
    stdio: 'ignore',
    detached: false,
  });
}

function startStack({ noBrowser = true } = {}) {
  if (launcherProcess && !launcherProcess.killed) {
    return launcherProcess;
  }

  const scriptPath = path.join(repoRoot, 'scripts', 'launch.ps1');
  const args = noBrowser ? ['-NoBrowser'] : [];
  launcherProcess = runPowerShell(scriptPath, args);
  launcherProcess.on('exit', () => {
    launcherProcess = null;
  });
  return launcherProcess;
}

function stopStack() {
  const scriptPath = path.join(repoRoot, 'scripts', 'launch.ps1');
  runPowerShell(scriptPath, ['-Stop']);
}

function showMainWindow() {
  if (!mainWindow) {
    createMainWindow();
  }
  mainWindow.show();
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
}

function toggleMainWindow() {
  if (!mainWindow) {
    createMainWindow();
    return;
  }
  if (mainWindow.isVisible() && mainWindow.isFocused()) {
    mainWindow.hide();
  } else {
    showMainWindow();
  }
}

function createMainWindow() {
  const iconIco = path.join(__dirname, 'icon.ico');
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 980,
    minHeight: 650,
    show: false,
    backgroundColor: '#060a12',
    title: 'Notion2Council',
    icon: fs.existsSync(iconIco) ? iconIco : undefined,
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  mainWindow.on('close', event => {
    if (!app.isQuitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.loadURL(councilUiUrl);
}

async function openChat() {
  startStack({ noBrowser: true });
  showMainWindow();
  try {
    await waitForUrl(councilUiUrl, 90000);
    if (mainWindow && mainWindow.webContents.getURL() !== councilUiUrl) {
      await mainWindow.loadURL(councilUiUrl);
    }
    showMainWindow();
    await focusChatInput('');
  } catch (error) {
    showError('Could not open chat', error.message);
  }
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
  `).catch(() => false);
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
  shell.openPath(path.join(repoRoot, 'config'));
}

function openLogsFolder() {
  shell.openPath(path.join(repoRoot, 'logs'));
}

function showError(title, message) {
  dialog.showErrorBox(title, message || 'Unknown error');
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
    {
      label: 'Notion2Council',
      submenu: [
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
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'toggleDevTools' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
      ],
    },
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
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
    },
  });

  hotkeyWindow.on('closed', () => {
    hotkeyWindow = null;
  });

  hotkeyWindow.loadFile(path.join(__dirname, 'hotkeys.html'));
}

ipcMain.handle('hotkeys:get', () => {
  return {
    defaults: defaultHotkeys,
    current: readHotkeys(),
    configPath: getHotkeyConfigPath(),
  };
});

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

app.whenReady().then(async () => {
  createMainWindow();
  createTray();
  setApplicationMenu();
  registerHotkeys();
  startStack({ noBrowser: true });

  try {
    await waitForUrl(councilUiUrl, 90000);
    await mainWindow.loadURL(councilUiUrl);
  } catch {
    // Keep the shell alive even if the stack is not ready yet.
  }

  mainWindow.show();
});

app.on('window-all-closed', event => {
  event.preventDefault();
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});
