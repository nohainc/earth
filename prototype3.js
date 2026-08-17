const data = {
  home: ['The world is moving.', 'Your position is stable. Three signals are worth your attention today.'],
  market: ['Market horizon.', 'Prices, scarcity, and opportunity in the shared economy.'],
  business: ['Build something that lasts.', 'Your decisions shape output, condition, and the future of your business.'],
  civic: ['Rules are gameplay.', 'Every vote changes the conditions other Humans must live within.'],
  city: ['A city is a promise.', 'Infrastructure and services determine who can build a future here.'],
  tech: ['The next advantage is forming.', 'Small breakthroughs compound across time, institutions, and generations.']
};

const saved = JSON.parse(localStorage.getItem('earth-prototype3-state') || '{}');
const state = {
  day: saved.day || 184,
  credits: saved.credits || 18420,
  research: saved.research || 72,
  ballot: saved.ballot || null
};

const persist = () => localStorage.setItem('earth-prototype3-state', JSON.stringify(state));

const api = async (path, options = {}) => {
  try {
    const response = await fetch(path, { headers: { 'content-type': 'application/json' }, ...options });
    if (!response.ok) throw new Error('API unavailable');
    return await response.json();
  } catch (error) {
    return null;
  }
};

function calculateYearAndDay(totalDays) {
  if (totalDays <= 0) return { year: 1, dayOfYear: 1 };
  let daysLeft = totalDays - 1;
  let year = 1;
  while (true) {
    const daysInThisYear = (year % 5 === 0) ? 366 : 365;
    if (daysLeft < daysInThisYear) {
      return { year, dayOfYear: daysLeft + 1 };
    }
    daysLeft -= daysInThisYear;
    year++;
  }
}

const EPOCH_START_TIME_MS = Date.parse('2026-01-01T00:00:00.000Z');
let baseElapsedRealSeconds = Math.max(0, Math.floor((Date.now() - EPOCH_START_TIME_MS) / 1000));
let localElapsedSeconds = 0;

