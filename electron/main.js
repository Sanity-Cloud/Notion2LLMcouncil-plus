const { app, Menu, Tray, nativeImage, globalShortcut, clipboard, ipcMain, shell } = require('electron');
const path = require('path');
const fs = require('fs');

// Internal Modules
const { appendLog } = require('./lib/logger');
const { readHotkeys, writeHotkeys, defaultHotkeys, getHotkeyConfigPath } = require('./lib/config');
const { waitForUrl, waitForRuntimeState } = require('./lib/utils');
const { startStack, stopStack } = require('./lib/launcher');
const { getIntegrationConfig, getEditableLocalConfig, saveLocalIntegrationConfig } = require('./lib/integration-config');
const { getDiagnosticsStatus } = require('./lib/diagnostics');
const { createMainWindow, getMainWindow, showMainWindow, toggleMainWindow } = require('./windows/main');
const { openHotkeySettings } = require('./windows/hotkeys');
const { openDiagnostics } = require('./windows/diagnostics');

let tray = null;
let isQuitting = false;
const initialConfig = getIntegrationConfig();
const councilUiUrl = initialConfig.councilUiUrl;

async function focusChatInput(text, submit = false) {
  const mainWindow = getMainWindow();
  if (!mainWindow) return;
  const safeText = JSON.stringify(text || '');
  const shouldSubmit = JSON.stringify(!!submit);
  await mainWindow.webContents.executeJavaScript(`
    (() => {
      // Tightened selectors prioritizing specific chat input classes
      const selectors = [
        'textarea.council-message-input',
        'textarea#chat-input',
        '.chat-container textarea.message-input',
        '.input-area textarea',
        'textarea.message-input',
        'textarea'
      ];
      
      let input = null;
      for (const selector of selectors) {
        const found = document.querySelector(selector);
        // Ensure it's visible and not disabled
        if (found && found.offsetParent !== null && !found.disabled) {
          input = found;
          break;
        }
      }
      
      if (!input) return false;
      
      input.focus();
      const text = ${safeText};
      if (text) {
        // Clear if we are setting new text
        input.value = '';
        input.value = text;
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
        
        // Only auto-submit when explicitly requested. Clipboard-to-chat should populate, not send.
        const doSubmit = ${shouldSubmit};
        if (doSubmit) {
          input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
        }
      }
      return true;
    })();
  `).catch(error => appendLog(`focusChatInput failed: ${error.message}`));
}

async function clearCouncilUiStorage() {
  const mainWindow = getMainWindow();
  if (!mainWindow) return;

  const config = getIntegrationConfig();
  let originUrl = config.councilUiUrl;
  try {
    if (fs.existsSync(config.statePath)) {
      const state = JSON.parse(fs.readFileSync(config.statePath, 'utf8'));
      if (state && state.councilFrontend && state.councilFrontend.url) {
        originUrl = state.councilFrontend.url;
      }
    }
  } catch {}

  try {
    await mainWindow.webContents.session.clearStorageData({
      origin: originUrl,
      storages: ['localstorage', 'indexdb', 'cookies']
    });
    appendLog(`Successfully cleared LLM Council UI storage (localstorage, indexdb, cookies) for origin: ${originUrl}`);
  } catch (error) {
    appendLog(`Failed to clear LLM Council UI storage: ${error.message}`);
  }
}

