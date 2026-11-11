(() => {
  const body = document.body;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---- light modes: the demo menu drives the hero laptop and the demo glow ----
  const labels = {
    on: 'Logo light is on',
    off: 'Logo light is off',
    breathe: 'Breathe (medium)',
    strobe: 'Strobe (slow)',
  };
  const status = document.getElementById('menu-status');
  const warn = document.getElementById('strobe-warn');
  const items = document.querySelectorAll('.mi[data-set]');

  function setMode(mode) {
    body.dataset.mode = mode;
    status.textContent = labels[mode];
    warn.hidden = mode !== 'strobe';
    items.forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.set === mode)));
  }
  items.forEach((b) => b.addEventListener('click', () => setMode(b.dataset.set)));
  setMode('breathe');

  // ---- 3D laptop: gentle idle sway, tilts toward the pointer ----
  const laptop = document.getElementById('laptop');
  const stage = document.getElementById('stage');
  if (laptop && !reduceMotion) {
    let pointerActive = false;
    let t0 = performance.now();
    const sway = (t) => {
      if (!pointerActive) {
        const s = Math.sin((t - t0) / 3200);
        laptop.style.setProperty('--ry', `${(s * 24).toFixed(2)}deg`);
        laptop.style.setProperty('--rx', `${(8 + Math.cos((t - t0) / 4100) * 2).toFixed(2)}deg`);
      }
      requestAnimationFrame(sway);
    };
    laptop.style.transition = 'transform .25s ease-out';
    requestAnimationFrame(sway);

    stage.parentElement.addEventListener('pointermove', (e) => {
      const r = stage.getBoundingClientRect();
      const x = (e.clientX - (r.left + r.width / 2)) / r.width;
      const y = (e.clientY - (r.top + r.height / 2)) / r.height;
      pointerActive = true;
      laptop.style.setProperty('--ry', `${(x * 50).toFixed(2)}deg`);
      laptop.style.setProperty('--rx', `${(8 - y * 12).toFixed(2)}deg`);
    });
    stage.parentElement.addEventListener('pointerleave', () => { pointerActive = false; });
  }

  // ---- menu bar clock ----
  const clock = document.getElementById('clock');
  const tick = () => {
    const d = new Date();
    clock.textContent = d.toLocaleDateString(undefined, { weekday: 'short' }) + ' ' +
      d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });
  };
  tick();
  setInterval(tick, 30000);

  // ---- copy buttons ----
  document.querySelectorAll('.copy').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const text = document.getElementById(btn.dataset.copy).textContent;
      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = 'Copied';
      } catch {
        btn.textContent = 'Select & copy';
      }
      setTimeout(() => (btn.textContent = 'Copy'), 1600);
    });
  });

  // ---- reveal sections on scroll ----
  if (!reduceMotion && 'IntersectionObserver' in window) {
    const targets = document.querySelectorAll('.demo, .section-title, .tile, .faq details');
    targets.forEach((el) => el.classList.add('reveal'));
    const io = new IntersectionObserver((entries) => {
      entries.forEach((en) => {
        if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); }
      });
    }, { threshold: 0.15 });
    targets.forEach((el) => io.observe(el));
  }
})();
