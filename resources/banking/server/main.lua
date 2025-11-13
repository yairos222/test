local json = json
if not json or not json.encode or not json.decode then
    local ok, loaded = pcall(require, 'json')
    if ok then
        json = loaded
    else
        error('json library is required for the banking resource')
    end
end

local Config = {
    localization = {
        default = 'en',
        strings = {
            en = {
                balance = 'Balance — Cash: %s | Bank: %s',
                usageTransfer = 'Usage: /banktransfer <player id|iban|favorite> <amount>',
                usageDeposit = 'Usage: /bankdeposit <amount>',
                usageWithdraw = 'Usage: /bankwithdraw <amount>',
                insufficient = 'You do not have enough funds for that action.',
                invalidAmount = 'Amount must be greater than zero.',
                atmRobberyAlert = 'ATM robbery detected near %s',
                locked = 'Your account is locked. Use /banklock again or contact staff.',
                pinRequired = 'Enter your PIN first with /bankpin <current> <new> or /bankpin <current>.',
                loanDenied = 'Loan denied. Check limits or repay outstanding balances.',
                shareStarted = 'You linked accounts with %s for %d minutes.',
                shareEnded = 'Account link with %s expired.',
                bankrupt = 'Bankruptcy triggered. Service fee deducted and balances reset.'
            }
        }
    },
    startingBalances = {
        cash = 1000,
        bank = 0,
        crypto = 0
    },
    currencies = {
        cash = { label = 'Cash', fractional = false },
        bank = { label = 'Bank', fractional = true },
        crypto = { label = 'Crypto', fractional = true }
    },
    notifications = {
        highImpact = 100000
    },
    atm = {
        models = { -870868698, 506770882, -1364697528, -1126237515 },
        tellerPeds = {
            { model = 's_m_m_highsec_01', coords = { x = 150.2, y = -1040.35, z = 29.37, w = 340.0 } }
        },
        interactDistance = 1.5,
        serviceFee = 0.01,
        withdrawLimit = 5000,
        robbery = {
            cooldown = 900000,
            rewardRange = { 500, 1500 },
            alertEvent = 'banking:securityAlert'
        }
    },
    wires = {
        delayPerThousand = 1000,
        minimumAmount = 5000,
        maxPending = 3
    },
    scheduledPayments = {
        maxActive = 5
    },
    sharedAccounts = {
        defaultLimit = 10000
    },
    taxes = {
        withdraw = 0.005,
        transfer = 0.01,
        treasuryAccount = 'treasury:server'
    },
    savings = {
        minBalance = 10000,
        rate = 0.001,
        interval = 600000
    },
    webhooks = {
        transaction = '',
        audit = '',
        backup = ''
    },
    history = {
        pageSize = 6
    },
    cooldowns = {
        bankdeposit = 3000,
        bankwithdraw = 3000,
        banktransfer = 5000,
        bankwire = 5000,
        bankloan = 60000,
        bankaudit = 60000
    },
    limits = {
        dailyTransfer = 500000,
        dailyWithdrawal = 250000
    },
    overdraft = {
        enabled = true,
        limit = 10000,
        interestRate = 0.01,
        interval = 900000
    },
    donations = {
        goals = {
            server = {
                label = 'Server Upgrades',
                target = 100000,
                raised = 0
            }
        }
    },
    achievements = {
        millionaire = {
            threshold = 1000000,
            message = 'Achievement unlocked: First million banked!'
        }
    },
    loans = {
        rate = 0.02,
        interval = 300000,
        max = 50000
    },
    investments = {
        bonds = { rate = 0.003 },
        stocks = { rateRange = { -0.01, 0.05 } }
    },
    serviceTiers = {
        default = { withdrawLimit = 5000, atmFeeMultiplier = 1.0 },
        vip = { withdrawLimit = 20000, atmFeeMultiplier = 0.5 }
    },
    rent = {
        event = 'banking:rentDue'
    },
    backup = {
        interval = 1800000
    }
}

local Locale = Config.localization.strings
local resourceName = GetCurrentResourceName()
local accounts = {}
local sharedAccounts = {}
local pendingTransfers = {}
local cooldowns = {}
local activeShares = {}
local pendingRequests = {}
local offlineTransfers = {}
local donationGoals = Config.donations.goals
local lastRobberies = {}
local accountsDirty = false

local function debugPrint(message)
    print(('[%s] %s'):format(resourceName, message))
end

local function L(key, ...)
    local lang = Config.localization.default
    local dictionary = Locale[lang] or {}
    local value = dictionary[key] or key
    if select('#', ...) > 0 then
        value = value:format(...)
    end
    return value
end

local function markDirty()
    accountsDirty = true
end

local function formatCurrency(amount)
    local isNegative = amount < 0
    local absolute = math.abs(amount)
    local formatted = string.format('%.2f', absolute)
    local left, right = formatted:match('^(%d+)%.' .. '(%d%d)')
    left = left or formatted
    local withCommas = left
    while true do
        local new, replacements = withCommas:gsub('^(%-?%d+)(%d%d%d)', '%1,%2')
        withCommas = new
        if replacements == 0 then
            break
        end
    end
    return (isNegative and '-' or '') .. '$' .. withCommas .. '.' .. (right or '00')
end

local function generateIban(identifier)
    local hash = tonumber(identifier:gsub('%D', ''), 10) or math.random(10000, 99999)
    local suffix = tostring(hash):sub(-6)
    return ('LS-%s-%s'):format(suffix, math.random(100, 999))
end

local function ensureAccount(identifier)
    if accounts[identifier] then
        return accounts[identifier]
    end

    accounts[identifier] = {
        balances = {
            cash = Config.startingBalances.cash,
            bank = Config.startingBalances.bank,
            crypto = Config.startingBalances.crypto
        },
        history = {},
        iban = generateIban(identifier),
        pin = ('%04d'):format(math.random(0, 9999)),
        pinVerifiedAt = 0,
        favorites = {},
        tier = 'default',
        locked = false,
        lifetime = {
            deposits = 0,
            withdrawals = 0,
            transfersOut = 0,
            transfersIn = 0,
            earnings = 0
        },
        scheduledPayments = {},
        pendingOffline = {},
        loans = {},
        investments = {},
        shares = {},
        achievements = {},
        lastLogin = os.time(),
        lastInterest = os.time(),
        overrides = {},
        requests = {}
    }
    markDirty()
    return accounts[identifier]
end

local function ensureSharedAccount(name)
    sharedAccounts[name] = sharedAccounts[name] or {
        balance = 0,
        members = {},
        limit = Config.sharedAccounts.defaultLimit
    }
    return sharedAccounts[name]
end

local function saveAccounts(force)
    if not accountsDirty and not force then
        return
    end

    local payload = json.encode({ accounts = accounts, shared = sharedAccounts, donations = donationGoals, offline = offlineTransfers })
    SaveResourceFile(resourceName, 'data/accounts.json', payload, -1)
    accountsDirty = false
    debugPrint('Accounts saved to disk')

    if Config.webhooks.backup ~= '' then
        PerformHttpRequest(Config.webhooks.backup, function() end, 'POST', payload, { ['Content-Type'] = 'application/json' })
    end
