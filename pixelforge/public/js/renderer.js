/**
 * PixelForge :: renderer.js
 * 32×32 animation renderer with multi-bit-depth display
 */

'use strict';

// ── State ──────────────────────────────────────────────────────────────────
const state = {
  animation:  null,    // loaded animation data from API
  frameIdx:   0,
  playing:    true,
  loop:       true,
  bitDepth:   24,
  zoom:       10,
  showGrid:   false,
  dither:     false,
  fps:        20,
  rafId:      null,
  lastTime:   0,
  hoveredPx:  null,
};

// ── DOM refs ───────────────────────────────────────────────────────────────
const canvas     = document.getElementById('main-canvas');
const ctx        = canvas.getContext('2d');
const zoomCanvas = document.getElementById('zoom-canvas');
const zoomCtx    = zoomCanvas.getContext('2d');

// ── Canvas resize ──────────────────────────────────────────────────────────
function resizeCanvas() {
  const z = state.zoom;
  canvas.width  = 32 * z;
  canvas.height = 32 * z;
}

// ── Render a single frame ──────────────────────────────────────────────────
function renderFrame(frameData) {
  if (!frameData) return;
  const { pixels, palette } = frameData;
  const z = state.zoom;

  resizeCanvas();
  const imgData = ctx.createImageData(32 * z, 32 * z);
  const d = imgData.data;

  for (let py = 0; py < 32; py++) {
    for (let px = 0; px < 32; px++) {
      const raw = pixels[py * 32 + px];
      let r, g, b;

      if (palette) {
        // indexed
        const entry = palette[raw] || [0, 0, 0];
        [r, g, b] = entry;
      } else if (state.bitDepth === 16) {
        // r5g6b5 unpack
        r = ((raw >> 11) & 0x1F) << 3;
        g = ((raw >> 5)  & 0x3F) << 2;
        b =  (raw        & 0x1F) << 3;
      } else {
        // 24-bit packed 0xRRGGBB
        r = (raw >> 16) & 0xFF;
        g = (raw >> 8)  & 0xFF;
        b =  raw        & 0xFF;
      }

      // Bayer ordered dithering for ≤ 4-bit
      if (state.dither && state.bitDepth <= 4) {
        const bayer = BAYER_4x4[py % 4][px % 4];
        const levels = (1 << state.bitDepth) - 1;
        r = Math.min(255, Math.round((r / 255 * levels + bayer) / levels * 255));
        g = Math.min(255, Math.round((g / 255 * levels + bayer) / levels * 255));
        b = Math.min(255, Math.round((b / 255 * levels + bayer) / levels * 255));
      }

      // Fill zoomed pixel block
      for (let dy = 0; dy < z; dy++) {
        for (let dx = 0; dx < z; dx++) {
          const i = ((py * z + dy) * 32 * z + (px * z + dx)) * 4;
          d[i]   = r;
          d[i+1] = g;
          d[i+2] = b;
          d[i+3] = 255;
        }
      }
    }
  }

  ctx.putImageData(imgData, 0, 0);

  // Grid overlay
  if (state.showGrid && z >= 4) {
    ctx.strokeStyle = 'rgba(57,255,20,0.15)';
    ctx.lineWidth = 0.5;
    for (let i = 0; i <= 32; i++) {
      ctx.beginPath();
      ctx.moveTo(i * z, 0); ctx.lineTo(i * z, 32 * z);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(0, i * z); ctx.lineTo(32 * z, i * z);
      ctx.stroke();
    }
  }
}

