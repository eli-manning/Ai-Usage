const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('settingsAPI', {
  getUsage: () => ipcRenderer.invoke('get-usage'),
  getSettings: () => ipcRenderer.invoke('get-settings'),
  setProviderEnabled: (id, enabled) => ipcRenderer.invoke('set-provider-enabled', id, enabled),
  openProviderLogin: (id) => ipcRenderer.invoke('open-provider-login', id),
  onUsageUpdate: (cb) => ipcRenderer.on('usage-update', (_, data) => cb(data)),
  closeSettings: () => ipcRenderer.invoke('close-settings'),
});
