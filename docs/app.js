(() => {
  const body = document.body;

  // ---- scroll story: whichever step crosses the middle of the screen drives the MacBook ----
  const steps = [...document.querySelectorAll('.step')];
  const dots = [...document.querySelectorAll('.dots li')];

  function activate(step) {
    steps.forEach((s) => s.classList.toggle('active', s === step));
    body.dataset.mode = step.dataset.mode;
    const n = step.dataset.step;
    dots.forEach((d) => d.classList.toggle('on', d.dataset.dot === n));
    document.dispatchEvent(new CustomEvent('lt:mode', { detail: step.dataset.mode }));
  }

  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) activate(e.target); });
    }, { rootMargin: '-45% 0px -45% 0px' });
    steps.forEach((s) => io.observe(s));
  }
  activate(steps[0]);

  // ---- breathe speed chips ----
  const speedLabel = document.getElementById('speed-label');
  document.querySelectorAll('.chip[data-speed]').forEach((chip, _, all) => {
    chip.addEventListener('click', () => {
      body.style.setProperty('--breathe', chip.dataset.speed);
      all.forEach((c) => c.setAttribute('aria-pressed', String(c === chip)));
      speedLabel.textContent = chip.textContent.toLowerCase();
    });
  });

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
})();
