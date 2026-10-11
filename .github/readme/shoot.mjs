// Screenshots of the app window from the landing pages for the README.
// Renders #window from index.html and en/index.html in headless Chrome and saves
// app-ru.png and app-en.png next to this script: 1800×738, transparent corners.
//
//   node .github/readme/shoot.mjs
//
// Needs macOS (sips) and Google Chrome; set CHROME to use another Chromium build.

import { spawn, execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..');
const CHROME = process.env.CHROME || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const SHOTS = [
  ['index.html', 'app-ru.png'],
  ['en/index.html', 'app-en.png'],
];
// Captured at 2x, then scaled down to the README size.
const OUT_W = 1800, OUT_H = 738;

async function shoot(page, out) {
  const port = 9300 + Math.floor(Math.random() * 600);
  const profile = mkdtempSync(join(tmpdir(), 'routekeeper-shoot-'));
  const chrome = spawn(CHROME, [
    '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--hide-scrollbars', '--force-color-profile=srgb', 'about:blank',
  ], { stdio: 'ignore' });
  let ws;
  try {
    let target;
    for (let i = 0; i < 50 && !target; i++) {
      try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find((t) => t.type === 'page'); }
      catch { await sleep(200); }
    }
    if (!target) throw new Error('Chrome did not start');
    ws = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((r) => { ws.onopen = r; });
    let id = 0;
    const pending = new Map();
    ws.onmessage = (m) => {
      const d = JSON.parse(m.data);
      if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); }
    };
    const send = (method, params = {}) => new Promise((res, rej) => {
      const i = ++id;
      pending.set(i, (d) => (d.error ? rej(new Error(`${method}: ${d.error.message}`)) : res(d.result)));
      ws.send(JSON.stringify({ id: i, method, params }));
    });
    const run = async (expression) =>
      (await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })).result.value;

    await send('Page.enable');
    await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1100, deviceScaleFactor: 2, mobile: false });
    await send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 0, g: 0, b: 0, a: 0 } });
    await send('Page.navigate', { url: pathToFileURL(join(root, page)).href });
    await sleep(1500);
    await run('document.fonts.ready.then(() => true)');
    // Bring the window into view so it straightens up and the trains start running.
    await run(`(() => { const w = document.getElementById('window'); w.scrollIntoView({ block: 'center' }); w.classList.add('in'); return true; })()`);
    await sleep(4500);
    // Leave only the window on a transparent page, snapped to whole pixels so its edges stay crisp.
    await run(`(() => {
      const st = document.createElement('style');
      st.textContent = 'html, body { background: transparent !important; } html::before, html::after, body::before, body::after, .stage::before { display: none !important; } body * { visibility: hidden !important; } #window, #window * { visibility: visible !important; } #window { box-shadow: none !important; transform: none !important; transition: none !important; }';
      document.head.append(st);
      const w = document.getElementById('window'), b = w.getBoundingClientRect();
      w.style.position = 'relative';
      w.style.left = Math.ceil(b.x) - b.x + 'px';
      w.style.top = Math.ceil(b.y + scrollY) - (b.y + scrollY) + 'px';
      return true;
    })()`);
    await sleep(300);
    const clip = await run(`(() => { const b = document.getElementById('window').getBoundingClientRect(); return { x: b.x + scrollX, y: b.y + scrollY, width: b.width, height: b.height, scale: 1 }; })()`);
    const shot = await send('Page.captureScreenshot', { format: 'png', clip, captureBeyondViewport: true });
    const raw = join(profile, 'raw.png');
    writeFileSync(raw, Buffer.from(shot.data, 'base64'));
    execFileSync('sips', ['-z', String(OUT_H), String(OUT_W), raw, '--out', out], { stdio: 'ignore' });
    const rows = await run(`[...document.querySelectorAll('#apps .row')].map((r) => r.querySelector('b').textContent).join(', ')`);
    console.log(`${out}: ${rows}`);
  } finally {
    ws?.close();
    chrome.kill();
    await sleep(300);
    rmSync(profile, { recursive: true, force: true });
  }
}

for (const [page, file] of SHOTS) await shoot(page, join(here, file));
