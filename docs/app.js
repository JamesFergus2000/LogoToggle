(() => {
  const body = document.body;
  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---------- the morphing panel ----------
  const steps = [...document.querySelectorAll('.step')];
  const panel = document.getElementById('panel');
  const copyBox = document.getElementById('panel-copy');
  const copies = [...copyBox.querySelectorAll('.pc')];
  const rowsBox = document.getElementById('rows');
  const rows = [...rowsBox.querySelectorAll('.row')];
  const pill = document.getElementById('sel-pill');
  const statusText = document.getElementById('status-text');
  const hint = document.getElementById('panel-hint');
  const progress = [...panel.querySelectorAll('.progress i')];
  const reveals = [...panel.querySelectorAll('.reveal-wrap')];

  const STATUS = { off: 'Logo light is off', on: 'Logo light is on', breathe: 'Breathe', strobe: 'Strobe (slow)', clap: 'Listening for claps' };
  let current = -1;
  let breatheSpeed = 'medium';

  function sizeCopy() {
    const on = copies.find((c) => c.classList.contains('on'));
    if (on) copyBox.style.height = on.offsetHeight + 'px';
  }

  function movePill() {
    const mode = body.dataset.mode;
    const row = current > 0 ? rows.find((r) => r.dataset.row === mode) : null;
    if (!row) { pill.style.opacity = '0'; return; }
    pill.style.opacity = '1';
    pill.style.transform = `translateY(${row.offsetTop}px)`;
    pill.style.height = row.offsetHeight + 'px';
    rows.forEach((r) => r.classList.toggle('sel', r === row));
  }

  function setStatus(text) {
    if (statusText.textContent === text) return;
    statusText.classList.add('swap');
    setTimeout(() => { statusText.textContent = text; statusText.classList.remove('swap'); }, reduceMotion ? 0 : 160);
  }

  function activate(i) {
    if (i === current) return;
    current = i;
    const step = steps[i];
    const mode = step.dataset.mode;
    body.dataset.mode = mode;
    body.dataset.shot = i === 0 ? 'intro' : mode;
    body.dataset.section = 'story';
    panel.dataset.step = String(i);
    panel.classList.toggle('menu-open', i > 0);

    copies.forEach((c) => c.classList.toggle('on', c.dataset.for === String(i)));
    sizeCopy();
    reveals.forEach((r) => r.classList.toggle('open', r.dataset.show === String(i)));
    progress.forEach((p, n) => p.classList.toggle('on', n < i));
    setStatus(mode === 'breathe' ? `Breathe (${breatheSpeed})` : STATUS[mode]);
    hint.textContent = i === 0 ? 'Scroll to explore' : `${i} of 5`;
    // Wait for the menu / reveals to start opening before measuring rows.
    requestAnimationFrame(movePill);
    setTimeout(movePill, 360);

    document.dispatchEvent(new CustomEvent('lt:mode', { detail: mode }));
  }

  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => { if (e.isIntersecting) activate(steps.indexOf(e.target)); });
    }, { rootMargin: '-50% 0px -50% 0px' });
    steps.forEach((s) => io.observe(s));

    // Past the story: panel steps aside, Mac settles into a calm glow.
    const install = document.getElementById('install');
    new IntersectionObserver(([e]) => {
      if (e.isIntersecting) {
        current = -1;
        body.dataset.section = 'install';
        body.dataset.mode = 'on';
        body.dataset.shot = 'outro';
        document.dispatchEvent(new CustomEvent('lt:mode', { detail: 'on' }));
      }
    }, { rootMargin: '-40% 0px -60% 0px' }).observe(install);
  }
  activate(0);

  // Clicking a menu row scrolls the story to that mode.
  rows.forEach((r) => r.addEventListener('click', () => {
    const target = steps[Number(r.dataset.go)];
    const y = target.getBoundingClientRect().top + window.scrollY + target.offsetHeight / 2 - window.innerHeight / 2;
    window.scrollTo({ top: y, behavior: reduceMotion ? 'auto' : 'smooth' });
  }));

  // Breathe speed chips.
  panel.querySelectorAll('.chip[data-speed]').forEach((chip, _, all) => {
    chip.addEventListener('click', () => {
      body.style.setProperty('--breathe', chip.dataset.speed);
      all.forEach((c) => c.setAttribute('aria-pressed', String(c === chip)));
      breatheSpeed = chip.textContent.toLowerCase();
      if (body.dataset.mode === 'breathe') setStatus(`Breathe (${breatheSpeed})`);
    });
  });

  // When the story ends, the panel scrolls up with it instead of sitting over the install section.
  const story = document.querySelector('.story');
  function liftPanel() {
    const bottom = story.getBoundingClientRect().bottom;
    const lift = Math.max(0, window.innerHeight - bottom);
    panel.style.setProperty('--lift', lift + 'px');
  }
  window.addEventListener('scroll', liftPanel, { passive: true });
  window.addEventListener('resize', liftPanel);
  liftPanel();

  window.addEventListener('resize', () => { sizeCopy(); movePill(); });
  if (document.fonts) document.fonts.ready.then(() => { sizeCopy(); movePill(); });

  // ---------- copy buttons ----------
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
