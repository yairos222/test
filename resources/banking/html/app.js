const app = document.getElementById('app');
const cashEl = document.getElementById('cash');
const bankEl = document.getElementById('bank');
const cryptoEl = document.getElementById('crypto');
const ibanEl = document.getElementById('iban');
const tierEl = document.getElementById('tier');
const historyList = document.getElementById('historyList');
const favoriteList = document.getElementById('favoriteList');
const scheduleList = document.getElementById('scheduleList');
const tutorialList = document.getElementById('tutorialList');
const overlayTutorial = document.getElementById('overlayTutorial');
const hud = document.getElementById('hud');
const hudCash = document.getElementById('hudCash');
const hudBank = document.getElementById('hudBank');
const hudAlerts = document.getElementById('hudAlerts');
const launcher = document.getElementById('launcher');
const launcherBadge = document.getElementById('launcherBadge');
const cameraFeed = document.getElementById('cameraFeed');
const cameraMeta = document.getElementById('cameraMeta');
const themeSelect = document.getElementById('themeSelect');
const tutorialBtn = document.getElementById('tutorialBtn');
const closeBtn = document.getElementById('closeBtn');
const feeTip = document.getElementById('feeTip');
const taxTip = document.getElementById('taxTip');
const cooldownTip = document.getElementById('cooldownTip');
const sandboxBanner = document.getElementById('sandboxBanner');
const tutorialOverlay = document.getElementById('tutorialOverlay');
const closeOverlay = document.getElementById('closeOverlay');
const completeTutorialBtn = document.getElementById('completeTutorial');
const withdrawActions = document.getElementById('withdrawActions');
const qrCanvas = document.getElementById('qrCanvas');

const depositForm = document.getElementById('depositForm');
const withdrawForm = document.getElementById('withdrawForm');
const transferForm = document.getElementById('transferForm');
const historyForm = document.getElementById('historyForm');
const favoriteForm = document.getElementById('favoriteForm');
const qrForm = document.getElementById('qrForm');

const RESOURCE = GetParentResourceName ? GetParentResourceName() : 'banking';
const state = {
    data: {},
    history: [],
    favorites: {},
    schedules: [],
    onboarding: { steps: {} },
    tutorialSteps: [],
    tooltips: {},
    themes: {},
    preferences: {},
    quickActions: { withdraw: [] },
    alerts: {},
    atmNetwork: {},
    contextData: {}
};

function applyTheme(theme) {
    if (!theme) return;
    app.dataset.theme = theme;
}

