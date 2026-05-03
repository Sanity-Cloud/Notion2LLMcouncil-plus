const { app, Menu, Tray, nativeImage, globalShortcut, clipboard, ipcMain, shell } = require('electron');
const path = require('path');
const fs = require('fs');

// Internal Modules
const { appendLog } = require('./lib/logger');
const { readHotkeys, writeHotkeys, defaultHotkeys, getHotkeyConfigPath } = require('./lib/config');
const { waitForUrl } = require('./lib/utils');
const { startStack, stopStack } = require('./lib/launcher');
const { createMainWindow, getMainWindow, showMainWindow, toggleMainWindow } = require('./windows/main');
const { openHotkeySettings } = require('./windows/hotkeys');

let tray = null;
let isQuitting = false;
const councilUiUrl = process.env.NOTION2COUNCIL_UI_URL || 'http://127.0.0.1:5173/';
const notionApiUrl = process.env.NOTION2API_URL || 'http://127.0.0.1:8000/';
const notionDocsUrl = process.env.NOTION2API_DOCS_URL || 'http://127.0.0.1:8000/docs';

async function focusChatInput(text) {
  const mainWindow = getMainWindow();
  if (!mainWindow) return;
  const safeText = JSON.stringify(text || '');
  await mainWindow.webContents.executeJavaScript(`
    (() => {
      const input = document.querySelector('textarea.message-input') || 
                    document.querySelector('.input-area textarea') ||
                    document.querySelector('textarea');
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
    const mainWindow = getMainWindow();
    if (mainWindow && mainWindow.webContents.getURL() !== councilUiUrl) {
      await mainWindow.loadURL(councilUiUrl);
    }
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
    { label: 'Hotkey Settings', click: () => openHotkeySettings(getMainWindow()) },
    { label: 'Open Notion2API Chat', click: () => { startStack({ noBrowser: true }); shell.openExternal(notionApiUrl); } },
    { label: 'Open Notion2API Docs', click: () => { startStack({ noBrowser: true }); shell.openExternal(notionDocsUrl); } },
    { label: 'Open Logs', click: () => { shell.openPath(path.join(app.getPath('userData'), 'logs')); } },
    { type: 'separator' },
    { label: 'Start Stack', click: () => startStack({ noBrowser: true }) },
    { label: 'Stop Stack', click: stopStack },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() },
  ]));
}

function setApplicationMenu() {
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: 'Notion2Council', submenu: [
      { label: 'Open Chat', click: openChat },
      { label: 'Clipboard to Chat', click: openChatWithClipboard },
      { label: 'Hotkey Settings', click: () => openHotkeySettings(getMainWindow()) },
      { type: 'separator' },
      { label: 'Quit', click: () => app.quit() },
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
  bind('openHotkeySettings', hotkeys.openHotkeySettings, () => openHotkeySettings(getMainWindow()));
  return registrations;
}

// IPC Handlers
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

// App Lifecycle
app.whenReady().then(async () => {
  appendLog('App ready - starting Notion2Council stack');
  
  const mainWindow = createMainWindow(councilUiUrl);
  createTray();
  setApplicationMenu();
  registerHotkeys();
  
  // Start backend stack asynchronously
  startStack({ noBrowser: true });

  try {
    // Wait for the UI to be ready before loading
    await waitForUrl(councilUiUrl, 90000);
    await mainWindow.loadURL(councilUiUrl);
  } catch (error) {
    appendLog(`Council UI failed to load: ${error.message}`);
    // Optional: Load a local error page
  }

  mainWindow.show();
});

app.on('before-quit', () => {
  appendLog('App quitting - stopping background services');
  isQuitting = true;
  stopStack();
});

app.on('activate', () => {
  const mainWindow = getMainWindow();
  if (mainWindow) {
    showMainWindow();
  } else {
    createMainWindow(councilUiUrl);
  }
});

app.on('window-all-closed', () => {
  // On macOS it is common for applications and their menu bar
  // to stay active until the user quits explicitly with Cmd + Q
  if (process.platform !== 'darwin') {
    // We stay in tray on Windows/Linux by default, but let's be explicit
    // If you want to quit when windows close, uncomment the next line:
    // if (!isQuitting) app.quit();
  }
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});

process.on('uncaughtException', error => {
  appendLog(`Uncaught exception: ${error.stack || error.message}`);
});
