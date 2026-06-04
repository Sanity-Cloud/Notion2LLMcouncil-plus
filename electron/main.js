const { app, Menu, Tray, nativeImage, globalShortcut, clipboard, ipcMain, shell, dialog } = require('electron');
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
  if (!mainWindow) return false;

  const safeText = JSON.stringify(text || '');
  const shouldSubmit = JSON.stringify(!!submit);
  return mainWindow.webContents.executeJavaScript(`
    (() => {
      const selectors = [
        'textarea.message-input',
        'textarea.council-message-input',
        'textarea#chat-input',
        '.chat-container textarea.message-input',
        '.input-area textarea',
        'textarea'
      ];

      let input = null;
      for (const selector of selectors) {
        const found = document.querySelector(selector);
        if (found && found.offsetParent !== null && !found.disabled) {
          input = found;
          break;
        }
      }

      if (!input) return false;

      const text = ${safeText};
      input.focus();

      if (text) {
        const descriptor = Object.getOwnPropertyDescriptor(
          window.HTMLTextAreaElement.prototype,
          'value'
        );
        const setter = descriptor && descriptor.set;

        if (setter) {
          setter.call(input, text);
        } else {
          input.value = text;
        }

        input.dispatchEvent(new InputEvent('input', {
          bubbles: true,
          inputType: 'insertText',
          data: text
        }));
        input.dispatchEvent(new Event('change', { bubbles: true }));

        if (${shouldSubmit}) {
          input.dispatchEvent(new KeyboardEvent('keydown', {
            key: 'Enter',
            code: 'Enter',
            bubbles: true
          }));
        }
      }

      return true;
    })();
  `).catch(error => {
    appendLog(`focusChatInput failed: ${error.message}`);
    return false;
  });
}