function updateLiveClock() {
  const clockStrong = document.querySelector('.world-clock strong');
  if (!clockStrong) return;
  const totalRealSeconds = baseElapsedRealSeconds + localElapsedSeconds;
  const totalSimMinutes = totalRealSeconds; // 1 real sec = 1 sim min
  const inDayMinute = totalSimMinutes % 1440;
  const totalDays = Math.floor(totalSimMinutes / 1440) + 1;
  const hour = Math.floor(inDayMinute / 60) % 24;
  const minute = inDayMinute % 60;
  const timeStr = `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
  const { year, dayOfYear } = calculateYearAndDay(totalDays);
  clockStrong.textContent = `YEAR ${year} · DAY ${dayOfYear} · ${timeStr}`;
}

function applyCanonical(world) {
  if (!world?.human) return;
  state.day = world.clock.day;
  state.credits = world.human.credits;
  state.research = world.technology.research.progress;
  if (world.clock?.serverCurrentTime) {
    const diffMs = Number(world.clock.serverCurrentTime) - EPOCH_START_TIME_MS;
    baseElapsedRealSeconds = diffMs > 0 ? Math.floor(diffMs / 1000) : 0;
    localElapsedSeconds = 0;
  }
  persist();
  const statCredits = document.querySelector('.stats .stat strong');
  if (statCredits) statCredits.innerHTML = `${state.credits.toLocaleString()} <em>C</em>`;
  updateLiveClock();
  const prog = document.querySelector('.wide-progress i');
  if (prog) prog.style.width = state.research + '%';
}

setInterval(() => {
  localElapsedSeconds++;
  updateLiveClock();
}, 1000);

function go(page) {
  document.querySelectorAll('.page').forEach(x => x.classList.remove('active'));
  const target = document.querySelector('#page-' + page);
  if (target) target.classList.add('active');
  document.querySelectorAll('.nav').forEach(x => x.classList.toggle('active', x.dataset.page === page));
  if (data[page]) {
    document.querySelector('#pageTitle').textContent = data[page][0];
    document.querySelector('#pageIntro').textContent = data[page][1];
  }
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

document.querySelectorAll('[data-page]').forEach(x => x.addEventListener('click', () => go(x.dataset.page)));
document.querySelectorAll('[data-go]').forEach(x => x.addEventListener('click', () => go(x.dataset.go)));

const toast = msg => {
  const t = document.querySelector('#toast');
  if (!t) return;
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(window._toast);
  window._toast = setTimeout(() => t.classList.remove('show'), 2400);
};

// Theme toggle
document.querySelector('#themeBtn')?.addEventListener('click', () => {
  const h = document.documentElement;
  h.dataset.theme = h.dataset.theme === 'aurora' ? 'daylight' : 'aurora';
  toast(h.dataset.theme === 'daylight' ? 'Daylight theme enabled' : 'Aurora night theme enabled');
});

// Advance day action
document.querySelector('#advance')?.addEventListener('click', async () => {
  const result = await api('/api/day/advance', { method: 'POST' });
  if (result?.state) {
    applyCanonical(result.state);
    toast(`Day ${result.result.day} resolved · authoritative ledger updated`);
  } else {
    state.day += 1;
    state.credits += Math.round(580 + Math.random() * 180);
    persist();
    applyCanonical({
      clock: { day: state.day },
      human: { credits: state.credits },
      technology: { research: { progress: state.research } }
    });
    toast(`Day ${state.day} resolved locally`);
  }
});

// Market action
document.querySelector('#marketAction')?.addEventListener('click', async () => {
  const result = await api('/api/market/orders', {
    method: 'POST',
    body: JSON.stringify({ product: 'components', quantity: 12, limitPrice: 120 })
  });
  if (result?.order) {
    toast('Order intent accepted · awaiting uniform batch settlement');
  } else {
    state.credits = Math.max(0, state.credits - 1440);
    persist();
    toast('Order intent recorded locally · server unavailable');
  }
});

// Operating policy choices
document.querySelectorAll('.policy-choice').forEach(button => button.addEventListener('click', async () => {
  document.querySelectorAll('.policy-choice').forEach(item => item.classList.remove('selected'));
  button.classList.add('selected');
  const policy = button.dataset.policy;
  const result = await api('/api/businesses/kline-works/policy', {
    method: 'POST',
    body: JSON.stringify({ policy })
  });
  const copy = {
    reliability: 'Reliability first · 96% machine condition · +760 C expected daily revenue.',
    margin: 'Margin optimized · 92% machine condition · +690 C expected daily revenue.',
    capacity: 'Capacity push · 88% machine condition · +820 C expected daily revenue.'
  };
  const summaryEl = document.querySelector('#policySummary');
  if (summaryEl && copy[policy]) summaryEl.textContent = copy[policy];
  toast(result?.ok ? 'Operating policy queued for the next cycle' : 'Policy saved locally');
}));

// Governance voting
document.querySelector('#yes')?.addEventListener('click', async () => {
  const result = await api('/api/governance/proposals/042/vote', { method: 'POST', body: JSON.stringify({ vote: 'support' }) });
  state.ballot = 'support';
  persist();
  toast(result?.ok ? 'Support ballot recorded by Assembly coordinator' : 'Support ballot saved locally');
});

document.querySelector('#no')?.addEventListener('click', async () => {
  const result = await api('/api/governance/proposals/042/vote', { method: 'POST', body: JSON.stringify({ vote: 'oppose' }) });
  state.ballot = 'oppose';
  persist();
  toast(result?.ok ? 'Oppose ballot recorded by Assembly coordinator' : 'Oppose ballot saved locally');
});

// Research funding
document.querySelector('#fund')?.addEventListener('click', async () => {
  const result = await api('/api/research/fund', { method: 'POST', body: JSON.stringify({ amount: 240 }) });
  if (result?.research) {
    applyCanonical(result.state);
    toast(`Research funding accepted · ${result.research.progress}% complete`);
  } else {
    state.research = Math.min(100, state.research + 10);
    persist();
    const prog = document.querySelector('.wide-progress i');
    if (prog) prog.style.width = state.research + '%';
    toast(`Research funding saved locally · ${state.research}% complete`);
  }
});

// User profile interactive dropdown menu
const userBtn = document.querySelector('#userIdentityBtn');
const userDropdown = document.querySelector('#userDropdown');
const userWrapper = document.querySelector('#userIdentityWrapper');

if (userBtn && userDropdown) {
  const toggleDropdown = (show) => {
    const isExpanded = show !== undefined ? show : !userDropdown.classList.contains('open');
    userDropdown.classList.toggle('open', isExpanded);
    userBtn.setAttribute('aria-expanded', String(isExpanded));
  };

  userBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    toggleDropdown();
  });

  document.addEventListener('click', (e) => {
    if (userWrapper && !userWrapper.contains(e.target)) {
      toggleDropdown(false);
    }
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && userDropdown.classList.contains('open')) {
      toggleDropdown(false);
      userBtn.focus();
    }
  });

  document.querySelector('#menuPreferences')?.addEventListener('click', () => {
    toggleDropdown(false);
    toast('Preferences: Display & notifications updated');
  });

  document.querySelector('#menuSecurity')?.addEventListener('click', () => {
    toggleDropdown(false);
    toast('Ledger Key: #0084-742-AK · Signature verified');
  });

  document.querySelector('#menuSwitch')?.addEventListener('click', () => {
    toggleDropdown(false);
    toast('Affiliation: Operating as Independent in New Carthage');
  });

  document.querySelector('#menuSignOut')?.addEventListener('click', () => {
    toggleDropdown(false);
    toast('Session active · Closed alpha simulation sandbox');
  });
}

// Initial state fetch
api('/api/world').then(result => {
  if (result) applyCanonical(result);
});

// Real-time server-sent events
if (typeof EventSource !== 'undefined') {
  const events = new EventSource('/api/events');
  events.onmessage = message => {
    const event = JSON.parse(message.data);
    const labels = {
      'market.batch_settled': 'Market batch settled · canonical fills are ready',
      'governance.vote_updated': 'Assembly vote updated · your civic state changed',
      'research.progressed': 'Research progress updated',
      'business.policy_changed': 'Business policy accepted',
      'world.day_advanced': 'A new world day has resolved'
    };
    if (labels[event.type]) toast(labels[event.type]);
  };
}
