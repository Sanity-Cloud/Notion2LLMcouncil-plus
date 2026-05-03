const { BrowserWindow, app } = require('electron');
const path = require('path');
const fs = require('fs');
const { appendLog } = require('../lib/logger');

let mainWindow = null;

function createMainWindow(councilUiUrl) {
  if (mainWindow) return mainWindow;

  const iconPng = path.join(__dirname, '..', 'icon.png');
  
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 980,
    minHeight: 650,
    show: false,
    backgroundColor: '#060a12',
    title: 'Notion2Council',
    icon: fs.existsSync(iconPng) ? iconPng : undefined,
    webPreferences: { 
      nodeIntegration: false, 
      contextIsolation: true,
      sandbox: true // Security hardening
    },
  });

  mainWindow.on('close', event => {
    if (!app.isQuitting) {
      event.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  return mainWindow;
}

function getMainWindow() {
  return mainWindow;
}

function showMainWindow() {
  if (!mainWindow) return;
  mainWindow.show();
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
}

function toggleMainWindow() {
  if (!mainWindow) return;
  if (mainWindow.isVisible() && mainWindow.isFocused()) {
    mainWindow.hide();
  } else {
    showMainWindow();
  }
}

module.exports = {
  createMainWindow,
  getMainWindow,
  showMainWindow,
  toggleMainWindow
};