async function ensureChatInputReady() {
  const mainWindow = getMainWindow();
  if (!mainWindow) return false;

  return mainWindow.webContents.executeJavaScript(`
    (async () => {
      const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
      const hasInput = () => !!document.querySelector('textarea.message-input, .input-area textarea, textarea');

      if (hasInput()) return true;

      const buttons = Array.from(document.querySelectorAll('button'));
      const newChatButton = document.querySelector('.new-council-btn') || buttons.find(btn =>
        /new|chat|conversation|discussion/i.test(btn.textContent || '')
      );

      if (newChatButton && !newChatButton.disabled) {
        newChatButton.click();
        for (let i = 0; i < 40; i += 1) {
          if (hasInput()) return true;
          await sleep(250);
        }
      }

      return hasInput();
    })();
  `).catch(error => {
    appendLog(`ensureChatInputReady failed: ${error.message}`);
    return false;
  });
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

async function getActiveRuntimeUrls(timeoutMs = 90000) {
  const config = getIntegrationConfig();

  try {
    const state = await waitForRuntimeState(config.statePath, timeoutMs);
    return {
      notionBaseUrl: state.notion.url,
      notionHealthUrl: `${state.notion.url}/health`,
      notionDocsUrl: `${state.notion.url}/docs`,
      councilUiUrl: state.councilFrontend.url,
      councilBackendUrl: state.councilBackend.url,
    };
  } catch {
    return {
      notionBaseUrl: config.notionBaseUrl,
      notionHealthUrl: config.notionHealthUrl,
      notionDocsUrl: config.notionDocsUrl,
      councilUiUrl: config.councilUiUrl,
      councilBackendUrl: config.councilBackendUrl,
    };
  }
}

async function isRuntimeReady(urls, timeoutMs = 2500) {
  try {
    await waitForUrl(urls.notionHealthUrl, timeoutMs, { expectedContent: 'ok' });
    await waitForUrl(urls.councilUiUrl, timeoutMs);
    return true;
  } catch {
    return false;
  }
}

async function waitForReadyRuntimeUrls() {
  let urls = await getActiveRuntimeUrls(1000);

  if (!(await isRuntimeReady(urls, 2500))) {
    startStack({ noBrowser: true });
    urls = await getActiveRuntimeUrls(90000);
  }

  await waitForUrl(urls.notionHealthUrl, 90000, { expectedContent: 'ok' });
  await waitForUrl(urls.councilUiUrl, 90000);
  return urls;
}

async function waitForReadyNotionUrls() {
  let urls = await getActiveRuntimeUrls(1000);

  try {
    await waitForUrl(urls.notionHealthUrl, 2500, { expectedContent: 'ok' });
    return urls;
  } catch {
    startStack({ noBrowser: true });
    urls = await getActiveRuntimeUrls(90000);
    await waitForUrl(urls.notionHealthUrl, 90000, { expectedContent: 'ok' });
    return urls;
  }
}

async function openNotion2ApiBrowser() {
  try {
    const urls = await waitForReadyNotionUrls();
    appendLog(`Opening Notion2API in browser: ${urls.notionBaseUrl}`);
    return shell.openExternal(urls.notionBaseUrl);
  } catch (error) {
    appendLog(`Could not open Notion2API browser window: ${error.message}`);
    const fallbackUrl = getIntegrationConfig().notionBaseUrl;
    return shell.openExternal(fallbackUrl);
  }
}

async function openNotion2ApiDocsBrowser() {
  try {
    const urls = await waitForReadyNotionUrls();
    const docsUrl = process.env.NOTION2API_DOCS_URL || urls.notionDocsUrl;
    appendLog(`Opening Notion2API docs in browser: ${docsUrl}`);
    return shell.openExternal(docsUrl);
  } catch (error) {
    appendLog(`Could not open Notion2API docs browser window: ${error.message}`);
    return shell.openExternal(process.env.NOTION2API_DOCS_URL || getIntegrationConfig().notionDocsUrl);
  }
}

async function openChat() {
  showMainWindow();

  try {
    const urls = await waitForReadyRuntimeUrls();
    const mainWindow = getMainWindow();

    if (mainWindow && !mainWindow.webContents.getURL().startsWith(urls.councilUiUrl)) {
      await mainWindow.loadURL(urls.councilUiUrl);
    }

    showMainWindow();
    const ready = await ensureChatInputReady();
    if (!ready) {
      appendLog('Could not open chat input: no active conversation/input was available');
      return false;
    }

    return focusChatInput('');
  } catch (error) {
    appendLog(`Could not open chat: ${error.message}`);
    return false;
  }
}

async function openChatWithClipboard() {
  const text = clipboard.readText() || '';
  const opened = await openChat();
  if (!opened) return;

  const injected = await focusChatInput(text);
  if (!injected) {
    appendLog('Clipboard to Chat failed: chat input was not found');
  }
}

async function createNewChatInputReady() {
  const mainWindow = getMainWindow();
  if (!mainWindow) return false;

  return mainWindow.webContents.executeJavaScript(`
    (async () => {
      const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
      const hasInput = () => !!document.querySelector('textarea.message-input, .input-area textarea, textarea');

      const buttons = Array.from(document.querySelectorAll('button'));
      const newChatButton = document.querySelector('.new-council-btn') || buttons.find(btn =>
        /new|chat|conversation|discussion/i.test(btn.textContent || '')
      );

      if (!newChatButton || newChatButton.disabled) return false;

      newChatButton.click();

      for (let i = 0; i < 40; i += 1) {
        if (hasInput()) return true;
        await sleep(250);
      }

      return hasInput();
    })();
  `).catch(error => {
    appendLog(`createNewChatInputReady failed: ${error.message}`);
    return false;
  });
}

async function openNewChat() {
  showMainWindow();

  try {
    const urls = await waitForReadyRuntimeUrls();
    const mainWindow = getMainWindow();

    if (mainWindow && !mainWindow.webContents.getURL().startsWith(urls.councilUiUrl)) {
      await mainWindow.loadURL(urls.councilUiUrl);
    }

    showMainWindow();

    const ready = await createNewChatInputReady();
    if (!ready) {
      appendLog('Could not create new chat input');
      return false;
    }

    return focusChatInput('');
  } catch (error) {
    appendLog(`Could not open new chat: ${error.message}`);
    return false;
  }
}

async function openNewChatWithClipboard() {
  const text = clipboard.readText() || '';
  const opened = await openNewChat();
  if (!opened) return;

  const injected = await focusChatInput(text);
  if (!injected) {
    appendLog('Clipboard to New Chat failed: chat input was not found');
  }
}


function showAboutDialog() {
  const mainWindow = getMainWindow();
  const iconPath = path.join(__dirname, 'icon.png');
  const appIcon = fs.existsSync(iconPath) ? nativeImage.createFromPath(iconPath) : undefined;
  
  dialog.showMessageBox(mainWindow && mainWindow.isVisible() ? mainWindow : null, {
    type: 'info',
    title: 'About Notion2Council',
    message: 'Notion2Council',
    detail: `Version: ${app.getVersion()}\n\nDesktop shell and launcher menu for Notion2LLMcouncil Plus.\n\nAuthor: Sanity Cloud\n\nRuntime info:\n• Electron: ${process.versions.electron}\n• Node: ${process.versions.node}\n• Chrome: ${process.versions.chrome}`,
    buttons: ['OK'],
    defaultId: 0,
    icon: appIcon
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
  const hotkeys = readHotkeys();
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Show / Hide', accelerator: hotkeys.toggleWindow, click: toggleMainWindow },
    { label: 'Open Chat', accelerator: hotkeys.openChat, click: openChat },
    { label: 'Open New Chat', accelerator: hotkeys.openNewChat, click: openNewChat },
    { label: 'Clipboard to Chat', accelerator: hotkeys.clipboardToChat, click: openChatWithClipboard },
    { label: 'Clipboard to New Chat', accelerator: hotkeys.clipboardToNewChat, click: openNewChatWithClipboard },
    { type: 'separator' },
    { label: 'About Notion2Council', click: showAboutDialog },
    { type: 'separator' },
    { label: 'Diagnostics', click: () => openDiagnostics(getMainWindow()) },
    { label: 'Hotkey Settings', accelerator: hotkeys.openHotkeySettings, click: () => openHotkeySettings(getMainWindow()) },
    { label: 'Reset LLM Council UI State', click: async () => {
        await clearCouncilUiStorage();
        const mainWindow = getMainWindow();
        if (mainWindow) mainWindow.reload();
      }
    },
    { label: 'Open Notion2API Browser', click: openNotion2ApiBrowser },
    { label: 'Open Notion2API Docs', click: openNotion2ApiDocsBrowser },
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
  const hotkeys = readHotkeys();
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    { label: 'Notion2Council', submenu: [
      { label: 'About Notion2Council', click: showAboutDialog },
      { type: 'separator' },
      { label: 'Open Chat', accelerator: hotkeys.openChat, click: openChat },
      { label: 'Open New Chat', accelerator: hotkeys.openNewChat, click: openNewChat },
      { label: 'Clipboard to Chat', accelerator: hotkeys.clipboardToChat, click: openChatWithClipboard },
      { label: 'Clipboard to New Chat', accelerator: hotkeys.clipboardToNewChat, click: openNewChatWithClipboard },
      { type: 'separator' },
      { label: 'Open Notion2API Browser', click: openNotion2ApiBrowser },
      { label: 'Open Notion2API Docs', click: openNotion2ApiDocsBrowser },
      { type: 'separator' },
      { label: 'Diagnostics', click: () => openDiagnostics(getMainWindow()) },
      { label: 'Hotkey Settings', accelerator: hotkeys.openHotkeySettings, click: () => openHotkeySettings(getMainWindow()) },
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
  bind('openNewChat', hotkeys.openNewChat, openNewChat);
  bind('clipboardToChat', hotkeys.clipboardToChat, openChatWithClipboard);
  bind('clipboardToNewChat', hotkeys.clipboardToNewChat, openNewChatWithClipboard);
  bind('openHotkeySettings', hotkeys.openHotkeySettings, () => openHotkeySettings(getMainWindow()));
  return registrations;
}

// IPC Handlers
ipcMain.handle('hotkeys:get', () => ({ defaults: defaultHotkeys, current: readHotkeys(), configPath: getHotkeyConfigPath() }));
ipcMain.handle('hotkeys:save', (_event, hotkeys) => {
  writeHotkeys(hotkeys);
  const registrations = registerHotkeys();
  setApplicationMenu();
  refreshTrayMenu();
  return { ok: registrations.every(item => item.ok), registrations, current: readHotkeys() };
});
ipcMain.handle('hotkeys:reset', () => {
  writeHotkeys(defaultHotkeys);
  const registrations = registerHotkeys();
  setApplicationMenu();
  refreshTrayMenu();
  return { ok: registrations.every(item => item.ok), registrations, current: readHotkeys() };
});
ipcMain.handle('hotkeys:testClipboardToChat', async () => {
  await openChatWithClipboard();
  return { ok: true };
});
ipcMain.handle('hotkeys:testClipboardToNewChat', async () => {
  await openNewChatWithClipboard();
  return { ok: true };
});
ipcMain.handle('diagnostics:status', getDiagnosticsStatus);
ipcMain.handle('diagnostics:getConfig', getEditableLocalConfig);
ipcMain.handle('diagnostics:saveConfig', (_event, values) => saveLocalIntegrationConfig(values));
ipcMain.handle('diagnostics:start', () => ({ ok: !!startStack({ noBrowser: true }) }));
ipcMain.handle('diagnostics:stop', () => ({ ok: !!stopStack() }));
ipcMain.handle('diagnostics:openCouncil', async () => {
  const urls = await getActiveRuntimeUrls(1000);
  return shell.openExternal(urls.councilUiUrl);
});
ipcMain.handle('diagnostics:openNotion', openNotion2ApiBrowser);
ipcMain.handle('diagnostics:openDocs', openNotion2ApiDocsBrowser);
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
    await waitForUrl(activeCouncilUiUrl, 90000);
    
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