end

local function loadAccounts()
    local file = LoadResourceFile(resourceName, 'data/accounts.json')
    if not file then
        return
    end

    local decoded = json.decode(file)
    if not decoded then
        return
    end

    accounts = decoded.accounts or {}
    sharedAccounts = decoded.shared or {}
    donationGoals = decoded.donations or donationGoals
    offlineTransfers = decoded.offline or {}

    for identifier, account in pairs(accounts) do
        account.balances = account.balances or {}
        account.balances.cash = tonumber(account.balances.cash or Config.startingBalances.cash) or 0
        account.balances.bank = tonumber(account.balances.bank or Config.startingBalances.bank) or 0
        account.balances.crypto = tonumber(account.balances.crypto or Config.startingBalances.crypto) or 0
        account.history = account.history or {}
        account.iban = account.iban or generateIban(identifier)
        account.pin = account.pin or ('%04d'):format(math.random(0, 9999))
        account.pinVerifiedAt = account.pinVerifiedAt or 0
        account.favorites = account.favorites or {}
        account.tier = account.tier or 'default'
        account.locked = account.locked == true
        account.lifetime = account.lifetime or { deposits = 0, withdrawals = 0, transfersOut = 0, transfersIn = 0, earnings = 0 }
        account.scheduledPayments = account.scheduledPayments or {}
        account.pendingOffline = account.pendingOffline or {}
        account.loans = account.loans or {}
        account.investments = account.investments or {}
        account.shares = account.shares or {}
        account.achievements = account.achievements or {}
        account.lastLogin = account.lastLogin or os.time()
        account.lastInterest = account.lastInterest or os.time()
        account.overrides = account.overrides or {}
        account.requests = account.requests or {}
    end
    debugPrint(('Loaded %d accounts'):format((function(tbl) local c=0 for _ in pairs(tbl) do c=c+1 end return c end)(accounts)))
end

CreateThread(function()
    while true do
        Wait(Config.backup.interval)
        saveAccounts()
    end
end)

local function sendWebhook(url, payload)
    if url == '' then
        return
    end
    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function dispatchNotification(target, message, category)
    if target == 0 then
        debugPrint(message)
        return
    end
    TriggerClientEvent('banking:notify', target, message, category or 'info')
end

local function playSound(target, sound)
    if target ~= 0 then
        TriggerClientEvent('banking:playSound', target, sound)
    end
end

local function sendBalances(src, reason)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    TriggerClientEvent('banking:setBalance', src, {
        cash = account.balances.cash,
        bank = account.balances.bank,
        crypto = account.balances.crypto,
        history = account.history,
        iban = account.iban,
        tier = account.tier
    })
    TriggerEvent('banking:balanceUpdated', src, account.balances.cash, account.balances.bank, reason or 'update')
end

function getIdentifier(src)
    local identifiers = GetPlayerIdentifiers(src)
    for _, identifier in ipairs(identifiers) do
        if identifier:find('license:', 1, true) == 1 then
            return identifier
        end
    end
    return identifiers[1] or ('temp:%s'):format(src)
end

