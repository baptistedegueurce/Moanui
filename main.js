const { app, BrowserWindow } = require('electron');
const { spawn } = require('child_process');
const http = require('http');
const path = require('path');

let mainWindow;
let splashWindow;
let rProcess;

function createSplash() {
  splashWindow = new BrowserWindow({
    width: 600,
    height: 400,
    frame: false,
    alwaysOnTop: true,
    transparent: false,
    resizable: false,
    icon: path.join(path.dirname(__dirname), 'icon.ico')
  });

  splashWindow.loadFile(path.join(__dirname, 'splash.html'));
}

function createWindow() {
  mainWindow = new BrowserWindow({
    autoHideMenuBar: true,
    icon: path.join(path.dirname(__dirname), 'icon.ico'),
    show: false
  });
  mainWindow.maximize();

  mainWindow.loadURL('http://127.0.0.1:3838');

  mainWindow.once('ready-to-show', () => {
    if (splashWindow) {
      splashWindow.webContents.executeJavaScript('window.__finishBar()').catch(() => {});
      setTimeout(() => {
        if (splashWindow && !splashWindow.isDestroyed()) splashWindow.close();
        mainWindow.show();
        mainWindow.setAlwaysOnTop(true);
        mainWindow.focus();
        setTimeout(() => mainWindow.setAlwaysOnTop(false), 500);
      }, 700);
    } else {
      mainWindow.show();
      mainWindow.setAlwaysOnTop(true);
      mainWindow.focus();
      setTimeout(() => mainWindow.setAlwaysOnTop(false), 500);
    }
  });
}

app.whenReady().then(() => {
  createSplash();

  const appDir = path.dirname(__dirname);
  const rScript = path.join(appDir, 'run.R');
  const rExe = path.join(appDir, 'R-portable', 'bin', 'Rscript.exe');

  rProcess = spawn(rExe, [rScript], {
    cwd: appDir,
    detached: true,
    stdio: 'inherit',
    windowsHide: false
  });

  rProcess.unref();

  let attempts = 0;
  const maxAttempts = 120;

  const checkServer = () => {
    const req = http.get('http://127.0.0.1:3838', () => {
      createWindow();
    });
    req.on('error', () => {
      attempts++;
      if (attempts >= maxAttempts) { app.quit(); return; }
      setTimeout(checkServer, 1000);
    });
    req.end();
  };

  checkServer();
});

app.on('window-all-closed', () => {
  if (rProcess) { try { rProcess.kill(); } catch(e) {} }
  app.quit();
});