// ── Zoom canvas (8×8 magnified patch around cursor) ───────────────────────
function renderZoom(cx, cy) {
  if (!state.animation) return;
  const frame = state.animation.frames[state.frameIdx];
  if (!frame) return;

  const { pixels, palette } = frame;
  const Z = 4; // zoom-canvas cell size
  zoomCtx.fillStyle = '#020a02';
  zoomCtx.fillRect(0, 0, 128, 128);

  for (let dy = -4; dy < 4; dy++) {
    for (let dx = -4; dx < 4; dx++) {
      const px = Math.max(0, Math.min(31, cx + dx));
      const py = Math.max(0, Math.min(31, cy + dy));
      const raw = pixels[py * 32 + px];
      let r, g, b;

      if (palette) {
        const entry = palette[raw] || [0,0,0];
        [r, g, b] = entry;
      } else if (state.bitDepth === 16) {
        r = ((raw >> 11) & 0x1F) << 3;
        g = ((raw >> 5)  & 0x3F) << 2;
        b =  (raw        & 0x1F) << 3;
      } else {
        r = (raw >> 16) & 0xFF;
        g = (raw >> 8)  & 0xFF;
        b =  raw        & 0xFF;
      }

      const sx = (dx + 4) * Z * 4;
      const sy = (dy + 4) * Z * 4;
      zoomCtx.fillStyle = `rgb(${r},${g},${b})`;
      zoomCtx.fillRect(sx, sy, Z * 4, Z * 4);

      // cross-hair on center
      if (dx === 0 && dy === 0) {
        zoomCtx.strokeStyle = 'rgba(255,255,255,0.7)';
        zoomCtx.lineWidth = 1;
        zoomCtx.strokeRect(sx + 0.5, sy + 0.5, Z * 4 - 1, Z * 4 - 1);
      }
    }
  }
}

// ── Bayer 4×4 matrix for ordered dithering ────────────────────────────────
const BAYER_4x4 = [
  [ 0/16, 8/16, 2/16,10/16],
  [12/16, 4/16,14/16, 6/16],
  [ 3/16,11/16, 1/16, 9/16],
  [15/16, 7/16,13/16, 5/16]
];

// ── Animation loop ────────────────────────────────────────────────────────
function tick(ts) {
  state.rafId = requestAnimationFrame(tick);
  if (!state.animation || !state.playing) return;

  const interval = 1000 / state.fps;
  if (ts - state.lastTime < interval) return;
  state.lastTime = ts;

  renderFrame(state.animation.frames[state.frameIdx]);
  updateFrameBar();

  state.frameIdx++;
  if (state.frameIdx >= state.animation.frames.length) {
    if (state.loop) {
      state.frameIdx = 0;
    } else {
      state.frameIdx = state.animation.frames.length - 1;
      state.playing  = false;
      syncPlayBtn();
    }
  }
}

// ── API ───────────────────────────────────────────────────────────────────
async function loadAnimation(name, bitDepth) {
  document.getElementById('anim-info').textContent = `Loading ${name}…`;
  const url = `/api/animations/${name}?bit_depth=${bitDepth}`;
  const resp = await fetch(url);
  if (!resp.ok) { alert(`Failed to load: ${resp.statusText}`); return; }
  const data = await resp.json();

  // Normalise: store frames as [{pixels, palette}]
  state.animation = {
    name:    data.name,
    fps:     data.fps,
    frames:  data.frames,       // [{pixels, palette}]
    palette: data.palette,
  };

  state.fps      = data.fps;
  state.frameIdx = 0;

  document.getElementById('fps-display').textContent = data.fps;
  document.getElementById('speed-slider').value      = data.fps;
  document.getElementById('mode-label').textContent  = `${bitDepth}BPP`;
  document.getElementById('anim-info').textContent   =
    `${data.name.toUpperCase()}  ·  ${data.frames.length} frames  ·  ${data.fps} fps  ·  ${bitDepth}-bit`;

  renderPalette(data.palette);
  renderFrame(data.frames[0]);
  updateFrameBar();
}

