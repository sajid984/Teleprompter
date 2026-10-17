// The remote-control web page served to a Mac / iPhone browser on the same Wi-Fi.
// Self-contained: no external scripts, fonts or images, so it works without internet.
enum RemotePage {
    static let html = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Prompter Remote">
<meta name="theme-color" content="#0e0f12">
<title>Teleprompter Remote</title>
<style>
  :root { --bg:#0e0f12; --card:#181a1f; --raise:#23262d; --line:#2c3038; --text:#f2f3f5; --dim:#9aa0aa; --accent:#ff5a36; --ok:#34c759; --warn:#ffcc00; }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { background: var(--bg); }
  body { margin: 0; color: var(--text); font: 16px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         padding: calc(8px + env(safe-area-inset-top)) 16px calc(24px + env(safe-area-inset-bottom)); }
  main { max-width: 760px; margin: 0 auto; }
  header { display: flex; align-items: center; gap: 10px; padding: 10px 0 4px; }
  header h1 { font-size: 17px; margin: 0; flex: 1; font-weight: 650; }
  .dot { width: 10px; height: 10px; border-radius: 50%; background: #555; flex: none; }
  .dot.on { background: var(--ok); }
  .dot.off { background: var(--accent); }
  .muted { color: var(--dim); font-size: 14px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 20px; padding: 16px; margin: 12px 0; }
  .title { font-size: 21px; font-weight: 700; overflow-wrap: anywhere; }
  .progress { height: 8px; background: var(--line); border-radius: 4px; overflow: hidden; margin: 14px 0 6px; }
  .progress > div { height: 100%; width: 0; background: var(--accent); transition: width .4s linear; }
  .times { display: flex; justify-content: space-between; color: var(--dim); font-size: 14px; font-variant-numeric: tabular-nums; }
  button { font: inherit; font-weight: 600; color: var(--text); background: var(--raise); border: 1px solid var(--line);
           border-radius: 14px; min-height: 52px; min-width: 52px; padding: 0 16px; cursor: pointer; touch-action: manipulation; user-select: none; -webkit-user-select: none; }
  button:active { transform: scale(.96); filter: brightness(1.25); }
  button:disabled { opacity: .35; cursor: default; transform: none; }
  button svg { width: 24px; height: 24px; fill: currentColor; vertical-align: middle; }
  .transport { display: flex; justify-content: center; align-items: center; gap: 12px; margin: 18px 0 10px; flex-wrap: wrap; }
  .play { width: 96px; height: 96px; border-radius: 50%; background: var(--accent); border: none; }
  .play svg { width: 40px; height: 40px; }
  .row { display: flex; align-items: center; gap: 10px; margin: 8px 0; }
  .row.center { justify-content: center; }
  .label { width: 92px; color: var(--dim); flex: none; }
  .value { min-width: 56px; text-align: center; font-size: 22px; font-weight: 700; font-variant-numeric: tabular-nums; }
  input[type=range] { flex: 1; accent-color: var(--accent); height: 36px; min-width: 0; }
  .toggle.on { background: var(--accent); border-color: var(--accent); }
  .grow { flex: 1; }
  .scripts { display: grid; gap: 8px; margin-top: 10px; }
  .scripts button { display: flex; justify-content: space-between; align-items: center; gap: 12px; text-align: left; min-height: 56px; font-weight: 500; }
  .scripts button.current { border-color: var(--accent); }
  .scripts .words { color: var(--dim); font-size: 13px; white-space: nowrap; }
  input[type=text], textarea, .pin { width: 100%; background: #0b0c0f; color: var(--text); border: 1px solid var(--line); border-radius: 12px; padding: 12px; font: inherit; }
  textarea { min-height: 180px; resize: vertical; margin-top: 8px; }
  .check { display: flex; align-items: center; gap: 8px; margin-top: 10px; }
  .overlay { position: fixed; inset: 0; background: rgba(5,6,8,.92); display: none; align-items: center; justify-content: center; padding: 24px; z-index: 10; }
  .overlay.show { display: flex; }
  .overlay .box { max-width: 380px; text-align: center; }
  .pin { text-align: center; font-size: 34px; letter-spacing: 10px; font-variant-numeric: tabular-nums; margin-top: 12px; }
  .toast { position: fixed; left: 50%; bottom: calc(20px + env(safe-area-inset-bottom)); transform: translateX(-50%); background: #2b2f37;
           border: 1px solid var(--line); padding: 10px 18px; border-radius: 999px; opacity: 0; transition: opacity .2s; pointer-events: none; z-index: 20; max-width: 90vw; text-align: center; }
  .toast.show { opacity: 1; }
  .keys { text-align: center; color: var(--dim); font-size: 13px; margin-top: 18px; }
  .badge { font-size: 12px; font-weight: 700; padding: 3px 8px; border-radius: 999px; background: var(--raise); color: var(--dim); }
  .badge.live { background: var(--accent); color: #fff; }
  /* Live preview of the iPad text */
  .pvwrap { display: flex; justify-content: center; margin: 14px 0 6px; }
  .pv { position: relative; overflow: hidden; border-radius: 14px; background: #000; border: 1px solid var(--line); }
  .pv .scroller { position: absolute; inset: 0; overflow-y: auto; overflow-x: hidden; scrollbar-width: none; overscroll-behavior: contain; }
  .pv .scroller::-webkit-scrollbar { display: none; }
  .pv .ptext { white-space: pre-wrap; overflow-wrap: break-word; }
  .pv .ptext > div { margin-bottom: var(--pspace, 0); }
  .pv .marker { position: absolute; left: 0; right: 0; height: 2px; pointer-events: none; }
  .pv .marker::before, .pv .marker::after { content: ""; position: absolute; top: 50%; transform: translateY(-50%); border: 8px solid transparent; }
  .pv .marker::before { left: 0; border-left: 11px solid var(--mk, var(--accent)); }
  .pv .marker::after { right: 0; border-right: 11px solid var(--mk, var(--accent)); }
  .pv .empty { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; color: var(--dim); font-size: 14px; text-align: center; padding: 16px; }
  #mini { cursor: pointer; }
  #mini .scroller { overflow: hidden; pointer-events: none; }
  .pvhint { text-align: center; color: var(--dim); font-size: 13px; margin-bottom: 4px; }
  .live { position: fixed; inset: 0; z-index: 8; background: #000; display: none; flex-direction: column; }
  .live.show { display: flex; }
  .livebar { display: flex; align-items: center; gap: 10px; padding: 10px 14px; background: var(--card); }
  .livebar.top { padding-top: calc(10px + env(safe-area-inset-top)); border-bottom: 1px solid var(--line); }
  .livebar.bottom { padding-bottom: calc(10px + env(safe-area-inset-bottom)); border-top: 1px solid var(--line); justify-content: center; flex-wrap: wrap; }
  .livebar .play { width: 64px; height: 64px; }
  .livebar .play svg { width: 30px; height: 30px; }
  .livetitle { flex: 1; font-weight: 700; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .livebody { flex: 1; min-height: 0; display: flex; justify-content: center; }
  #big { width: 100%; max-width: 1000px; height: 100%; border: none; border-radius: 0; user-select: none; -webkit-user-select: none; }
  #big .scroller { cursor: grab; touch-action: pan-y; }
  /* Phones: play button on its own row, slimmer controls. */
  @media (max-width: 480px) {
    body { padding-left: 12px; padding-right: 12px; }
    .card { padding: 14px; }
    .transport { display: grid; grid-template-columns: repeat(4, auto); justify-content: center; gap: 10px; }
    .transport .play { grid-column: 1 / -1; justify-self: center; order: -1; width: 88px; height: 88px; }
    .row { gap: 8px; }
    .label { width: 64px; font-size: 15px; }
    .row button { min-width: 46px; padding: 0 10px; }
    .value { min-width: 40px; font-size: 20px; }
  }
</style>
</head>
<body>
<main>
  <header>
    <span id="dot" class="dot"></span>
    <h1>Teleprompter Remote</h1>
    <span id="conn" class="muted">Connecting…</span>
  </header>

  <section class="card">
    <div class="row" style="margin:0">
      <div id="title" class="title grow">No script open</div>
      <span id="badge" class="badge">Stopped</span>
    </div>
    <div id="sub" class="muted">Pick a script below to open it on the iPad.</div>
    <div class="pvwrap">
      <div id="mini" class="pv" title="Click to scroll the script live">
        <div class="scroller"><div class="ptext"></div></div>
        <div class="marker"></div>
        <div class="empty">Open a script to see a live preview of the iPad here.</div>
      </div>
    </div>
    <div class="pvhint">Click the preview to scroll the script live</div>
    <div class="progress"><div id="bar"></div></div>
    <div class="times"><span id="elapsed">0:00</span><span id="remaining">-0:00</span></div>
    <div class="transport">
      <button class="needs" data-cmd="top" title="Back to top (Home)" aria-label="Back to top"><svg viewBox="0 0 24 24"><path d="M6 5h2v14H6zM20 5v14L9 12z"/></svg></button>
      <button class="needs" data-cmd="back" title="Jump back (Page Up)" aria-label="Jump back"><svg viewBox="0 0 24 24"><path d="M12 5v14L2 12zM22 5v14l-10-7z"/></svg></button>
      <button id="play" class="play needs" data-cmd="toggle" title="Play / Pause (Space)" aria-label="Play or pause"></button>
      <button class="needs" data-cmd="forward" title="Jump forward (Page Down)" aria-label="Jump forward"><svg viewBox="0 0 24 24"><path d="M12 5v14l10-7zM2 5v14l10-7z"/></svg></button>
      <button class="needs" data-cmd="close" title="Close the prompter (Esc)" aria-label="Close prompter"><svg viewBox="0 0 24 24"><path d="M6.4 5 12 10.6 17.6 5 19 6.4 13.4 12l5.6 5.6-1.4 1.4-5.6-5.6L6.4 19 5 17.6 10.6 12 5 6.4z"/></svg></button>
    </div>
    <div class="row center">
      <button class="needs" data-cmd="lineBack" title="Up one line (↑)">▲&#xFE0E; Line</button>
      <button class="needs" data-cmd="lineForward" title="Down one line (↓)">▼&#xFE0E; Line</button>
    </div>
  </section>

  <section class="card">
    <div class="row">
      <span class="label">Speed</span>
      <button data-cmd="speedDown" title="Slower (←)" aria-label="Slower">−</button>
      <span id="speed" class="value">–</span>
      <button data-cmd="speedUp" title="Faster (→)" aria-label="Faster">+</button>
    </div>
    <div class="row"><input id="speedSlider" type="range" min="1" max="100" step="1" aria-label="Speed"></div>
    <div class="row">
      <span class="label">Text size</span>
      <button data-cmd="fontDown" title="Smaller text (−)">A−</button>
      <span id="font" class="value">–</span>
      <button data-cmd="fontUp" title="Bigger text (=)">A+</button>
    </div>
    <div class="row">
      <span class="label">Mirror</span>
      <button id="mirror" class="toggle" data-cmd="mirror" title="Mirror (M)">Off</button>
    </div>
  </section>

  <section class="card">
    <div class="row" style="margin:0; justify-content:space-between">
      <strong>Scripts on the iPad</strong>
      <button id="refresh" style="min-height:40px">Refresh</button>
    </div>
    <div id="scripts" class="scripts"><span class="muted">Loading…</span></div>
  </section>

  <section class="card">
    <strong>Send a script to the iPad</strong>
    <div class="muted" style="margin:4px 0 10px">Paste text here and it is saved on the iPad as a new script.</div>
    <input id="newTitle" type="text" placeholder="Title (optional)" autocomplete="off">
    <textarea id="newBody" placeholder="Paste your script here…"></textarea>
    <label class="check muted"><input id="newClean" type="checkbox" checked> Remove extra blank lines and spaces</label>
    <div class="row" style="margin-top:12px; flex-wrap:wrap">
      <button id="send">Send to iPad</button>
      <button id="sendOpen">Send and open</button>
    </div>
  </section>

  <div class="keys">Keyboard: Space play / pause · ← → speed · ↑ ↓ one line · Page Up / Down jump · Home top · − = text size · M mirror · Esc close</div>
</main>

<div id="live" class="live">
  <div class="livebar top">
    <button id="liveClose" style="min-height:44px">Back</button>
    <span id="liveTitle" class="livetitle"></span>
    <span id="liveTime" class="muted"></span>
  </div>
  <div class="livebody">
    <div id="big" class="pv">
      <div class="scroller"><div class="ptext"></div></div>
      <div class="marker"></div>
      <div class="empty">Open a script to scroll it here.</div>
    </div>
  </div>
  <div class="livebar bottom">
    <button class="needs" data-cmd="top" title="Back to top" aria-label="Back to top"><svg viewBox="0 0 24 24"><path d="M6 5h2v14H6zM20 5v14L9 12z"/></svg></button>
    <button class="needs" data-cmd="back" title="Jump back" aria-label="Jump back"><svg viewBox="0 0 24 24"><path d="M12 5v14L2 12zM22 5v14l-10-7z"/></svg></button>
    <button id="play2" class="play needs" data-cmd="toggle" title="Play / Pause (Space)" aria-label="Play or pause"></button>
    <button class="needs" data-cmd="forward" title="Jump forward" aria-label="Jump forward"><svg viewBox="0 0 24 24"><path d="M12 5v14l10-7zM2 5v14l10-7z"/></svg></button>
    <button data-cmd="speedDown" title="Slower (←)" aria-label="Slower">−</button>
    <span id="speed2" class="value">–</span>
    <button data-cmd="speedUp" title="Faster (→)" aria-label="Faster">+</button>
  </div>
</div>

<div id="pinOverlay" class="overlay">
  <div class="box">
    <h2 style="margin:0 0 6px">Enter the iPad's code</h2>
    <div class="muted">On the iPad: Scripts list → Remote button (the waves icon). The 6-digit code is shown there.</div>
    <input id="pin" class="pin" inputmode="numeric" pattern="[0-9]*" maxlength="6" autocomplete="one-time-code">
    <div style="margin-top:14px"><button id="pinGo" style="width:100%">Connect</button></div>
    <div id="pinMsg" class="muted" style="margin-top:10px; min-height:20px"></div>
  </div>
</div>
<div id="toast" class="toast"></div>

<script>
(() => {
  const $ = id => document.getElementById(id);
  const PLAY = '<svg viewBox="0 0 24 24"><path d="M7 4.5v15l13-7.5z"/></svg>';
  const PAUSE = '<svg viewBox="0 0 24 24"><path d="M6 4h4.5v16H6zM13.5 4H18v16h-4.5z"/></svg>';
  let code = '';
  let scriptsRevision = null;
  let currentId = null;
  let sliderActive = false;
  let needCode = false;
  let toastTimer = null;

  try {
    const match = location.hash.match(/code=(\d{6})/);
    if (match) {
      code = match[1];
      localStorage.setItem('prompterRemoteCode', code);
      history.replaceState(null, '', location.pathname);
    } else {
      code = localStorage.getItem('prompterRemoteCode') || '';
    }
  } catch (e) {}

  function toast(text) {
    const t = $('toast');
    t.textContent = text;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 2200);
  }

  function fmt(total) {
    total = Math.max(0, Math.round(total || 0));
    const h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60;
    return (h ? h + ':' + String(m).padStart(2, '0') : m) + ':' + String(s).padStart(2, '0');
  }

  function askForCode(message) {
    needCode = true;
    $('pinMsg').textContent = message || '';
    $('pinOverlay').classList.add('show');
    setTimeout(() => $('pin').focus(), 50);
  }

  async function api(path, body) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 5000);
    const options = { method: body === undefined ? 'GET' : 'POST', headers: { 'X-Remote-Code': code }, signal: controller.signal, cache: 'no-store' };
    if (body !== undefined) {
      options.headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(body);
    }
    try {
      const response = await fetch(path, options);
      const data = await response.json().catch(() => ({}));
      if (response.status === 401) {
        askForCode(code ? 'That code did not work. Check the iPad.' : '');
        const err = new Error('auth'); err.status = 401; throw err;
      }
      if (!response.ok) {
        const err = new Error(data.error || ('Error ' + response.status)); err.status = response.status; throw err;
      }
      return data;
    } finally {
      clearTimeout(timer);
    }
  }

  function setConnected(on) {
    $('dot').className = 'dot ' + (on ? 'on' : 'off');
    $('conn').textContent = on ? 'Connected' : 'Not connected';
  }

  function render(s) {
    lastState = s;
    currentId = s.scriptId;
    $('title').textContent = s.prompterOpen ? (s.title || 'Script') : 'No script open';
    $('sub').textContent = s.prompterOpen
      ? (s.countdown ? 'Starting in ' + s.countdown + '…' : s.reachedEnd ? 'End of script' : 'Open on the iPad')
      : 'Pick a script below to open it on the iPad.';
    const badge = $('badge');
    badge.textContent = s.countdown ? String(s.countdown) : s.playing ? 'Playing' : s.prompterOpen ? 'Paused' : 'Stopped';
    badge.className = 'badge' + (s.playing || s.countdown ? ' live' : '');
    $('bar').style.width = (s.progress * 100).toFixed(2) + '%';
    $('elapsed').textContent = fmt(s.elapsed);
    $('remaining').textContent = '-' + fmt(s.remaining);
    $('play').innerHTML = (s.playing || s.countdown) ? PAUSE : PLAY;
    $('play2').innerHTML = $('play').innerHTML;
    $('speed').textContent = s.speed;
    $('speed2').textContent = s.speed;
    $('liveTitle').textContent = s.title || '';
    $('liveTime').textContent = fmt(s.elapsed) + '  -' + fmt(s.remaining);
    if (!sliderActive) $('speedSlider').value = s.speed;
    $('font').textContent = s.fontSize;
    const mirror = $('mirror');
    mirror.textContent = s.mirror ? 'On' : 'Off';
    mirror.classList.toggle('on', s.mirror);
    document.querySelectorAll('.needs').forEach(b => b.disabled = !s.prompterOpen);
    document.querySelectorAll('.scripts button').forEach(b => b.classList.toggle('current', b.dataset.id === currentId));
    updatePreviews(s);
    if (s.scriptsRevision !== scriptsRevision) {
      scriptsRevision = s.scriptsRevision;
      loadScripts();
    }
  }

  async function loadScripts() {
    try {
      const list = await api('/api/scripts');
      const box = $('scripts');
      box.innerHTML = '';
      if (!list.length) { box.innerHTML = '<span class="muted">No scripts yet.</span>'; return; }
      for (const item of list) {
        const b = document.createElement('button');
        b.dataset.id = item.id;
        if (item.id === currentId) b.classList.add('current');
        const name = document.createElement('span');
        name.textContent = item.title;
        const words = document.createElement('span');
        words.className = 'words';
        words.textContent = item.words + ' words · Open';
        b.append(name, words);
        b.addEventListener('click', async () => {
          b.blur();
          try { render(await api('/api/start', { id: item.id })); toast('Opened on the iPad'); }
          catch (e) { if (e.status !== 401) toast(e.message); }
        });
        box.append(b);
      }
    } catch (e) { /* shown by the connection dot */ }
  }

  async function poll() {
    if (!needCode) {
      try {
        render(await api('/api/state'));
        setConnected(true);
      } catch (e) {
        if (e.status !== 401) setConnected(false);
      }
    }
    setTimeout(poll, document.hidden ? 2000 : 250);
  }

  async function send(action, value) {
    try {
      render(await api('/api/command', value === undefined ? { action } : { action, value }));
    } catch (e) {
      if (e.status !== 401) toast(e.status ? e.message : 'Cannot reach the iPad. Is the app open?');
    }
  }

  document.querySelectorAll('[data-cmd]').forEach(b => b.addEventListener('click', () => { b.blur(); send(b.dataset.cmd); }));

  const slider = $('speedSlider');
  slider.addEventListener('input', () => { sliderActive = true; $('speed').textContent = slider.value; });
  slider.addEventListener('change', () => { sliderActive = false; send('setSpeed', Number(slider.value)); });

  $('refresh').addEventListener('click', () => { $('refresh').blur(); loadScripts(); });

  async function sendScript(open) {
    const body = $('newBody').value;
    if (!body.trim()) { toast('Paste a script first'); return; }
    try {
      await api('/api/scripts', { title: $('newTitle').value, body, clean: $('newClean').checked, open });
      $('newTitle').value = '';
      $('newBody').value = '';
      toast(open ? 'Sent and opened on the iPad' : 'Saved on the iPad');
      scriptsRevision = null;
    } catch (e) { if (e.status !== 401) toast(e.message); }
  }
  $('send').addEventListener('click', () => sendScript(false));
  $('sendOpen').addEventListener('click', () => sendScript(true));

  async function connectWithPin() {
    const value = $('pin').value.replace(/\D/g, '');
    if (value.length !== 6) { $('pinMsg').textContent = 'The code has 6 digits.'; return; }
    code = value;
    try { localStorage.setItem('prompterRemoteCode', code); } catch (e) {}
    needCode = false;
    try {
      render(await api('/api/state'));
      setConnected(true);
      $('pinOverlay').classList.remove('show');
      $('pin').value = '';
      toast('Connected');
    } catch (e) {
      if (e.status !== 401) { needCode = true; $('pinMsg').textContent = e.message; }
    }
  }
  $('pinGo').addEventListener('click', connectWithPin);
  $('pin').addEventListener('keydown', e => { if (e.key === 'Enter') connectWithPin(); });

  const keys = { ' ': 'toggle', 'Enter': 'toggle', 'ArrowLeft': 'speedDown', 'ArrowRight': 'speedUp',
                 'ArrowUp': 'lineBack', 'ArrowDown': 'lineForward', 'PageUp': 'back', 'PageDown': 'forward',
                 'Home': 'top', '-': 'fontDown', '=': 'fontUp', '+': 'fontUp', 'm': 'mirror', 'M': 'mirror', 'Escape': 'close' };
  document.addEventListener('keydown', e => {
    if (needCode || e.metaKey || e.ctrlKey || e.altKey || e.target.closest('input, textarea')) return;
    if (e.key === 'Escape' && liveOpen) { e.preventDefault(); closeLive(); return; }
    const action = keys[e.key];
    if (action) { e.preventDefault(); send(action); }
  });

  // ---------- Live preview of the iPad text ----------
  // The iPad sends the exact text and style; the page lays it out at a scaled size and follows the
  // character that sits on the iPad's reading guide, so wrapping differences never matter.
  class Preview {
    constructor(root, interactive) {
      this.root = root;
      this.interactive = interactive;
      this.scroller = root.querySelector('.scroller');
      this.text = root.querySelector('.ptext');
      this.marker = root.querySelector('.marker');
      this.empty = root.querySelector('.empty');
      this.data = null; this.lineStarts = [];
      this.pos = null; this.lastSet = -1; this.userUntil = 0;
      this.base = null; this.baseAt = 0; this.speed = 0; this.playing = false;
      this.scale = 1; this.pitch = 20; this.markerY = 0;
      if (interactive) this.scroller.addEventListener('scroll', () => this.onScroll(), { passive: true });
      this.clear();
    }
    clear() {
      this.data = null; this.base = null; this.pos = null;
      this.text.replaceChildren();
      this.empty.style.display = '';
      this.marker.style.display = 'none';
      this.root.style.background = '';
    }
    build(d) {
      this.data = d; this.lineStarts = [];
      const frag = document.createDocumentFragment();
      let offset = 0;
      for (const line of d.text.split('\n')) {
        const div = document.createElement('div');
        div.textContent = line.length ? line : '​';
        div.dataset.start = offset;
        div.dataset.len = line.length;
        this.lineStarts.push(offset);
        offset += line.length + 1;
        frag.append(div);
      }
      this.text.replaceChildren(frag);
      const t = this.text.style;
      this.root.style.background = d.backgroundColor;
      t.color = d.textColor; t.fontFamily = d.font; t.fontWeight = d.weight; t.textAlign = d.alignment; t.lineHeight = d.lineHeight;
      this.marker.style.background = d.textColor.replace('rgb(', 'rgba(').replace(')', ', 0.35)');
      this.marker.style.setProperty('--mk', d.markerColor);
      this.marker.style.display = '';
      this.empty.style.display = 'none';
      this.layout();
    }
    layout() {
      const d = this.data;
      const w = this.scroller.clientWidth, h = this.scroller.clientHeight;
      if (!d || !w || !h) return false;
      this.scale = w / d.viewWidth;
      const fs = d.fontSize * this.scale;
      this.pitch = fs * d.lineHeight;
      this.markerY = Math.round(h * d.markerPosition);
      const t = this.text.style;
      t.fontSize = fs + 'px';
      t.paddingLeft = t.paddingRight = (w * d.marginPercent) + 'px';
      t.paddingTop = Math.max(0, this.markerY - this.pitch / 2) + 'px';
      t.paddingBottom = (h - this.markerY + this.pitch) + 'px';
      t.setProperty('--pspace', (d.paragraphSpacing * fs) + 'px');
      this.marker.style.top = (this.markerY - 1) + 'px';
      this.pos = null;
      return true;
    }
    lineIndex(ci) {
      let lo = 0, hi = this.lineStarts.length - 1;
      while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (this.lineStarts[mid] <= ci) lo = mid; else hi = mid - 1; }
      return lo;
    }
    originTop() { return this.scroller.getBoundingClientRect().top - this.scroller.scrollTop; }
    // Vertical centre (in scroll-content coordinates) of the line holding character `ci`.
    centerOf(ci) {
      const i = this.lineIndex(ci);
      const div = this.text.children[i];
      if (!div) return 0;
      const origin = this.originTop();
      const len = Number(div.dataset.len), node = div.firstChild;
      if (len > 0 && node) {
        const at = Math.min(Math.max(ci - this.lineStarts[i], 0), len - 1);
        const range = document.createRange();
        range.setStart(node, at); range.setEnd(node, at + 1);
        const rect = range.getClientRects()[0];
        if (rect && rect.height) return (rect.top + rect.bottom) / 2 - origin;
      }
      return div.getBoundingClientRect().top - origin + this.pitch / 2;
    }
    lineAt(contentY) {
      const kids = this.text.children, origin = this.originTop();
      let lo = 0, hi = kids.length - 1;
      while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (kids[mid].getBoundingClientRect().top - origin <= contentY) lo = mid; else hi = mid - 1; }
      return kids[lo] || null;
    }
    setBase(s) {
      if (!this.data || s.anchor == null || !this.scroller.clientHeight) return;
      this.base = this.centerOf(s.anchor) + (s.anchorDelta || 0) * this.pitch - this.markerY;
      this.baseAt = performance.now();
      this.speed = (s.pointsPerSecond || 0) * this.scale;
      this.playing = !!s.playing && !s.countdown;
    }
    setScroll(v) { this.pos = v; this.scroller.scrollTop = v; this.lastSet = this.scroller.scrollTop; }
    // Glide toward the iPad's position, predicting motion between status updates.
    follow(now, dt) {
      if (this.base === null || !this.scroller.clientHeight) return;
      if (now < this.userUntil) { this.pos = null; return; }
      if (this.pos === null) this.pos = this.scroller.scrollTop;
      const target = this.base + (this.playing ? (now - this.baseAt) / 1000 * this.speed : 0);
      const diff = target - this.pos;
      if (Math.abs(diff) < 0.2) return;
      this.setScroll(Math.abs(diff) > this.scroller.clientHeight ? target : this.pos + diff * Math.min(1, dt * 10));
    }
    onScroll() {
      if (Math.abs(this.scroller.scrollTop - this.lastSet) < 2) return;   // our own follow movement
      this.userUntil = performance.now() + 800;
      scheduleSeek(this);
    }
    // Which character is on the reading guide right now, and how far past its line centre (in lines).
    anchorAtMarker() {
      if (!this.data) return null;
      const r = this.scroller.getBoundingClientRect();
      const x = r.left + this.scroller.clientWidth * this.data.marginPercent + 2;
      const y = r.top + this.markerY;
      let node = null, off = 0;
      if (document.caretPositionFromPoint) {
        const c = document.caretPositionFromPoint(x, y);
        if (c) { node = c.offsetNode; off = c.offset; }
      } else if (document.caretRangeFromPoint) {
        const c = document.caretRangeFromPoint(x, y);
        if (c) { node = c.startContainer; off = c.startOffset; }
      }
      let div = node ? (node.nodeType === 3 ? node.parentElement : node) : null;
      if (!div || div.parentElement !== this.text) {
        div = this.lineAt(this.scroller.scrollTop + this.markerY);
        off = 0;
      }
      if (!div) return null;
      const index = Number(div.dataset.start) + Math.min(off, Number(div.dataset.len));
      const delta = (this.scroller.scrollTop + this.markerY - this.centerOf(index)) / this.pitch;
      return { index, delta };
    }
  }

  const mini = new Preview($('mini'), false);
  const big = new Preview($('big'), true);
  let lastState = null, previewRevision = null, loadingPreview = false, liveOpen = false;
  let seekTimer = null, seekSource = null;

  function scheduleSeek(preview) {
    seekSource = preview;
    if (seekTimer) return;
    seekTimer = setTimeout(() => {
      seekTimer = null;
      const a = seekSource && seekSource.anchorAtMarker();
      if (a) api('/api/command', { action: 'seek', value: a.index, delta: a.delta }).then(render).catch(() => {});
    }, 60);
  }

  function sizeMini() {
    const wrap = $('mini').parentElement;
    const d = mini.data;
    const aspect = d ? d.viewWidth / d.viewHeight : 1.44;
    let w = Math.min(wrap.clientWidth, 520), h = w / aspect;
    if (h > 260) { h = 260; w = h * aspect; }
    $('mini').style.width = w + 'px';
    $('mini').style.height = h + 'px';
    mini.layout();
  }

  async function loadPreview(revision) {
    if (loadingPreview) return;
    loadingPreview = true;
    try {
      const d = await api('/api/preview');
      previewRevision = revision;
      mini.build(d); sizeMini();
      big.build(d);
      if (lastState) { mini.setBase(lastState); big.setBase(lastState); }
    } catch (e) {
      previewRevision = null;
    } finally {
      loadingPreview = false;
    }
  }

  function updatePreviews(s) {
    if (s.prompterOpen) {
      if (s.previewRevision !== previewRevision) loadPreview(s.previewRevision);
    } else if (previewRevision !== null || mini.data) {
      previewRevision = null;
      mini.clear(); big.clear(); sizeMini();
      if (liveOpen) closeLive();
    }
    mini.setBase(s);
    big.setBase(s);
  }

  function openLive() {
    if (!lastState || !lastState.prompterOpen) { toast('Open a script on the iPad first'); return; }
    liveOpen = true;
    $('live').classList.add('show');
    document.body.style.overflow = 'hidden';
    big.layout();
    big.setBase(lastState);
    if (big.base !== null) big.setScroll(big.base);
  }

  function closeLive() {
    liveOpen = false;
    $('live').classList.remove('show');
    document.body.style.overflow = '';
  }

  $('mini').addEventListener('click', openLive);
  $('liveClose').addEventListener('click', closeLive);

  // Mouse: drag the text to scroll (touch and trackpads scroll natively). A click without dragging plays / pauses.
  (() => {
    const el = big.scroller;
    let drag = null, dragged = false;
    el.addEventListener('pointerdown', e => {
      if (e.pointerType !== 'mouse' || e.button !== 0) return;
      drag = { y: e.clientY, top: el.scrollTop };
      dragged = false;
      el.setPointerCapture(e.pointerId);
    });
    el.addEventListener('pointermove', e => {
      if (!drag) return;
      const dy = e.clientY - drag.y;
      if (Math.abs(dy) > 4) dragged = true;
      if (dragged) el.scrollTop = drag.top - dy;
    });
    const end = () => { drag = null; };
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
    el.addEventListener('click', () => {
      if (dragged) { dragged = false; return; }
      send('toggle');
    });
  })();

  window.addEventListener('resize', () => {
    sizeMini();
    big.layout();
    if (lastState) { mini.setBase(lastState); big.setBase(lastState); }
  });

  let lastFrame = performance.now();
  function frame(now) {
    const dt = Math.min(0.1, Math.max(0, (now - lastFrame) / 1000));
    lastFrame = now;
    mini.follow(now, dt);
    if (liveOpen) big.follow(now, dt);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  if (!code) askForCode('');
  sizeMini();
  poll();
})();
</script>
</body>
</html>
"""#
}
