const { app, BrowserWindow } = require('electron')
const path = require('path')

function createWindow() {
  const win = new BrowserWindow({
    width: 1100,
    height: 700,
    minWidth: 900,
    minHeight: 600,
    backgroundColor: '#0b0b0d',
    autoHideMenuBar: true,
    title: 'VigiaCam',
    webPreferences: {
      contextIsolation: false,
      nodeIntegration: true
    }
  })
  win.loadFile(path.join(__dirname, 'app', 'index.html'))
}

app.whenReady().then(() => {
  createWindow()
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow() })
})

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit() })