// ── Palette display ───────────────────────────────────────────────────────
function renderPalette(palette) {
  const grid = document.getElementById('palette-grid');
  grid.innerHTML = '';
  if (!palette) {
    grid.innerHTML = '<span style="color:#4a7a4a;font-size:10px">True-color – no indexed palette</span>';
    return;
  }
  palette.forEach(([r, g, b], i) => {
    const sw = document.createElement('div');
    sw.className = 'pal-swatch';
    sw.style.background = `rgb(${r},${g},${b})`;
    sw.title = `[${i}] rgb(${r},${g},${b})`;
    grid.appendChild(sw);
  });
}

// ── Frame bar ─────────────────────────────────────────────────────────────
function updateFrameBar() {
  if (!state.animation) return;
  const total = state.animation.frames.length;
  const pct   = total > 1 ? (state.frameIdx / (total - 1)) * 100 : 0;
  document.getElementById('frame-thumb').style.width = pct + '%';
  document.getElementById('frame-counter').textContent =
    `${state.frameIdx + 1} / ${total}`;
}

// ── Sync play button ──────────────────────────────────────────────────────
function syncPlayBtn() {
  const btn = document.getElementById('btn-play');
  btn.textContent = state.playing ? '⏸ PAUSE' : '▶ PLAY';
  btn.classList.toggle('active', state.playing);
}

// ── Event wiring ──────────────────────────────────────────────────────────
document.getElementById('load-btn').addEventListener('click', () => {
  const name = document.getElementById('anim-select').value;
  loadAnimation(name, state.bitDepth);
});

document.querySelectorAll('.depth-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.depth-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    state.bitDepth = parseInt(btn.dataset.bits, 10);
    if (state.animation) {
      const name = document.getElementById('anim-select').value;
      loadAnimation(name, state.bitDepth);
    }
  });
});

document.getElementById('btn-play').addEventListener('click', () => {
  state.playing = !state.playing;
  syncPlayBtn();
});

document.getElementById('btn-loop').addEventListener('click', () => {
  state.loop = !state.loop;
  const btn = document.getElementById('btn-loop');
  btn.textContent = state.loop ? '↻' : '→';
  btn.classList.toggle('active', state.loop);
});

document.getElementById('btn-prev').addEventListener('click', () => {
  if (!state.animation) return;
  state.frameIdx = Math.max(0, state.frameIdx - 1);
  renderFrame(state.animation.frames[state.frameIdx]);
  updateFrameBar();
});

document.getElementById('btn-next').addEventListener('click', () => {
  if (!state.animation) return;
  state.frameIdx = Math.min(state.animation.frames.length - 1, state.frameIdx + 1);
  renderFrame(state.animation.frames[state.frameIdx]);
  updateFrameBar();
});

document.getElementById('speed-slider').addEventListener('input', e => {
  state.fps = parseInt(e.target.value, 10);
  document.getElementById('fps-display').textContent = state.fps;
});

document.getElementById('zoom-slider').addEventListener('input', e => {
  state.zoom = parseInt(e.target.value, 10);
  document.getElementById('zoom-display').textContent = state.zoom + '×';
  if (state.animation) renderFrame(state.animation.frames[state.frameIdx]);
});

document.getElementById('grid-toggle').addEventListener('click', () => {
  state.showGrid = !state.showGrid;
  const btn = document.getElementById('grid-toggle');
  btn.textContent  = state.showGrid ? 'GRID: ON' : 'GRID: OFF';
  btn.dataset.on   = state.showGrid;
  btn.classList.toggle('active', state.showGrid);
  if (state.animation) renderFrame(state.animation.frames[state.frameIdx]);
});

document.getElementById('dither-toggle').addEventListener('click', () => {
  state.dither = !state.dither;
  const btn = document.getElementById('dither-toggle');
  btn.textContent = state.dither ? 'DITHER: ON' : 'DITHER: OFF';
  btn.dataset.on  = state.dither;
  btn.classList.toggle('active', state.dither);
  if (state.animation) {
    const name = document.getElementById('anim-select').value;
    loadAnimation(name, state.bitDepth);
  }
});