async function openChat() {
  const config = getIntegrationConfig();
  startStack({ noBrowser: true });
  showMainWindow();
  try {
    await waitForUrl(config.notionHealthUrl, 90000, { expectedContent: 'ok' });
    await waitForUrl(config.councilUiUrl, 90000, { expectedTitle: 'LLM Council' });
    const mainWindow = getMainWindow();
    if (mainWindow && mainWindow.webContents.getURL() !== config.councilUiUrl) {
      await mainWindow.loadURL(config.councilUiUrl);
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
    { label: 'Diagnostics', click: () => openDiagnostics(getMainWindow()) },
    { label: 'Hotkey Settings', click: () => openHotkeySettings(getMainWindow()) },
    { label: 'Reset LLM Council UI State', click: async () => {
        await clearCouncilUiStorage();
        const mainWindow = getMainWindow();
        if (mainWindow) mainWindow.reload();
      }
    },
    { label: 'Open Notion2API', click: () => { startStack({ noBrowser: true }); shell.openExternal(getIntegrationConfig().notionBaseUrl); } },
    { label: 'Open Notion2API Docs', click: () => { startStack({ noBrowser: true }); shell.openExternal(process.env.NOTION2API_DOCS_URL || getIntegrationConfig().notionDocsUrl); } },
    { label: 'Open App Logs', click: () => { shell.openPath(path.join(app.getPath('userData'), 'logs')); } },
    { label: 'Open Service Logs', click: () => { shell.openPath(getIntegrationConfig().logsDir); } },
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
      { label: 'Diagnostics', click: () => openDiagnostics(getMainWindow()) },
      { label: 'Hotkey Settings', click: () => openHotkeySettings(getMainWindow()) },
      { label: 'Reset LLM Council UI State', click: async () => {
          await clearCouncilUiStorage();
          const mainWindow = getMainWindow();
          if (mainWindow) mainWindow.reload();
        }
      },
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
ipcMain.handle('diagnostics:status', getDiagnosticsStatus);
ipcMain.handle('diagnostics:getConfig', getEditableLocalConfig);
ipcMain.handle('diagnostics:saveConfig', (_event, values) => saveLocalIntegrationConfig(values));
ipcMain.handle('diagnostics:start', () => ({ ok: !!startStack({ noBrowser: true }) }));
ipcMain.handle('diagnostics:stop', () => ({ ok: !!stopStack() }));
ipcMain.handle('diagnostics:openCouncil', () => shell.openExternal(getIntegrationConfig().councilUiUrl));
ipcMain.handle('diagnostics:openDocs', () => shell.openExternal(process.env.NOTION2API_DOCS_URL || getIntegrationConfig().notionDocsUrl));
ipcMain.handle('diagnostics:openLogs', () => shell.openPath(getIntegrationConfig().logsDir));

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
    const config = getIntegrationConfig();
    appendLog('Waiting for launcher-state.json to be populated by the PowerShell orchestrator...');
    
    // Wait for the state file to be fully written and populated with all 3 services
    const state = await waitForRuntimeState(config.statePath, 90000);
    
    const activeNotionHealthUrl = `${state.notion.url}/health`;
    const activeCouncilUiUrl = state.councilFrontend.url;
    
    appendLog(`Dynamic active ports resolved. Waiting for health checks on Notion2API (${activeNotionHealthUrl}) and Council UI (${activeCouncilUiUrl})`);

    // Wait for the UI to be ready before loading
    await waitForUrl(activeNotionHealthUrl, 90000, { expectedContent: 'ok' });
    await waitForUrl(activeCouncilUiUrl, 90000, { expectedTitle: 'LLM Council' });
    
    // Clear storage on provider drift has been disabled to prevent destruction of UI metadata.
    // UI state can still be reset manually via the "Reset LLM Council UI State" menu action.
    await mainWindow.loadURL(activeCouncilUiUrl);
  } catch (error) {
    appendLog(`Council UI failed to load: ${error.message}`);
    openDiagnostics(mainWindow);
  }

  mainWindow.show();
});

app.on('before-quit', (e) => {
  if (isQuitting) return;            // re-entry guard
  isQuitting = true;
  app.isQuitting = true;             // keep window close-handlers happy

  e.preventDefault();                // hold the quit until stopStack settles

  appendLog('App quitting - stopping background services');
  const child = stopStack();

  const finish = () => {
    try { app.removeAllListeners('before-quit'); } catch {}
    app.quit();
  };

  if (!child || typeof child.once !== 'function') {
    finish();
    return;
  }

  let done = false;
  const finalize = () => { if (done) return; done = true; finish(); };

  child.once('exit', finalize);
  child.once('error', finalize);
  setTimeout(finalize, 8000);        // hard cap so a stuck PS process can't trap us
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
