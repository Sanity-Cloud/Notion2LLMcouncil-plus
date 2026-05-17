const { app } = require('electron');
const fs = require('fs');
const path = require('path');

const defaultHotkeys = {
  toggleWindow: 'CommandOrControl+Alt+Space',
  openChat: 'CommandOrControl+Alt+L',
  openNewChat: 'CommandOrControl+Alt+N',
  clipboardToChat: 'CommandOrControl+Alt+V',
  clipboardToNewChat: 'CommandOrControl+Alt+Shift+V',
  openHotkeySettings: 'CommandOrControl+Alt+H',
};

const legacyDefaultHotkeys = {
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

    const saved = JSON.parse(fs.readFileSync(file, 'utf8'));
    const merged = { ...defaultHotkeys, ...saved };

    // Migrate only the known old defaults that commonly conflict on Windows.
    // User-customized accelerators are preserved.
    for (const [name, legacyValue] of Object.entries(legacyDefaultHotkeys)) {
      if (merged[name] === legacyValue) merged[name] = defaultHotkeys[name];
    }

    return merged;
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