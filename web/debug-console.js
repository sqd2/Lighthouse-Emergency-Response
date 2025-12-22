// On-screen debug console for iPhone testing
(function() {
  // Only enable on web
  if (typeof window === 'undefined') return;

  // Create console container with textarea for easy copying
  const consoleDiv = document.createElement('div');
  consoleDiv.id = 'debug-console';
  consoleDiv.style.cssText = `
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    height: 200px;
    background: rgba(0, 0, 0, 0.9);
    z-index: 999999;
    display: none;
    border-top: 2px solid #0f0;
    padding: 8px;
  `;

  // Create textarea for logs (easier to select on mobile)
  const logTextarea = document.createElement('textarea');
  logTextarea.readOnly = true;
  logTextarea.style.cssText = `
    width: 100%;
    height: 100%;
    background: rgba(0, 0, 0, 0.8);
    color: #0f0;
    font-family: monospace;
    font-size: 10px;
    border: none;
    resize: none;
    padding: 4px;
    outline: none;
  `;
  consoleDiv.appendChild(logTextarea);

  // Create copy button
  const copyBtn = document.createElement('button');
  copyBtn.textContent = '📋 Copy Logs';
  copyBtn.style.cssText = `
    position: fixed;
    top: 10px;
    right: 10px;
    padding: 10px 20px;
    background: rgba(0, 255, 0, 0.8);
    border: 2px solid #0f0;
    border-radius: 5px;
    font-size: 14px;
    font-weight: bold;
    z-index: 1000001;
    cursor: pointer;
    color: black;
  `;

  // Store raw log text
  window.debugLogs = [];

  copyBtn.onclick = function() {
    const logText = window.debugLogs.join('\n');
    navigator.clipboard.writeText(logText).then(() => {
      copyBtn.textContent = '✅ Copied!';
      copyBtn.style.background = 'rgba(0, 255, 0, 1)';
      setTimeout(() => {
        copyBtn.textContent = '📋 Copy Logs';
        copyBtn.style.background = 'rgba(0, 255, 0, 0.8)';
      }, 2000);
    }).catch(err => {
      console.error('Failed to copy:', err);
      copyBtn.textContent = '❌ Failed';
      setTimeout(() => {
        copyBtn.textContent = '📋 Copy Logs';
      }, 2000);
    });
  };

  // Create toggle button
  const toggleBtn = document.createElement('button');
  toggleBtn.textContent = '🐛';
  toggleBtn.style.cssText = `
    position: fixed;
    bottom: 10px;
    right: 10px;
    width: 50px;
    height: 50px;
    background: rgba(0, 255, 0, 0.8);
    border: 2px solid #0f0;
    border-radius: 50%;
    font-size: 24px;
    z-index: 1000000;
    cursor: pointer;
  `;

  let isVisible = false;
  toggleBtn.onclick = function() {
    isVisible = !isVisible;
    consoleDiv.style.display = isVisible ? 'block' : 'none';
    copyBtn.style.display = isVisible ? 'block' : 'none';
    toggleBtn.style.background = isVisible ? 'rgba(255, 0, 0, 0.8)' : 'rgba(0, 255, 0, 0.8)';
    if (isVisible) {
      // Select all text when opened to make it easy to copy
      logTextarea.select();
    }
  };

  // Add to page
  document.body.appendChild(consoleDiv);
  document.body.appendChild(toggleBtn);
  document.body.appendChild(copyBtn);
  copyBtn.style.display = 'none'; // Hidden by default

  // Log function
  function addLog(type, args) {
    const timestamp = new Date().toLocaleTimeString();
    const message = Array.from(args).map(arg => {
      if (typeof arg === 'object') {
        try {
          return JSON.stringify(arg, null, 2);
        } catch (e) {
          return String(arg);
        }
      }
      return String(arg);
    }).join(' ');

    // Store raw log text for copying
    const rawLog = `[${timestamp}] ${type.toUpperCase()}: ${message}`;
    window.debugLogs.push(rawLog);

    // Keep only last 100 logs in memory
    if (window.debugLogs.length > 100) {
      window.debugLogs.shift();
    }

    // Update textarea with all logs
    logTextarea.value = window.debugLogs.join('\n');
    logTextarea.scrollTop = logTextarea.scrollHeight;
  }

  // Override console methods
  const originalLog = console.log;
  const originalError = console.error;
  const originalWarn = console.warn;
  const originalInfo = console.info;

  console.log = function() {
    originalLog.apply(console, arguments);
    addLog('log', arguments);
  };

  console.error = function() {
    originalError.apply(console, arguments);
    addLog('error', arguments);
  };

  console.warn = function() {
    originalWarn.apply(console, arguments);
    addLog('warn', arguments);
  };

  console.info = function() {
    originalInfo.apply(console, arguments);
    addLog('info', arguments);
  };

  console.log('✅ Debug console initialized - tap 🐛 button to toggle');
})();
