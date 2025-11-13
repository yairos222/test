const app = document.getElementById('app');
const cashEl = document.getElementById('cash');
const bankEl = document.getElementById('bank');
const cryptoEl = document.getElementById('crypto');
const ibanEl = document.getElementById('iban');
const tierEl = document.getElementById('tier');
const historyList = document.getElementById('historyList');
const favoriteList = document.getElementById('favoriteList');
const closeBtn = document.getElementById('closeBtn');

const depositForm = document.getElementById('depositForm');
const withdrawForm = document.getElementById('withdrawForm');
const transferForm = document.getElementById('transferForm');
const historyForm = document.getElementById('historyForm');
const favoriteForm = document.getElementById('favoriteForm');

const RESOURCE = GetParentResourceName ? GetParentResourceName() : 'banking';

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

function updateBalances(data) {
    cashEl.textContent = formatCurrency(data.cash || 0);
    bankEl.textContent = formatCurrency(data.bank || 0);
    cryptoEl.textContent = formatCurrency(data.crypto || 0);
    ibanEl.textContent = `IBAN: ${data.iban || 'N/A'}`;
    tierEl.textContent = `Tier: ${data.tier || 'default'}`;
}

function updateHistory(entries = []) {
    historyList.innerHTML = '';
    entries.forEach(entry => {
        const li = document.createElement('li');
        const sign = entry.amount >= 0 ? '+' : '-';
        const amount = formatCurrency(Math.abs(entry.amount || 0));
        const label = entry.description || entry.action || 'transaction';
        const time = entry.timestamp ? new Date(entry.timestamp * 1000).toLocaleTimeString() : '';
        li.textContent = `[${time}] ${label} (${sign}${amount})`;
        historyList.appendChild(li);
    });
}

function updateFavorites(list = {}) {
    favoriteList.innerHTML = '';
    Object.keys(list).forEach(name => {
        const li = document.createElement('li');
        li.textContent = `${name} → ${list[name]}`;
        favoriteList.appendChild(li);
    });
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || !data.action) return;
    if (data.action === 'open') {
        app.classList.remove('hidden');
        updateBalances(data.data || {});
        updateHistory(data.history || []);
        updateFavorites(data.favorites || {});
    }
    if (data.action === 'close') {
        app.classList.add('hidden');
    }
    if (data.action === 'updateBalances') {
        updateBalances(data.data || {});
    }
    if (data.action === 'updateHistory') {
        updateHistory(data.entries || []);
    }
    if (data.action === 'updateFavorites') {
        updateFavorites(data.favorites || {});
    }
});

closeBtn.addEventListener('click', () => fetchNui('close', {}));

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
