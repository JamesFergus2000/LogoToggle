(() => {
  const body = document.body;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---- light modes: the demo menu drives the hero MacBook and the demo glow ----
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

  // ---- hero: the Mac rises gently into place as you scroll ----
  const mbp = document.querySelector('.mbp');
  if (mbp && !reduceMotion) {
    const onScroll = () => {
      const p = Math.min(1, window.scrollY / 500);
      mbp.style.transform = `translateY(${(p * -24).toFixed(1)}px) scale(${(1 + p * 0.04).toFixed(3)})`;
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
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
