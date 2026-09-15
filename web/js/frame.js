(() => {
  const cutout = document.getElementById('screen-cutout');
  const root = document.documentElement;

  // ---------------------------------------------------------------------
  // User-adjustable X/Y scale - a personal display preference (not tied
  // to any dealership), saved in this client's own localStorage so it's
  // remembered next time. Multiplied against --screen-scale (the
  // auto-computed fit-to-cutout factor) rather than replacing it, so
  // "reset" always means "back to the auto-fit size", not some other
  // fixed default.
  // ---------------------------------------------------------------------
  const STORAGE_KEY = 'st_dealership_user_scale';

  function loadUserScale() {
    try {
      const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
      if (saved && typeof saved.x === 'number' && typeof saved.y === 'number') return saved;
    } catch (e) { /* ignore - malformed or unavailable storage */ }
    return { x: 1, y: 1 };
  }

  function applyUserScale(x, y) {
    x = Math.min(1.5, Math.max(0.5, Number(x) || 1));
    y = Math.min(1.5, Math.max(0.5, Number(y) || 1));
    root.style.setProperty('--user-scale-x', x);
    root.style.setProperty('--user-scale-y', y);
    return { x, y };
  }

  function saveUserScale(x, y) {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ x, y })); } catch (e) { /* ignore */ }
  }

  const initialScale = loadUserScale();
  applyUserScale(initialScale.x, initialScale.y);

  const btn = document.getElementById('display-settings-btn');
  const panel = document.getElementById('display-settings-panel');
  const sliderX = document.getElementById('ds-scale-x');
  const sliderY = document.getElementById('ds-scale-y');

  sliderX.value = initialScale.x;
  sliderY.value = initialScale.y;

  btn.addEventListener('click', () => panel.classList.toggle('hidden'));
  document.getElementById('ds-close').addEventListener('click', () => panel.classList.add('hidden'));

  document.getElementById('ds-reset').addEventListener('click', () => {
    sliderX.value = 1;
    sliderY.value = 1;
    const applied = applyUserScale(1, 1);
    saveUserScale(applied.x, applied.y);
  });

  function onSliderChange() {
    const applied = applyUserScale(sliderX.value, sliderY.value);
    saveUserScale(applied.x, applied.y);
  }
  sliderX.addEventListener('input', onSliderChange);
  sliderY.addEventListener('input', onSliderChange);

  // The app UI underneath was built assuming a full 1920x1080 canvas, but
  // #app-scale-wrapper (style.css) deliberately renders it into a smaller
  // 1476x830 "virtual canvas" instead - same 16:9 ratio, just smaller -
  // so that once scaled up to fill the laptop's screen cutout, text and
  // UI elements end up larger/more readable than a true 1:1 1920x1080
  // render would give. This scale is what does that scaling up: it's
  // always measuredCutoutHeight / 830 (matching the wrapper's height
  // above), constrained by height since the cutout is proportionally
  // wider than 16:9 (fits by height with side margins, not top/bottom
  // margins). Change the 830 here AND the width/height in style.css's
  // #app-scale-wrapper together if you adjust the virtual canvas size.
  function applyScale() {
    const rect = cutout.getBoundingClientRect();
    if (rect.height <= 0) return; // frame is currently hidden - nothing meaningful to measure yet
    const scale = rect.height / 830;
    root.style.setProperty('--screen-scale', scale);
  }

  // A one-shot calculation at load time is not enough: #frame-viewport
  // starts hidden (display:none) until the dealership UI or admin
  // console actually opens, and a hidden element measures as 0x0 - a
  // single applyScale() call here would lock the scale at 0 forever,
  // since nothing else was re-triggering it except an actual window
  // resize (which basically never happens mid-session in a real game).
  // ResizeObserver instead recalculates automatically every time the
  // cutout's real size changes for any reason, including the moment it
  // goes from hidden (0x0) to actually visible.
  const observer = new ResizeObserver(applyScale);
  observer.observe(cutout);

  applyScale();
  window.addEventListener('resize', applyScale);
})();
