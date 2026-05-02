const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('notion2CouncilHotkeys', {
  get: () => ipcRenderer.invoke('hotkeys:get'),
  save: hotkeys => ipcRenderer.invoke('hotkeys:save', hotkeys),
  reset: () => ipcRenderer.invoke('hotkeys:reset'),
  testClipboardToChat: () => ipcRenderer.invoke('hotkeys:testClipboardToChat'),
});
