const { app } = require('electron');
const fs = require('fs');
const path = require('path');

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
  const dir = path.dirname(file);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(file, JSON.stringify({ ...defaultHotkeys, ...hotkeys }, null, 2), 'utf8');
}

module.exports = {
  defaultHotkeys,
  getHotkeyConfigPath,
  readHotkeys,
  writeHotkeys
};