function fetchNui(action, data) {
    fetch(`https://${RESOURCE}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
    });
}

function formatCurrency(amount) {
    return '$' + (Number(amount) || 0).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function updateBalances() {
    cashEl.textContent = formatCurrency(state.data.cash || 0);
    bankEl.textContent = formatCurrency(state.data.bank || 0);
    cryptoEl.textContent = formatCurrency(state.data.crypto || 0);
    ibanEl.textContent = `IBAN: ${state.data.iban || 'N/A'}`;
    tierEl.textContent = `Tier: ${state.data.tier || 'default'}`;
}

function renderHistory() {
    historyList.innerHTML = '';
    state.history.forEach(entry => {
        const li = document.createElement('li');
        const sign = entry.amount >= 0 ? '+' : '-';
        const amount = formatCurrency(Math.abs(entry.amount || 0));
        const label = entry.description || entry.action || 'transaction';
        const time = entry.timestamp ? new Date(entry.timestamp * 1000).toLocaleTimeString() : '';
        li.textContent = `[${time}] ${label} (${sign}${amount})`;
        historyList.appendChild(li);
    });
}

function renderFavorites() {
    favoriteList.innerHTML = '';
    Object.entries(state.favorites).forEach(([name, target]) => {
        const li = document.createElement('li');
        li.textContent = `${name} → ${target}`;
        favoriteList.appendChild(li);
    });
}

function renderSchedules() {
    scheduleList.innerHTML = '';
    state.schedules.forEach(entry => {
        const li = document.createElement('li');
        li.draggable = true;
        li.dataset.id = entry.id;
        li.innerHTML = `<span>${entry.target}</span><span>${formatCurrency(entry.amount)}</span><small>${entry.remaining} left</small>`;
        li.addEventListener('dragstart', handleDragStart);
        li.addEventListener('dragover', handleDragOver);
        li.addEventListener('drop', handleDrop);
        scheduleList.appendChild(li);
    });
}

function renderTutorial(listEl) {
    listEl.innerHTML = '';
    state.tutorialSteps.forEach(step => {
        const li = document.createElement('li');
        const complete = state.onboarding.steps && state.onboarding.steps[step.id];
        li.classList.toggle('complete', !!complete);
        li.textContent = `${step.title} — ${step.description}`;
        listEl.appendChild(li);
    });
}

function renderTooltips() {
    feeTip.textContent = state.tooltips.atmFee || '';
    taxTip.textContent = `${state.tooltips.withdrawalTax || ''} ${state.tooltips.transferTax || ''}`;
    cooldownTip.textContent = state.tooltips.cooldowns || '';
}

function renderThemeOptions() {
    themeSelect.innerHTML = '';
    Object.entries(state.themes).forEach(([key, theme]) => {
        const option = document.createElement('option');
        option.value = key;
        option.textContent = theme.label || key;
        if (state.preferences.theme === key) {
            option.selected = true;
        }
        themeSelect.appendChild(option);
    });
    applyTheme(state.preferences.theme);
}

function renderQuickActions() {
    withdrawActions.innerHTML = '';
    (state.quickActions.withdraw || []).forEach(amount => {
        const button = document.createElement('button');
        button.type = 'button';
        button.textContent = formatCurrency(amount);
        button.addEventListener('click', () => fetchNui('quickAction', { action: 'withdraw', amount }));
        withdrawActions.appendChild(button);
    });
}

function renderCamera() {
    const context = state.contextData || {};
    cameraFeed.textContent = context.label || 'No feed';
    const network = context.id ? state.atmNetwork[context.id] : null;
    const risk = network ? Math.floor((network.robberyRisk || 0) * 100) : 0;
    cameraMeta.textContent = context.signage ? `${context.signage} — Risk ${risk}%` : '';
}

function updateHudWidget(payload) {
    if (!payload) {
        hud.classList.add('hidden');
        return;
    }
    hudCash.textContent = formatCurrency(payload.cash || 0);
    hudBank.textContent = formatCurrency(payload.bank || 0);
    const totalAlerts = (payload.alerts?.wires || 0) + (payload.alerts?.donations || 0) + (payload.alerts?.loanDue ? 1 : 0);
    hudAlerts.textContent = totalAlerts;
    hud.classList.toggle('hidden', payload.visible === false);
}

function updateLauncherBadge(alerts) {
    const total = (alerts?.wires || 0) + (alerts?.donations || 0) + (alerts?.loanDue ? 1 : 0);
    if (total > 0) {
        launcherBadge.textContent = total;
        launcherBadge.classList.remove('hidden');
        launcher.classList.remove('hidden');
    } else {
        launcherBadge.classList.add('hidden');
        launcher.classList.add('hidden');
    }
}

function drawQr(text) {
    const ctx = qrCanvas.getContext('2d');
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, qrCanvas.width, qrCanvas.height);
    ctx.fillStyle = '#fff';
    for (let x = 0; x < 16; x += 1) {
        for (let y = 0; y < 16; y += 1) {
            const hash = (x * 31 + y * 17 + text.length * 13) % 7;
            if (hash > 3) {
                ctx.fillRect(x * 6, y * 6, 4, 4);
            }
        }
    }
}

function handleDragStart(event) {
    event.dataTransfer.setData('text/plain', event.currentTarget.dataset.id);
}

function handleDragOver(event) {
    event.preventDefault();
}

function handleDrop(event) {
    event.preventDefault();
    const fromId = event.dataTransfer.getData('text/plain');
    const target = event.currentTarget.dataset.id;
    if (!fromId || fromId === target) return;
    const ids = state.schedules.map(s => s.id);
    const fromIndex = ids.indexOf(fromId);
    const toIndex = ids.indexOf(target);
    if (fromIndex === -1 || toIndex === -1) return;
    ids.splice(toIndex, 0, ids.splice(fromIndex, 1)[0]);
    fetchNui('scheduleReorder', { order: ids });
}

function handleKeyboardNav(event) {
    if (!app || app.classList.contains('hidden')) return;
    const focusable = Array.from(app.querySelectorAll('input, button, select'));
    const currentIndex = focusable.indexOf(document.activeElement);
    if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
        const next = focusable[(currentIndex + 1) % focusable.length];
        next?.focus();
    } else if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
        const next = focusable[(currentIndex - 1 + focusable.length) % focusable.length];
        next?.focus();
    }
}

function pollControllers() {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const pad = pads.find(Boolean);
    if (!pad) return;
    if (pad.buttons[0]?.pressed) {
        const firstInput = app.querySelector('input, button');
        firstInput?.focus();
    }
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;
    if (data.action === 'open') {
        app.classList.remove('hidden');
        document.body.classList.add('tablet-open');
        state.data = data.data || {};
        state.history = data.history || [];
        state.favorites = data.favorites || {};
        state.schedules = data.schedules || [];
        state.onboarding = data.onboarding || state.onboarding;
        state.tutorialSteps = data.tutorialSteps || state.tutorialSteps;
        state.tooltips = data.tooltips || state.tooltips;
        state.themes = data.themes || state.themes;
        state.preferences = data.preferences || state.preferences;
        state.quickActions = data.quickActions || state.quickActions;
        state.alerts = data.alerts || state.alerts;
        state.atmNetwork = data.atmNetwork || state.atmNetwork;
        state.contextData = data.contextData || state.contextData;
        sandboxBanner.classList.toggle('hidden', !state.preferences.sandbox);
        updateBalances();
        renderHistory();
        renderFavorites();
        renderSchedules();
        renderTutorial(tutorialList);
        renderTooltips();
        renderThemeOptions();
        renderQuickActions();
        renderCamera();
        drawQr(state.data.iban || '');
        if (!state.onboarding.completed) {
            renderTutorial(overlayTutorial);
            tutorialOverlay.classList.remove('hidden');
        }
    }
    if (data.action === 'close') {
        app.classList.add('hidden');
        document.body.classList.remove('tablet-open');
        tutorialOverlay.classList.add('hidden');
    }
    if (data.action === 'updateBalances') {
        state.data = { ...state.data, ...data.data };
        updateBalances();
    }
    if (data.action === 'updateHistory') {
        state.history = data.entries || [];
        renderHistory();
    }
    if (data.action === 'updateFavorites') {
        state.favorites = data.favorites || {};
        renderFavorites();
    }
    if (data.action === 'updateSchedules') {
        state.schedules = data.schedules || [];
        renderSchedules();
    }
    if (data.action === 'updateHud') {
        updateHudWidget(data.hud);
    }
    if (data.action === 'alertBadge') {
        updateLauncherBadge(data.alerts);
    }
    if (data.action === 'context') {
        state.onboarding = data.onboarding || state.onboarding;
        state.tutorialSteps = data.tutorialSteps || state.tutorialSteps;
        state.tooltips = data.tooltips || state.tooltips;
        state.themes = data.themes || state.themes;
        state.preferences = data.preferences || state.preferences;
        state.quickActions = data.quickActions || state.quickActions;
        state.alerts = data.alerts || state.alerts;
        state.atmNetwork = data.atmNetwork || state.atmNetwork;
        state.contextData = data.context || state.contextData;
        sandboxBanner.classList.toggle('hidden', !state.preferences.sandbox);
        renderTutorial(tutorialList);
        renderTooltips();
        renderThemeOptions();
        renderQuickActions();
        renderCamera();
    }
});

closeBtn.addEventListener('click', () => fetchNui('close', {}));
launcher.addEventListener('click', () => fetchNui('analytics', { event: 'launcher' }));
themeSelect.addEventListener('change', () => fetchNui('setTheme', { theme: themeSelect.value }));
tutorialBtn.addEventListener('click', () => {
    renderTutorial(overlayTutorial);
    tutorialOverlay.classList.toggle('hidden');
});
closeOverlay.addEventListener('click', () => tutorialOverlay.classList.add('hidden'));
completeTutorialBtn.addEventListener('click', () => fetchNui('completeTutorial', { id: 'complete' }));

depositForm.addEventListener('submit', (e) => {
    e.preventDefault();
    fetchNui('deposit', { amount: depositForm.amount.value });
});

withdrawForm.addEventListener('submit', (e) => {
    e.preventDefault();
    fetchNui('withdraw', { amount: withdrawForm.amount.value });
});

transferForm.addEventListener('submit', (e) => {
    e.preventDefault();
    fetchNui('transfer', {
        target: transferForm.target.value,
        amount: transferForm.amount.value,
        pin: transferForm.pin.value
    });
});

historyForm.addEventListener('submit', (e) => {
    e.preventDefault();
    fetchNui('history', {
        page: Number(historyForm.page.value) || 1,
        filter: historyForm.filter.value
    });
});

favoriteForm.addEventListener('submit', (e) => {
    e.preventDefault();
    fetchNui('favorite', {
        name: favoriteForm.name.value,
        target: favoriteForm.target.value
    });
});

qrForm.addEventListener('submit', (e) => {
    e.preventDefault();
    fetchNui('scanQr', {
        target: qrForm.target.value,
        amount: qrForm.amount.value
    });
});

document.addEventListener('keydown', handleKeyboardNav);
setInterval(pollControllers, 1000);