local function formatHistory(account, page, filter)
    local entries = {}
    filter = filter and filter:lower() or nil
    for _, entry in ipairs(account.history or {}) do
        if not filter or entry.action:lower():find(filter, 1, true) then
            entries[#entries + 1] = entry
        end
    end
    local pageSize = Config.history.pageSize
    local totalPages = math.max(1, math.ceil(#entries / pageSize))
    page = math.max(1, math.min(totalPages, page))
    local startIndex = (page - 1) * pageSize + 1
    local sliced = {}
    for i = startIndex, math.min(#entries, startIndex + pageSize - 1) do
        sliced[#sliced + 1] = entries[i]
    end
    return sliced, page, totalPages
end

local function pushHistory(identifier, action, amount, description)
    local account = ensureAccount(identifier)
    account.history = account.history or {}
    table.insert(account.history, 1, {
        action = action,
        amount = amount,
        description = description,
        timestamp = os.time()
    })
    if #account.history > Config.history.pageSize * 10 then
        table.remove(account.history)
    end
    markDirty()
end

local function applyTaxes(action, amount)
    local taxRate = Config.taxes[action]
    if not taxRate or taxRate <= 0 then
        return amount, 0
    end
    local tax = amount * taxRate
    local net = amount - tax
    local treasury = ensureAccount(Config.taxes.treasuryAccount)
    treasury.balances.bank = treasury.balances.bank + tax
    pushHistory(Config.taxes.treasuryAccount, 'tax', tax, ('Tax income from %s'):format(action))
    return net, tax
end

local function applyCooldown(src, command)
    local duration = Config.cooldowns[command]
    if not duration or duration <= 0 then
        return true
    end
    cooldowns[src] = cooldowns[src] or {}
    local now = GetGameTimer()
    local expires = cooldowns[src][command] or 0
    if now < expires then
        dispatchNotification(src, ('Please wait %.1fs before using %s again.'):format((expires - now) / 1000.0, command))
        return false
    end
    cooldowns[src][command] = now + duration
    return true
end

local function applyTransactionLimit(identifier, field, amount, limit)
    if limit <= 0 then
        return true
    end
    local account = ensureAccount(identifier)
    account.daily = account.daily or {}
    local today = os.date('!%Y-%m-%d')
    account.daily[field] = account.daily[field] or { day = today, total = 0 }
    local info = account.daily[field]
    if info.day ~= today then
        info.day = today
        info.total = 0
    end
    if info.total + amount > limit then
        return false, ('Daily %s limit reached.'):format(field)
    end
    info.total = info.total + amount
    return true
end

local function updateLifetime(identifier, field, amount)
    local account = ensureAccount(identifier)
    account.lifetime[field] = (account.lifetime[field] or 0) + amount
    markDirty()
end

local function enforceBankruptcy(identifier)
    local account = ensureAccount(identifier)
    if account.balances.bank < -(Config.overdraft.limit or 0) then
        account.balances.cash = Config.startingBalances.cash
        account.balances.bank = Config.startingBalances.bank
        pushHistory(identifier, 'bankruptcy', 0, L('bankrupt'))
        local playerId = findPlayerByIdentifier(identifier)
        if playerId then
            dispatchNotification(playerId, L('bankrupt'))
        end
    end
end

local function unlockAchievements(identifier)
    local account = ensureAccount(identifier)
    local totalWealth = account.balances.cash + account.balances.bank + account.balances.crypto
    for key, achievement in pairs(Config.achievements) do
        if totalWealth >= achievement.threshold and not account.achievements[key] then
            account.achievements[key] = true
            local playerId = findPlayerByIdentifier(identifier)
            if playerId then
                dispatchNotification(playerId, achievement.message)
            end
        end
    end
end

local function notifyHighImpact(identifier, action, amount)
    if amount < Config.notifications.highImpact then
        return
    end
    sendWebhook(Config.webhooks.transaction, {
        identifier = identifier,
        action = action,
        amount = amount,
        timestamp = os.time()
    })
end

local function findPlayerByIdentifier(identifier)
    for _, playerId in ipairs(GetPlayers()) do
        if getIdentifier(playerId) == identifier then
            return tonumber(playerId)
        end
    end
end

local function sendHistory(src, page, filter)
    if src == 0 then
        debugPrint('bankhistory cannot be used from console.')
        return
    end
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local entries, current, total = formatHistory(account, page or 1, filter)
    TriggerClientEvent('banking:historyPage', src, entries, current, total, filter)
end

local function parseAmount(rawValue, available)
    if not rawValue then
        return false, 'Amount is required.'
    end
    local lower = tostring(rawValue):lower()
    local value
    if lower == 'all' and available then
        value = available
    else
        value = tonumber(rawValue)
    end
    if not value or value <= 0 then
        return false, L('invalidAmount')
    end
    return value
end

local function requireUnlocked(account)
    if account.locked then
        return false, L('locked')
    end
    return true
end

local function queueOfflineTransfer(identifier, entry)
    offlineTransfers[identifier] = offlineTransfers[identifier] or {}
    table.insert(offlineTransfers[identifier], entry)
    markDirty()
end

local function processOfflineTransfers(identifier, src)
    local queued = offlineTransfers[identifier]
    if not queued then
        return
    end
    offlineTransfers[identifier] = nil
    for _, entry in ipairs(queued) do
        local account = ensureAccount(identifier)
        account.balances.bank = account.balances.bank + entry.amount
        pushHistory(identifier, 'transfer_in', entry.amount, entry.description or 'Offline transfer received')
        dispatchNotification(src, entry.description or 'Offline transfer received')
    end
    markDirty()
end

local function applySavings()
    local now = os.time()
    for identifier, account in pairs(accounts) do
        if account.balances.bank >= Config.savings.minBalance and now - (account.lastInterest or 0) >= Config.savings.interval then
            local interest = account.balances.bank * Config.savings.rate
            account.balances.bank = account.balances.bank + interest
            account.lastInterest = now
            pushHistory(identifier, 'savings', interest, 'Savings interest awarded')
        end
    end
end

CreateThread(function()
    while true do
        Wait(Config.savings.interval)
        applySavings()
        saveAccounts()
    end
end)

local function processScheduled()
    local now = os.time()
    for identifier, account in pairs(accounts) do
        for id, schedule in pairs(account.scheduledPayments) do
            if schedule.remaining > 0 and now >= schedule.nextRun then
                local targetAccount = ensureAccount(schedule.target)
                if account.balances.bank >= schedule.amount then
                    account.balances.bank = account.balances.bank - schedule.amount
                    targetAccount.balances.bank = targetAccount.balances.bank + schedule.amount
                    schedule.remaining = schedule.remaining - 1
                    schedule.nextRun = now + schedule.interval
                    pushHistory(identifier, 'schedule_out', -schedule.amount, ('Scheduled payment to %s'):format(schedule.target))
                    pushHistory(schedule.target, 'schedule_in', schedule.amount, ('Scheduled payment from %s'):format(identifier))
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(60000)
        processScheduled()
    end
end)

local function processPendingTransfers()
    local now = os.time()
    for index = #pendingTransfers, 1, -1 do
        local transfer = pendingTransfers[index]
        if now >= transfer.completeAt then
            table.remove(pendingTransfers, index)
            local toAccount = ensureAccount(transfer.to)
            toAccount.balances.bank = toAccount.balances.bank + transfer.amount
            pushHistory(transfer.to, 'wire_in', transfer.amount, ('Wire received from %s'):format(transfer.fromName))
            notifyHighImpact(transfer.to, 'wire_in', transfer.amount)
            local targetSrc = tonumber(transfer.targetSource or 0)
            if targetSrc and GetPlayerName(targetSrc) then
                dispatchNotification(targetSrc, ('Wire received: %s'):format(formatCurrency(transfer.amount)))
                sendBalances(targetSrc, 'wireIn')
            else
                queueOfflineTransfer(transfer.to, { amount = transfer.amount, description = 'Wire transfer completed' })
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(5000)
        processPendingTransfers()
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    account.lastLogin = os.time()
    local now = os.time()
    local offlineSeconds = now - (account.lastInterest or now)
    if offlineSeconds > Config.savings.interval then
        local cycles = math.floor(offlineSeconds / Config.savings.interval)
        for _ = 1, cycles do
            if account.balances.bank >= Config.savings.minBalance then
                local interest = account.balances.bank * Config.savings.rate
                account.balances.bank = account.balances.bank + interest
                pushHistory(identifier, 'savings', interest, 'Offline interest accrual')
            else
                break
            end
        end
        account.lastInterest = now
    end
    processOfflineTransfers(identifier, src)
    dispatchNotification(src, ('Welcome! Your IBAN: %s PIN: %s'):format(account.iban, account.pin))
    TriggerClientEvent('banking:setLocale', src, Config.localization.default)
    sendBalances(src, 'join')
    TriggerClientEvent('banking:setFavorites', src, account.favorites)
end)

AddEventHandler('playerDropped', function()
    saveAccounts()
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then
        return
    end
    saveAccounts(true)
end)

RegisterNetEvent('banking:requestBalance', function(reason)
    sendBalances(source, reason or 'clientRequest')
end)

RegisterNetEvent('banking:notifyDonationGoal', function(goalId)
    local src = source
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local goal = donationGoals[goalId]
    if not goal then
        dispatchNotification(src, 'Unknown donation goal.')
        return
    end
    dispatchNotification(src, ('%s progress: %s / %s'):format(goal.label, formatCurrency(goal.raised), formatCurrency(goal.target)))
end)

RegisterNetEvent('banking:atmUsed', function(coords)
    TriggerEvent('banking:atmUsage', source, coords)
end)

RegisterNetEvent('banking:atmRobbery', function(coords)
    local src = source
    local identifier = getIdentifier(src)
    local now = GetGameTimer()
    local last = lastRobberies[identifier] or 0
    if now - last < Config.atm.robbery.cooldown then
        dispatchNotification(src, 'ATM robbery cooldown active.')
        return
    end
    lastRobberies[identifier] = now
    local reward = math.random(Config.atm.robbery.rewardRange[1], Config.atm.robbery.rewardRange[2])
    local account = ensureAccount(identifier)
    account.balances.cash = account.balances.cash + reward
    pushHistory(identifier, 'atm_robbery', reward, 'ATM robbery reward')
    dispatchNotification(src, ('You stole %s. Expect attention!'):format(formatCurrency(reward)))
    sendBalances(src, 'atmRobbery')
    TriggerEvent(Config.atm.robbery.alertEvent, src, coords, reward)
end)

local function canUseBiometrics(src)
    local result = true
    TriggerEvent('banking:biometricCheck', src, function(allowed)
        result = allowed ~= false
    end)
    return result
end

local function requirePin(src, account)
    if not account.pin then
        return true
    end
    TriggerClientEvent('banking:promptPin', src)
    return true
end

local function adjustCashBalance(target, amount, message)
    if not target or not GetPlayerName(target) then
        return false, 'Player is not online.'
    end
    local identifier = getIdentifier(target)
    local account = ensureAccount(identifier)
    local ok, reason = requireUnlocked(account)
    if not ok then
        return false, reason
    end
    local value = tonumber(amount or 0) or 0
    if value == 0 then
        return false, 'Amount must not be zero.'
    end
    if value < 0 and account.balances.cash < math.abs(value) then
        return false, 'Player does not have enough cash.'
    end
    account.balances.cash = account.balances.cash + value
    markDirty()
    if value > 0 then
        dispatchNotification(target, ('You received %s cash.'):format(formatCurrency(value)))
        pushHistory(identifier, 'cash_in', value, message or 'Cash granted')
        playSound(target, 'cash_in')
    else
        dispatchNotification(target, ('You paid %s cash.'):format(formatCurrency(math.abs(value))))
        pushHistory(identifier, 'cash_out', value, message or 'Cash removed')
        playSound(target, 'cash_out')
    end
    TriggerEvent('banking:transaction', identifier, 'cash_adjust', value, { source = target })
    sendBalances(target, 'cashAdjustment')
    return true
end

exports('AddCash', function(target, amount)
    return adjustCashBalance(target, amount)
end)

local function adjustBankBalance(target, amount, reason)
    if not target or not GetPlayerName(target) then
        return false, 'Player is not online.'
    end
    local identifier = getIdentifier(target)
    local account = ensureAccount(identifier)
    local ok, lockReason = requireUnlocked(account)
    if not ok then
        return false, lockReason
    end
    local value = math.floor(tonumber(amount or 0) or 0)
    if value == 0 then
        return false, 'Amount must not be zero.'
    end
    if value < 0 and account.balances.bank + (Config.overdraft.limit or 0) < math.abs(value) then
        return false, 'Player does not have enough money in the bank.'
    end
    account.balances.bank = account.balances.bank + value
    markDirty()
    if value > 0 then
        dispatchNotification(target, ('You received %s in your bank.'):format(formatCurrency(value)))
        pushHistory(identifier, 'bank_in', value, reason or 'Bank deposit')
    else
        dispatchNotification(target, ('%s was deducted from your bank.'):format(formatCurrency(math.abs(value))))
        pushHistory(identifier, 'bank_out', value, reason or 'Bank withdrawal')
    end
    TriggerEvent('banking:transaction', identifier, 'bank_adjust', value, { source = target })
    sendBalances(target, 'bankAdjustment')
    return true
end

exports('AddBank', function(target, amount, reason)
    return adjustBankBalance(target, amount, reason)
end)

exports('GetBalance', function(target)
    if not target or not GetPlayerName(target) then
        return 0, 0, 0
    end
    local identifier = getIdentifier(target)
    local account = ensureAccount(identifier)
    return account.balances.cash, account.balances.bank, account.balances.crypto
end)

exports('TransferBank', function(from, to, amount)
    if not GetPlayerName(from) or not GetPlayerName(to) then
        return false, 'Both players must be online.'
    end
    local identifier = getIdentifier(from)
    local targetIdentifier = getIdentifier(to)
    local account = ensureAccount(identifier)
    local targetAccount = ensureAccount(targetIdentifier)
    local value = math.floor(tonumber(amount or 0) or 0)
    if value <= 0 then
        return false, 'Amount must be greater than zero.'
    end
    if account.balances.bank < value then
        return false, 'Sender does not have enough bank funds.'
    end
    account.balances.bank = account.balances.bank - value
    targetAccount.balances.bank = targetAccount.balances.bank + value
    pushHistory(identifier, 'transfer_out', -value, ('Sent %s to %s'):format(formatCurrency(value), GetPlayerName(to)))
    pushHistory(targetIdentifier, 'transfer_in', value, ('Received %s from %s'):format(formatCurrency(value), GetPlayerName(from)))
    dispatchNotification(from, ('Transferred %s to %s.'):format(formatCurrency(value), GetPlayerName(to)))
    dispatchNotification(to, ('You received %s from %s.'):format(formatCurrency(value), GetPlayerName(from)))
    sendBalances(from, 'transferOut')
    sendBalances(to, 'transferIn')
    return true
end)

exports('DistributeCrimePayout', function(target, total, ratio)
    if not target or not GetPlayerName(target) then
        return false
    end
    ratio = ratio or 0.5
    local identifier = getIdentifier(target)
    local account = ensureAccount(identifier)
    local bankCut = math.floor(total * ratio)
    local cashCut = total - bankCut
    account.balances.bank = account.balances.bank + bankCut
    account.balances.cash = account.balances.cash + cashCut
    pushHistory(identifier, 'crime', bankCut, ('Crime payout banked (%s cash)'):format(formatCurrency(cashCut)))
    sendBalances(target, 'crimePayout')
    return true
end)

exports('WithdrawForRent', function(target, amount)
    local identifier = getIdentifier(target)
    local account = ensureAccount(identifier)
    if account.balances.bank < amount then
        return false
    end
    account.balances.bank = account.balances.bank - amount
    pushHistory(identifier, 'rent', -amount, 'Rent payment')
    sendBalances(target, 'rent')
    return true
end)

exports('SetAccountOverride', function(identifier, key, value)
    if not identifier or not key then
        return false
    end
    local account = ensureAccount(identifier)
    account.overrides = account.overrides or {}
    account.overrides[key] = value
    markDirty()
    return true
end)

RegisterCommand('bankbalance', function(src)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    dispatchNotification(src, L('balance', formatCurrency(account.balances.cash), formatCurrency(account.balances.bank)))
    sendBalances(src, 'command:bankbalance')
end)

local function resolveTransferTarget(arg, requesterIdentifier)
    local targetId = tonumber(arg or '')
    if targetId and GetPlayerName(targetId) then
        return targetId, getIdentifier(targetId)
    end
    for identifier, account in pairs(accounts) do
        if account.iban == arg or identifier == arg then
            return -1, identifier
        end
    end
    if requesterIdentifier and accounts[requesterIdentifier] then
        local favoriteIdentifier = accounts[requesterIdentifier].favorites[arg]
        if favoriteIdentifier then
            return -1, favoriteIdentifier
        end
    end
    return nil, nil
end

local function processDeposit(src, rawAmount, context)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local ok, reason = requireUnlocked(account)
    if not ok then
        return false, reason
    end
    local amount, err = parseAmount(rawAmount, account.balances.cash)
    if not amount then
        return false, err or L('usageDeposit')
    end
    account.balances.cash = account.balances.cash - amount
    local net, tax = applyTaxes('deposit', amount)
    account.balances.bank = account.balances.bank + net
    updateLifetime(identifier, 'deposits', net)
    pushHistory(identifier, 'deposit', net, ('Deposited %s (tax %s)'):format(formatCurrency(net), formatCurrency(tax)))
    notifyHighImpact(identifier, 'deposit', net)
    sendBalances(src, context or 'deposit')
    playSound(src, 'deposit')
    markDirty()
    return true
end

local function processWithdraw(src, rawAmount, context)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local ok, reason = requireUnlocked(account)
    if not ok then
        return false, reason
    end
    local amount, err = parseAmount(rawAmount, account.balances.bank + (Config.overdraft.limit or 0))
    if not amount then
        return false, err or L('usageWithdraw')
    end
    if context == 'atm' and amount > Config.atm.withdrawLimit then
        return false, ('ATM withdraw limit is %s.'):format(formatCurrency(Config.atm.withdrawLimit))
    end
    local tier = Config.serviceTiers[account.tier] or Config.serviceTiers.default
    if amount > tier.withdrawLimit then
        return false, ('Your tier limit is %s per withdrawal.'):format(formatCurrency(tier.withdrawLimit))
    end
    local allowed, reasonLimit = applyTransactionLimit(identifier, 'withdraw', amount, Config.limits.dailyWithdrawal)
    if not allowed then
        return false, reasonLimit
    end
    if amount >= (account.overrides.biometricThreshold or 20000) and not canUseBiometrics(src) then
        return false, 'Biometric verification failed.'
    end
    local net, tax = applyTaxes('withdraw', amount)
    local fee = 0
    if context == 'atm' and Config.atm.serviceFee > 0 then
        fee = math.floor(amount * Config.atm.serviceFee * (tier.atmFeeMultiplier or 1.0))
        local treasury = ensureAccount(Config.taxes.treasuryAccount)
        treasury.balances.bank = treasury.balances.bank + fee
    end
    account.balances.bank = account.balances.bank - amount
    account.balances.cash = account.balances.cash + math.max(0, net - fee)
    updateLifetime(identifier, 'withdrawals', amount)
    pushHistory(identifier, 'withdraw', -amount, ('Withdrew %s (tax %s fee %s)'):format(formatCurrency(net), formatCurrency(tax), formatCurrency(fee)))
    notifyHighImpact(identifier, 'withdraw', amount)
    sendBalances(src, context or 'withdraw')
    playSound(src, 'withdraw')
    markDirty()
    enforceBankruptcy(identifier)
    return true
end

local function processTransfer(src, targetArg, rawAmount, options)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local ok, reason = requireUnlocked(account)
    if not ok then
        return false, reason
    end
    local amount, err = parseAmount(rawAmount, account.balances.bank)
    if not amount then
        return false, err or L('usageTransfer')
    end
    local allowed, limitReason = applyTransactionLimit(identifier, 'transfer', amount, Config.limits.dailyTransfer)
    if not allowed then
        return false, limitReason
    end
    local pinThreshold = account.overrides.pinThreshold or 10000
    if amount >= pinThreshold then
        local now = os.time()
        if not account.pinVerifiedAt or now - account.pinVerifiedAt > 300 then
            local providedPin = options and options.pin
            if providedPin == account.pin then
                account.pinVerifiedAt = now
            else
                return false, L('pinRequired')
            end
        end
    end
    local targetSrc, targetIdentifier = resolveTransferTarget(targetArg, identifier)
    if not targetIdentifier then
        return false, 'Target not found.'
    end
    if targetIdentifier == identifier then
        return false, 'You cannot transfer money to yourself.'
    end
    local targetAccount = ensureAccount(targetIdentifier)
    local net, tax = applyTaxes('transfer', amount)
    account.balances.bank = account.balances.bank - amount
    targetAccount.balances.bank = targetAccount.balances.bank + net
    updateLifetime(identifier, 'transfersOut', amount)
    updateLifetime(targetIdentifier, 'transfersIn', net)
    pushHistory(identifier, 'transfer_out', -amount, ('Sent %s to %s (tax %s)'):format(formatCurrency(net), targetIdentifier, formatCurrency(tax)))
    pushHistory(targetIdentifier, 'transfer_in', net, ('Received %s from %s'):format(formatCurrency(net), identifier))
    notifyHighImpact(identifier, 'transfer_out', amount)
    notifyHighImpact(targetIdentifier, 'transfer_in', net)
    if targetSrc and targetSrc ~= -1 then
        dispatchNotification(targetSrc, ('You received %s from %s'):format(formatCurrency(net), GetPlayerName(src)))
        sendBalances(targetSrc, 'transferIn')
    else
        queueOfflineTransfer(targetIdentifier, { amount = net, description = ('Transfer from %s'):format(identifier) })
    end
    sendBalances(src, 'transferOut')
    markDirty()
    enforceBankruptcy(identifier)
    return true
end

RegisterCommand('bankdeposit', function(src, args)
    if not applyCooldown(src, 'bankdeposit') then
        return
    end
    local success, message = processDeposit(src, args[1])
    if not success and message then
        dispatchNotification(src, message)
    end
end)

RegisterCommand('bankwithdraw', function(src, args)
    if not applyCooldown(src, 'bankwithdraw') then
        return
    end
    local success, message = processWithdraw(src, args[1])
    if not success and message then
        dispatchNotification(src, message)
    end
end)

RegisterCommand('banktransfer', function(src, args)
    if not applyCooldown(src, 'banktransfer') then
        return
    end
    local success, message = processTransfer(src, args[1], args[2])
    if not success and message then
        dispatchNotification(src, message)
    end
end)

RegisterNetEvent('banking:uiAction', function(action, payload)
    local src = source
    payload = payload or {}
    if action == 'deposit' then
        if not applyCooldown(src, 'bankdeposit') then
            return
        end
        local success, message = processDeposit(src, payload.amount, payload.context)
        if not success and message then
            dispatchNotification(src, message)
        end
    elseif action == 'withdraw' then
        if not applyCooldown(src, 'bankwithdraw') then
            return
        end
        local success, message = processWithdraw(src, payload.amount, payload.context)
        if not success and message then
            dispatchNotification(src, message)
        end
    elseif action == 'transfer' then
        if not applyCooldown(src, 'banktransfer') then
            return
        end
        local success, message = processTransfer(src, payload.target, payload.amount, { pin = payload.pin })
        if not success and message then
            dispatchNotification(src, message)
        end
    elseif action == 'history' then
        sendHistory(src, payload.page or 1, payload.filter)
    elseif action == 'favorite' then
        local identifier = getIdentifier(src)
        local account = ensureAccount(identifier)
        if payload.name and payload.target then
            local _, targetIdentifier = resolveTransferTarget(payload.target, identifier)
            if targetIdentifier then
                account.favorites[payload.name] = targetIdentifier
                TriggerClientEvent('banking:setFavorites', src, account.favorites)
                dispatchNotification(src, ('Favorite %s saved.'):format(payload.name))
                markDirty()
            else
                dispatchNotification(src, 'Target not found for favorite.')
            end
        end
    end
end)

RegisterNetEvent('banking:paycheck', function(amount)
    local src = source
    amount = tonumber(amount or 0) or 0
    if amount <= 0 then
        return
    end
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    account.balances.bank = account.balances.bank + amount
    pushHistory(identifier, 'paycheck', amount, 'Automatic paycheck')
    sendBalances(src, 'paycheck')
    markDirty()
end)

RegisterCommand('bankwire', function(src, args)
    if not applyCooldown(src, 'bankwire') then
        return
    end
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local targetArg = args[1]
    local amount, err = parseAmount(args[2], account.balances.bank)
    if not amount then
        dispatchNotification(src, err or 'Usage: /bankwire <iban> <amount>')
        return
    end
    if amount < Config.wires.minimumAmount then
        dispatchNotification(src, ('Minimum wire amount is %s'):format(formatCurrency(Config.wires.minimumAmount)))
        return
    end
    if #pendingTransfers >= Config.wires.maxPending then
        dispatchNotification(src, 'Wire network is busy. Try again later.')
        return
    end
    local _, targetIdentifier = resolveTransferTarget(targetArg, identifier)
    if not targetIdentifier then
        dispatchNotification(src, 'Target IBAN not found.')
        return
    end
    account.balances.bank = account.balances.bank - amount
    local delay = math.max(Config.wires.delayPerThousand * (amount / 1000.0), 5000)
    table.insert(pendingTransfers, {
        from = identifier,
        fromName = GetPlayerName(src) or identifier,
        to = targetIdentifier,
        amount = amount,
        completeAt = os.time() + math.floor(delay / 1000),
        targetSource = src
    })
    pushHistory(identifier, 'wire_out', -amount, ('Wire scheduled to %s'):format(targetIdentifier))
    dispatchNotification(src, ('Wire scheduled. ETA %d seconds.'):format(math.floor(delay / 1000)))
end)

RegisterCommand('bankschedule', function(src, args)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local action = args[1]
    if action == 'list' then
        local lines = { 'Scheduled payments:' }
        for id, schedule in pairs(account.scheduledPayments) do
            lines[#lines + 1] = ('%s -> %s amount %s remaining %d'):format(id, schedule.target, formatCurrency(schedule.amount), schedule.remaining)
        end
        dispatchNotification(src, table.concat(lines, '\n'))
        return
    end
    if action == 'add' then
        local target = args[2]
        local amount = tonumber(args[3])
        local interval = tonumber(args[4]) or 600
        local repeats = tonumber(args[5]) or 10
        if not target or not amount then
            dispatchNotification(src, 'Usage: /bankschedule add <iban|player> <amount> <interval sec> <times>')
            return
        end
        if (function(tbl) local c=0 for _ in pairs(tbl) do c=c+1 end return c end)(account.scheduledPayments) >= Config.scheduledPayments.maxActive then
            dispatchNotification(src, 'Maximum scheduled payments reached.')
            return
        end
        local _, targetIdentifier = resolveTransferTarget(target, identifier)
        if not targetIdentifier then
            dispatchNotification(src, 'Target not found.')
            return
        end
        local id = ('%s-%d'):format(targetIdentifier, os.time())
        account.scheduledPayments[id] = {
            target = targetIdentifier,
            amount = amount,
            interval = interval,
            remaining = repeats,
            nextRun = os.time() + interval
        }
        dispatchNotification(src, ('Scheduled payment %s created.'):format(id))
        markDirty()
    elseif action == 'remove' then
        local id = args[2]
        if not account.scheduledPayments[id] then
            dispatchNotification(src, 'Schedule not found.')
            return
        end
        account.scheduledPayments[id] = nil
        dispatchNotification(src, ('Schedule %s removed.'):format(id))
        markDirty()
    else
        dispatchNotification(src, 'Usage: /bankschedule <list|add|remove> ...')
    end
end)

RegisterCommand('bankshared', function(src, args)
    local sub = args[1]
    if sub == 'create' then
        local name = args[2]
        if not name then
            dispatchNotification(src, 'Usage: /bankshared create <name>')
            return
        end
        local shared = ensureSharedAccount(name)
        shared.members[getIdentifier(src)] = 'owner'
        dispatchNotification(src, ('Shared account %s created.'):format(name))
        markDirty()
        return
    end
    if sub == 'deposit' or sub == 'withdraw' then
        local name = args[2]
        local amount = tonumber(args[3] or '0')
        if not name or amount <= 0 then
            dispatchNotification(src, 'Usage: /bankshared ' .. sub .. ' <name> <amount>')
            return
        end
        local shared = sharedAccounts[name]
        if not shared then
            dispatchNotification(src, 'Unknown shared account.')
            return
        end
        local identifier = getIdentifier(src)
        if not shared.members[identifier] then
            dispatchNotification(src, 'You do not belong to that account.')
            return
        end
        local account = ensureAccount(identifier)
        if sub == 'deposit' then
            if account.balances.bank < amount then
                dispatchNotification(src, L('insufficient'))
                return
            end
            account.balances.bank = account.balances.bank - amount
            shared.balance = shared.balance + amount
            pushHistory(identifier, 'shared_deposit', -amount, ('Shared account %s'):format(name))
        else
            if shared.balance < amount then
                dispatchNotification(src, 'Shared account lacks funds.')
                return
            end
            shared.balance = shared.balance - amount
            account.balances.bank = account.balances.bank + amount
            pushHistory(identifier, 'shared_withdraw', amount, ('Shared account %s'):format(name))
        end
        dispatchNotification(src, ('Shared account %s balance: %s'):format(name, formatCurrency(shared.balance)))
        markDirty()
        return
    end
    dispatchNotification(src, 'Usage: /bankshared <create|deposit|withdraw> ...')
end)

RegisterCommand('bankhistory', function(src, args)
    local page = tonumber(args[1] or '1')
    local filter = args[2]
    sendHistory(src, page, filter)
end)

RegisterCommand('bankhelp', function(src)
    dispatchNotification(src, 'Commands: /bankbalance /bankdeposit /bankwithdraw /banktransfer /bankwire /bankschedule /bankstats /bankloan /bankinvest')
end)

RegisterCommand('banktop', function(src, args)
    local mode = (args[1] or 'bank'):lower()
    local list = {}
    for identifier, account in pairs(accounts) do
        table.insert(list, {
            identifier = identifier,
            bank = account.balances.bank or 0,
            cash = account.balances.cash or 0,
            wealth = (account.balances.bank or 0) + (account.balances.cash or 0) + (account.balances.crypto or 0),
            gains = account.lifetime.earnings or 0
        })
    end
    table.sort(list, function(a, b)
        if mode == 'cash' then
            return a.cash > b.cash
        elseif mode == 'wealth' then
            return a.wealth > b.wealth
        elseif mode == 'gains' then
            return a.gains > b.gains
        end
        return a.bank > b.bank
    end)
    local lines = { ('Top accounts (%s):'):format(mode) }
    for i = 1, math.min(5, #list) do
        local entry = list[i]
        lines[#lines + 1] = ('%d) %s — %s'):format(i, entry.identifier, formatCurrency(entry[mode] or entry.bank))
    end
    dispatchNotification(src, table.concat(lines, '\n'))
end)

RegisterCommand('bankgive', function(src, args)
    if not IsPlayerAceAllowed(src, 'command.bankgive') then
        dispatchNotification(src, 'Insufficient permissions.')
        return
    end
    local targetId = tonumber(args[1] or '')
    local amount = tonumber(args[2] or '0')
    if not targetId or amount == 0 then
        dispatchNotification(src, 'Usage: /bankgive <player id> <amount>')
        return
    end
    local success, message = adjustBankBalance(targetId, amount, 'bankgive command')
    dispatchNotification(src, message or (success and 'Success' or 'Failed'))
    if success then
        sendWebhook(Config.webhooks.transaction, {
            action = 'bankgive',
            source = getIdentifier(src),
            target = getIdentifier(targetId),
            amount = amount
        })
    end
end)

RegisterCommand('bankset', function(src, args)
    if not IsPlayerAceAllowed(src, 'command.bankset') then
        dispatchNotification(src, 'Insufficient permissions.')
        return
    end
    local targetId = tonumber(args[1] or '')
    local amount = tonumber(args[2] or '0')
    if not targetId then
        dispatchNotification(src, 'Usage: /bankset <player id> <amount>')
        return
    end
    local identifier = getIdentifier(targetId)
    local account = ensureAccount(identifier)
    account.balances.bank = amount
    pushHistory(identifier, 'bank_set', amount, ('Bank set by %s'):format(GetPlayerName(src) or 'console'))
    sendBalances(targetId, 'command:bankset')
    sendWebhook(Config.webhooks.transaction, {
        action = 'bankset',
        source = getIdentifier(src),
        target = identifier,
        amount = amount
    })
end)

RegisterCommand('bankfine', function(src, args)
    if not IsPlayerAceAllowed(src, 'command.bankfine') then
        dispatchNotification(src, 'Insufficient permissions.')
        return
    end
    local targetId = tonumber(args[1] or '')
    local amount = tonumber(args[2] or '0')
    if not targetId or amount <= 0 then
        dispatchNotification(src, 'Usage: /bankfine <player id> <amount>')
        return
    end
    adjustBankBalance(targetId, -amount, 'Fine issued')
    sendWebhook(Config.webhooks.transaction, {
        action = 'bankfine',
        source = getIdentifier(src),
        target = getIdentifier(targetId),
        amount = amount
    })
end)

RegisterCommand('banktier', function(src, args)
    if not IsPlayerAceAllowed(src, 'command.banktier') then
        dispatchNotification(src, 'Insufficient permissions.')
        return
    end
    local targetId = tonumber(args[1] or '')
    local tier = args[2]
    if not targetId or not tier then
        dispatchNotification(src, 'Usage: /banktier <player id> <tier>')
        return
    end
    if not GetPlayerName(targetId) then
        dispatchNotification(src, 'Player offline.')
        return
    end
    if not Config.serviceTiers[tier] then
        dispatchNotification(src, 'Unknown tier.')
        return
    end
    local identifier = getIdentifier(targetId)
    local account = ensureAccount(identifier)
    account.tier = tier
    dispatchNotification(src, ('Assigned %s to tier %s.'):format(GetPlayerName(targetId), tier))
    dispatchNotification(targetId, ('You are now tier %s.'):format(tier))
    markDirty()
end)

RegisterCommand('bankloan', function(src, args)
    if not applyCooldown(src, 'bankloan') then
        return
    end
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    if account.loans.active then
        dispatchNotification(src, L('loanDenied'))
        return
    end
    local amount = tonumber(args[1] or '0')
    if amount <= 0 or amount > Config.loans.max then
        dispatchNotification(src, ('Loan amount must be between 1 and %s'):format(formatCurrency(Config.loans.max)))
        return
    end
    account.loans.active = {
        principal = amount,
        remaining = amount,
        nextPayment = os.time() + Config.loans.interval
    }
    account.balances.bank = account.balances.bank + amount
    pushHistory(identifier, 'loan', amount, 'Loan issued')
    dispatchNotification(src, ('Loan approved: %s'):format(formatCurrency(amount)))
    markDirty()
end)

RegisterCommand('bankrepay', function(src, args)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    if not account.loans.active then
        dispatchNotification(src, 'No active loan.')
        return
    end
    local amount = tonumber(args[1] or '0')
    if amount <= 0 then
        dispatchNotification(src, 'Usage: /bankrepay <amount>')
        return
    end
    if account.balances.bank < amount then
        dispatchNotification(src, L('insufficient'))
        return
    end
    account.balances.bank = account.balances.bank - amount
    account.loans.active.remaining = account.loans.active.remaining - amount
    pushHistory(identifier, 'loan_repay', -amount, 'Loan repayment')
    if account.loans.active.remaining <= 0 then
        account.loans.active = nil
        dispatchNotification(src, 'Loan fully repaid!')
    end
    sendBalances(src, 'loanRepay')
    markDirty()
end)

RegisterCommand('bankinvest', function(src, args)
    local option = args[1]
    local amount = tonumber(args[2] or '0')
    if not option or amount <= 0 then
        dispatchNotification(src, 'Usage: /bankinvest <bonds|stocks> <amount>')
        return
    end
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    if account.balances.bank < amount then
        dispatchNotification(src, L('insufficient'))
        return
    end
    account.balances.bank = account.balances.bank - amount
    account.investments[option] = (account.investments[option] or 0) + amount
    pushHistory(identifier, 'invest_' .. option, -amount, ('Invested %s into %s'):format(formatCurrency(amount), option))
    dispatchNotification(src, ('Investment recorded: %s'):format(option))
    markDirty()
end)

CreateThread(function()
    while true do
        Wait(Config.loans.interval)
        local now = os.time()
        for identifier, account in pairs(accounts) do
            if account.loans.active and now >= account.loans.active.nextPayment then
                local due = math.min(account.loans.active.remaining, account.loans.active.remaining * Config.loans.rate)
                account.loans.active.nextPayment = now + Config.loans.interval
                if account.balances.bank >= due then
                    account.balances.bank = account.balances.bank - due
                    account.loans.active.remaining = account.loans.active.remaining - due
                    pushHistory(identifier, 'loan_interest', -due, 'Loan interest payment')
                else
                    pushHistory(identifier, 'loan_default', 0, 'Failed loan payment')
                    account.balances.bank = account.balances.bank - due
                end
                if account.loans.active.remaining <= 0 then
                    account.loans.active = nil
                    dispatchNotification(-1, ('%s repaid loan'):format(identifier))
                end
            end
        end
        markDirty()
    end
end)

RegisterCommand('bankstats', function(src)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local stats = account.lifetime
    local message = ('Lifetime — Deposits: %s Withdrawals: %s Transfers Out: %s Transfers In: %s')
        :format(formatCurrency(stats.deposits or 0), formatCurrency(stats.withdrawals or 0), formatCurrency(stats.transfersOut or 0), formatCurrency(stats.transfersIn or 0))
    dispatchNotification(src, message)
end)

RegisterCommand('bankrequest', function(src, args)
    local targetId = tonumber(args[1] or '')
    local amount = tonumber(args[2] or '0')
    if not targetId or amount <= 0 then
        dispatchNotification(src, 'Usage: /bankrequest <player id> <amount>')
        return
    end
    if not GetPlayerName(targetId) then
        dispatchNotification(src, 'Target offline.')
        return
    end
    local identifier = getIdentifier(src)
    local targetIdentifier = getIdentifier(targetId)
    pendingRequests[targetIdentifier] = pendingRequests[targetIdentifier] or {}
    local requestId = ('%s-%d'):format(identifier, os.time())
    pendingRequests[targetIdentifier][requestId] = { from = identifier, amount = amount }
    dispatchNotification(targetId, ('%s requested %s via /bankapprove %s'):format(GetPlayerName(src), formatCurrency(amount), requestId))
    dispatchNotification(src, 'Request sent.')
end)

RegisterCommand('bankapprove', function(src, args)
    local requestId = args[1]
    if not requestId then
        dispatchNotification(src, 'Usage: /bankapprove <request id>')
        return
    end
    local identifier = getIdentifier(src)
    local requests = pendingRequests[identifier]
    if not requests or not requests[requestId] then
        dispatchNotification(src, 'Request not found.')
        return
    end
    local request = requests[requestId]
    local targetIdentifier = request.from
    local amount = request.amount
    requests[requestId] = nil
    local targetAccount = ensureAccount(targetIdentifier)
    local account = ensureAccount(identifier)
    if account.balances.bank < amount then
        dispatchNotification(src, L('insufficient'))
        return
    end
    account.balances.bank = account.balances.bank - amount
    targetAccount.balances.bank = targetAccount.balances.bank + amount
    pushHistory(identifier, 'request_out', -amount, ('Request approved to %s'):format(targetIdentifier))
    pushHistory(targetIdentifier, 'request_in', amount, ('Request fulfilled by %s'):format(identifier))
    dispatchNotification(src, 'Request approved.')
    for _, playerId in ipairs(GetPlayers()) do
        if getIdentifier(playerId) == targetIdentifier then
            dispatchNotification(playerId, ('%s approved your request.'):format(GetPlayerName(src)))
            sendBalances(playerId, 'requestIn')
            break
        end
    end
    sendBalances(src, 'requestOut')
end)

RegisterCommand('bankfavorite', function(src, args)
    local nickname = args[1]
    local target = args[2]
    if not nickname or not target then
        dispatchNotification(src, 'Usage: /bankfavorite <nickname> <player id|iban>')
        return
    end
    local _, targetIdentifier = resolveTransferTarget(target, getIdentifier(src))
    if not targetIdentifier then
        dispatchNotification(src, 'Target not found.')
        return
    end
    local account = ensureAccount(getIdentifier(src))
    account.favorites[nickname] = targetIdentifier
    TriggerClientEvent('banking:setFavorites', src, account.favorites)
    dispatchNotification(src, ('Favorite %s saved.'):format(nickname))
    markDirty()
end)

RegisterCommand('bankpin', function(src, args)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    local current = args[1]
    if not current or current ~= account.pin then
        dispatchNotification(src, 'Incorrect PIN.')
        return
    end
    local newPin = args[2]
    if newPin then
        if #newPin < 4 then
            dispatchNotification(src, 'PIN must be at least 4 digits.')
            return
        end
        account.pin = newPin
        dispatchNotification(src, 'PIN updated.')
    else
        account.pinVerifiedAt = os.time()
        dispatchNotification(src, 'PIN verified for transfers (5 minutes).')
    end
    markDirty()
end)

RegisterCommand('bankshare', function(src, args)
    local targetId = tonumber(args[1] or '')
    local duration = tonumber(args[2] or '300')
    if not targetId or not GetPlayerName(targetId) then
        dispatchNotification(src, 'Usage: /bankshare <player id> <duration seconds>')
        return
    end
    local identifier = getIdentifier(src)
    local targetIdentifier = getIdentifier(targetId)
    local expires = os.time() + duration
    activeShares[identifier] = { target = targetIdentifier, expires = expires }
    activeShares[targetIdentifier] = { target = identifier, expires = expires }
    dispatchNotification(src, L('shareStarted', GetPlayerName(targetId), math.floor(duration / 60)))
    dispatchNotification(targetId, L('shareStarted', GetPlayerName(src), math.floor(duration / 60)))
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        for identifier, share in pairs(activeShares) do
            if now >= share.expires then
                local partner = share.target
                activeShares[identifier] = nil
                if partner then
                    activeShares[partner] = nil
                end
                for _, playerId in ipairs(GetPlayers()) do
                    local pidIdentifier = getIdentifier(playerId)
                    if pidIdentifier == identifier or pidIdentifier == partner then
                        dispatchNotification(playerId, L('shareEnded', share.target))
                    end
                end
            end
        end
    end
end)

RegisterCommand('banklock', function(src)
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    account.locked = not account.locked
    dispatchNotification(src, account.locked and 'Account locked.' or 'Account unlocked.')
    markDirty()
end)

RegisterCommand('bankdashboard', function(src)
    if not IsPlayerAceAllowed(src, 'command.bankdashboard') then
        dispatchNotification(src, 'Insufficient permissions.')
        return
    end
    local totals = { cash = 0, bank = 0 }
    for _, account in pairs(accounts) do
        totals.cash = totals.cash + (account.balances.cash or 0)
        totals.bank = totals.bank + (account.balances.bank or 0)
    end
    dispatchNotification(src, ('Totals — Cash: %s Bank: %s'):format(formatCurrency(totals.cash), formatCurrency(totals.bank)))
end)

RegisterCommand('bankaudit', function(src, args)
    if not applyCooldown(src, 'bankaudit') then
        return
    end
    if not IsPlayerAceAllowed(src, 'command.bankaudit') then
        dispatchNotification(src, 'Insufficient permissions.')
        return
    end
    local targetIdentifier = args[1]
    if not targetIdentifier or not accounts[targetIdentifier] then
        dispatchNotification(src, 'Usage: /bankaudit <identifier>')
        return
    end
    local account = accounts[targetIdentifier]
    sendWebhook(Config.webhooks.audit, {
        identifier = targetIdentifier,
        balances = account.balances,
        history = account.history
    })
    dispatchNotification(src, 'Audit exported to webhook.')
end)

RegisterCommand('bankdonate', function(src, args)
    local goalId = args[1]
    local amount = tonumber(args[2] or '0')
    if not goalId or amount <= 0 then
        dispatchNotification(src, 'Usage: /bankdonate <goal id> <amount>')
        return
    end
    local goal = donationGoals[goalId]
    if not goal then
        dispatchNotification(src, 'Goal not found.')
        return
    end
    local identifier = getIdentifier(src)
    local account = ensureAccount(identifier)
    if account.balances.bank < amount then
        dispatchNotification(src, L('insufficient'))
        return
    end
    account.balances.bank = account.balances.bank - amount
    goal.raised = (goal.raised or 0) + amount
    pushHistory(identifier, 'donation', -amount, ('Donated to %s'):format(goal.label))
    dispatchNotification(src, ('Thank you! %s progress: %s/%s'):format(goal.label, formatCurrency(goal.raised), formatCurrency(goal.target)))
    markDirty()
end)

RegisterCommand('bankalert', function(src, args)
    if not IsPlayerAceAllowed(src, 'command.bankalert') then
        dispatchNotification(src, 'Insufficient permissions.')
        return
    end
    local message = table.concat(args, ' ')
    if message == '' then
        dispatchNotification(src, 'Usage: /bankalert <message>')
        return
    end
    TriggerClientEvent('chat:addMessage', -1, { args = { 'Bank', message } })
end)

RegisterCommand('bankreload', function(src)
    if src ~= 0 then
        dispatchNotification(src, 'Console only.')
        return
    end
    loadAccounts()
end)

loadAccounts()