// ── Frame track click ─────────────────────────────────────────────────────
document.getElementById('frame-track').addEventListener('click', e => {
  if (!state.animation) return;
  const rect = e.currentTarget.getBoundingClientRect();
  const pct  = (e.clientX - rect.left) / rect.width;
  state.frameIdx = Math.round(pct * (state.animation.frames.length - 1));
  renderFrame(state.animation.frames[state.frameIdx]);
  updateFrameBar();
});

// ── Canvas hover ──────────────────────────────────────────────────────────
canvas.addEventListener('mousemove', e => {
  if (!state.animation) return;
  const rect = canvas.getBoundingClientRect();
  const z    = state.zoom;
  const px   = Math.floor((e.clientX - rect.left) / z);
  const py   = Math.floor((e.clientY - rect.top) / z);

  if (px < 0 || px > 31 || py < 0 || py > 31) return;

  const frame  = state.animation.frames[state.frameIdx];
  const raw    = frame.pixels[py * 32 + px];
  let r, g, b;

  if (frame.palette) {
    [r, g, b] = frame.palette[raw] || [0,0,0];
  } else if (state.bitDepth === 16) {
    r = ((raw >> 11) & 0x1F) << 3;
    g = ((raw >> 5)  & 0x3F) << 2;
    b =  (raw        & 0x1F) << 3;
  } else {
    r = (raw >> 16) & 0xFF;
    g = (raw >>  8) & 0xFF;
    b =  raw        & 0xFF;
  }

  document.getElementById('cursor-xy').textContent  = `${px.toString().padStart(2,'0')},${py.toString().padStart(2,'0')}`;
  document.getElementById('cursor-rgb').textContent = `${r},${g},${b}`;
  document.getElementById('cursor-hex').textContent =
    '#' + [r,g,b].map(v => v.toString(16).padStart(2,'0')).join('');

  renderZoom(px, py);
});

canvas.addEventListener('mouseleave', () => {
  document.getElementById('cursor-xy').textContent  = '--,--';
  document.getElementById('cursor-rgb').textContent = '---,---,---';
  document.getElementById('cursor-hex').textContent = '#------';
});

// ── Export ────────────────────────────────────────────────────────────────
document.getElementById('export-png').addEventListener('click', () => {
  const link     = document.createElement('a');
  link.download  = `pixelforge_frame_${state.frameIdx}.png`;
  link.href      = canvas.toDataURL('image/png');
  link.click();
});

document.getElementById('export-json').addEventListener('click', () => {
  if (!state.animation) return;
  const blob = new Blob([JSON.stringify(state.animation, null, 2)], {type: 'application/json'});
  const link = document.createElement('a');
  link.download = `${state.animation.name}_${state.bitDepth}bpp.json`;
  link.href     = URL.createObjectURL(blob);
  link.click();
});

// ── Keyboard shortcuts ────────────────────────────────────────────────────
document.addEventListener('keydown', e => {
  if (!state.animation) return;
  if (e.key === ' ') { e.preventDefault(); document.getElementById('btn-play').click(); }
  if (e.key === 'ArrowLeft')  document.getElementById('btn-prev').click();
  if (e.key === 'ArrowRight') document.getElementById('btn-next').click();
  if (e.key === 'g') document.getElementById('grid-toggle').click();
  if (e.key === 'd') document.getElementById('dither-toggle').click();
  if (e.key === 'l') document.getElementById('btn-loop').click();
  if (e.key === '+' || e.key === '=') {
    const s = document.getElementById('zoom-slider');
    s.value = Math.min(20, +s.value + 1);
    s.dispatchEvent(new Event('input'));
  }
  if (e.key === '-') {
    const s = document.getElementById('zoom-slider');
    s.value = Math.max(1, +s.value - 1);
    s.dispatchEvent(new Event('input'));
  }
});

// ── Boot ──────────────────────────────────────────────────────────────────
requestAnimationFrame(tick);
// Auto-load first animation
document.getElementById('load-btn').click();
