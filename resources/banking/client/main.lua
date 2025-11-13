local balances = { cash = 0, bank = 0, crypto = 0 }
local history = {}
local favorites = {}
local locale = 'en'
local uiVisible = false
local uiContext = 'command'
local currentIban = ''
local currentTier = 'default'
local scheduledPayments = {}
local tutorialData = { steps = {}, completed = false }
local tutorialSteps = {}
local uiPreferences = { theme = 'emerald', hud = true, analytics = true, smartwatch = true }
local uiThemes = {}
local uiTooltips = {}
local uiCooldowns = {}
local uiTaxes = {}
local quickActions = { withdraw = {}, deposit = {} }
local alerts = { wires = 0, loanDue = 0, donations = 0 }
local atmLocations = {}
local tellerLocations = {}
local atmNetworkState = {}
local lastInteractionContext = {}
local spawnedTellers = {}
local atmMeta = { fee = 0.01, withdrawLimit = 5000 }

local function formatCurrency(amount)
    local sign = amount < 0 and '-' or ''
    local value = math.abs(amount)
    return ("%s$%0.2f"):format(sign, value)
end

local function showNotification(message, category)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    local icon = 'CHAR_BANK_FLEECA'
    EndTextCommandThefeedPostMessagetext(icon, icon, false, 9, 'Fleeca Banking', category or '')
    EndTextCommandThefeedPostTicker(false, false)
    TriggerEvent('chat:addMessage', {
        color = category == 'error' and { 200, 50, 50 } or { 0, 200, 120 },
        multiline = true,
        args = { 'Banking', message }
    })
end

RegisterNetEvent('banking:notify', function(message, category)
    showNotification(message, category)
end)

RegisterNetEvent('banking:setLocale', function(lang)
    locale = lang or 'en'
end)

local function sendUiMessage(payload)
    if not uiVisible then
        return
    end
    SendNUIMessage(payload)
end

local function syncUiMetadata()
    SendNUIMessage({
        action = 'context',
        onboarding = tutorialData,
        tutorialSteps = tutorialSteps,
        tooltips = uiTooltips,
        themes = uiThemes,
        preferences = uiPreferences,
        schedules = scheduledPayments,
        quickActions = quickActions,
        cooldowns = uiCooldowns,
        taxes = uiTaxes,
        alerts = alerts,
        atmNetwork = atmNetworkState,
        context = lastInteractionContext
    })
end

local function updateHud()
    SendNUIMessage({
        action = 'updateHud',
        hud = {
            cash = balances.cash,
            bank = balances.bank,
            crypto = balances.crypto,
            alerts = alerts,
            visible = uiPreferences.hud ~= false
        }
    })
end

local function updateAlertBadge()
    SendNUIMessage({
        action = 'alertBadge',
        alerts = alerts
    })
end

local function updateUiBalances()
    sendUiMessage({
        action = 'updateBalances',
        data = {
            cash = balances.cash,
            bank = balances.bank,
            crypto = balances.crypto,
            iban = currentIban,
            tier = currentTier,
            alerts = alerts
        }
    })
end

local function setUiVisible(state, context)
    uiVisible = state
    if state then
        uiContext = context or uiContext
        SetNuiFocus(true, true)
        if SetNuiFocusKeepInput then
            SetNuiFocusKeepInput(true)
        end
        SendNUIMessage({
            action = 'open',
            context = uiContext,
            data = {
                cash = balances.cash,
                bank = balances.bank,
                crypto = balances.crypto,
                iban = currentIban,
                tier = currentTier
            },
            favorites = favorites,
            history = history,
            locale = locale,
            schedules = scheduledPayments,
            onboarding = tutorialData,
            tutorialSteps = tutorialSteps,
            tooltips = uiTooltips,
            themes = uiThemes,
            preferences = uiPreferences,
            quickActions = quickActions,
            cooldowns = uiCooldowns,
            taxes = uiTaxes,
            alerts = alerts,
            atmNetwork = atmNetworkState,
            contextData = lastInteractionContext
        })
        syncUiMetadata()
    else
        SetNuiFocus(false, false)
        if SetNuiFocusKeepInput then
            SetNuiFocusKeepInput(false)
        end
        SendNUIMessage({ action = 'close' })
    end
end

local function openBank(context, coords)
    if not uiVisible then
        lastInteractionContext = coords or { type = context or 'command' }
        setUiVisible(true, context or 'command')
        if context == 'atm' or context == 'teller' then
            TriggerServerEvent('banking:atmUsed', coords or {})
        end
    end
end

local function closeBank()
    if uiVisible then
        setUiVisible(false)
    end
end

RegisterNetEvent('banking:setBalance', function(data)
    balances.cash = data.cash or 0
    balances.bank = data.bank or 0
    balances.crypto = data.crypto or 0
    history = data.history or history
    currentIban = data.iban or currentIban
    currentTier = data.tier or currentTier
    scheduledPayments = data.schedules or scheduledPayments
    tutorialData = data.onboarding or tutorialData
    tutorialSteps = data.tutorialSteps or tutorialSteps
    uiPreferences = data.preferences or uiPreferences
    uiThemes = data.themes or uiThemes
    uiTooltips = data.tooltips or uiTooltips
    uiCooldowns = data.cooldowns or uiCooldowns
    uiTaxes = data.taxes or uiTaxes
    quickActions = data.quickActions or quickActions
    alerts = data.alerts or alerts
    atmMeta = data.atmMeta or atmMeta
    if uiVisible then
        updateUiBalances()
        sendUiMessage({ action = 'updateHistory', entries = history })
        sendUiMessage({ action = 'updateSchedules', schedules = scheduledPayments })
        syncUiMetadata()
    else
        TriggerEvent('chat:addMessage', {
            color = { 0, 200, 120 },
            multiline = true,
            args = { 'Banking', ('Cash: %s | Bank: %s'):format(formatCurrency(balances.cash), formatCurrency(balances.bank)) }
        })
    end
    if uiPreferences.smartwatch ~= false and alerts.loanDue and alerts.loanDue > 0 then
        PlaySoundFrontend(-1, 'TENNIS_POINT_WON', 'HUD_AWARDS', true)
    end
    updateHud()
    updateAlertBadge()
end)

RegisterNetEvent('banking:historyPage', function(entries, page, total, filter)
    history = entries or {}
    sendUiMessage({ action = 'updateHistory', entries = history, page = page, total = total, filter = filter })
    if not uiVisible then
        TriggerEvent('chat:addMessage', { color = { 0, 200, 120 }, args = { 'Banking', ('History page %d/%d'):format(page or 1, total or 1) } })
        for _, entry in ipairs(history) do
            TriggerEvent('chat:addMessage', {
                color = { entry.amount >= 0 and 0 or 200, 200, 120 },
                args = { 'Banking', ('[%s] %s (%s%s)'):format(os.date('%H:%M', entry.timestamp or os.time()), entry.description or entry.action or 'transaction', entry.amount >= 0 and '+' or '-', formatCurrency(math.abs(entry.amount or 0))) }
            })
        end
    end
end)

RegisterNetEvent('banking:setFavorites', function(list)
    favorites = list or {}
    sendUiMessage({ action = 'updateFavorites', favorites = favorites })
    if uiVisible then
        syncUiMetadata()
    end
end)

RegisterNetEvent('banking:playSound', function(sound)
    if sound then
        PlaySoundFrontend(-1, sound, 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
end)

RegisterNetEvent('banking:promptPin', function()
    showNotification('Enter your PIN via /bankpin <current pin> [new pin] for high-value transfers.', 'info')
end)

RegisterNetEvent('banking:syncInteractionPoints', function(data)
    atmLocations = data.atms or {}
    tellerLocations = data.tellers or {}
    if uiVisible then
        syncUiMetadata()
    end
end)

RegisterNetEvent('banking:atmNetwork', function(state)
    atmNetworkState = state or atmNetworkState
    if uiVisible then
        syncUiMetadata()
    end
end)

local function requestBalance()
    TriggerServerEvent('banking:requestBalance', 'ui')
end

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then
        return
    end
    requestBalance()
    TriggerServerEvent('banking:requestWorldData')
    TriggerEvent('chat:addSuggestion', '/bankbalance', 'Check your balances')
    TriggerEvent('chat:addSuggestion', '/bankdeposit', 'Deposit cash into the bank', { { name = 'amount', help = 'Amount or "all"' } })
    TriggerEvent('chat:addSuggestion', '/bankwithdraw', 'Withdraw from the bank', { { name = 'amount', help = 'Amount or "all"' } })
    TriggerEvent('chat:addSuggestion', '/banktransfer', 'Transfer bank funds', { { name = 'target', help = 'Player id, IBAN or favorite' }, { name = 'amount', help = 'Amount' } })
    TriggerEvent('chat:addSuggestion', '/bankwire', 'Schedule a timed wire', { { name = 'iban', help = 'Target IBAN' }, { name = 'amount', help = 'Amount' } })
    TriggerEvent('chat:addSuggestion', '/bankschedule', 'Manage scheduled payments', { { name = 'subcommand', help = 'list/add/remove' } })
    TriggerEvent('chat:addSuggestion', '/bankshared', 'Shared account actions', { { name = 'subcommand', help = 'create/deposit/withdraw' } })
    TriggerEvent('chat:addSuggestion', '/bankhistory', 'Show paginated history', { { name = 'page', help = 'Page number' }, { name = 'filter', help = 'Filter string' } })
    TriggerEvent('chat:addSuggestion', '/bankgive', 'Admin: adjust bank balance', { { name = 'id', help = 'Player id' }, { name = 'amount', help = 'Amount (+/-)' } })
    TriggerEvent('chat:addSuggestion', '/bankset', 'Admin: set bank balance', { { name = 'id', help = 'Player id' }, { name = 'amount', help = 'Amount' } })
    TriggerEvent('chat:addSuggestion', '/bankfine', 'Admin: fine a player', { { name = 'id', help = 'Player id' }, { name = 'amount', help = 'Amount' } })
    TriggerEvent('chat:addSuggestion', '/bankloan', 'Request a payday loan', { { name = 'amount', help = 'Requested amount' } })
    TriggerEvent('chat:addSuggestion', '/bankrepay', 'Repay an active loan', { { name = 'amount', help = 'Repayment amount' } })
    TriggerEvent('chat:addSuggestion', '/bankinvest', 'Invest into bonds or stocks', { { name = 'option', help = 'bonds/stocks' }, { name = 'amount', help = 'Amount' } })
    TriggerEvent('chat:addSuggestion', '/bankstats', 'See your lifetime banking stats')
    TriggerEvent('chat:addSuggestion', '/bankfavorite', 'Save a transfer favorite', { { name = 'nickname', help = 'Nickname' }, { name = 'target', help = 'Player id or IBAN' } })
    TriggerEvent('chat:addSuggestion', '/bankpin', 'Verify or change your banking PIN', { { name = 'current', help = 'Current PIN' }, { name = 'new', help = 'Optional new PIN' } })
    TriggerEvent('chat:addSuggestion', '/bankrequest', 'Request funds from another player', { { name = 'id', help = 'Player id' }, { name = 'amount', help = 'Amount' } })
    TriggerEvent('chat:addSuggestion', '/bankapprove', 'Approve a pending bank request', { { name = 'request id', help = 'Request id from notification' } })
    TriggerEvent('chat:addSuggestion', '/bankdonate', 'Donate to configured goals', { { name = 'goal id', help = 'Goal identifier' }, { name = 'amount', help = 'Amount' } })
    TriggerEvent('chat:addSuggestion', '/bankshare', 'Temporarily link accounts', { { name = 'player id', help = 'Partner id' }, { name = 'duration', help = 'Seconds' } })
    TriggerEvent('chat:addSuggestion', '/banklock', 'Toggle account lock state')
    TriggerEvent('chat:addSuggestion', '/banktier', 'Admin: set service tier', { { name = 'player id', help = 'Player id' }, { name = 'tier', help = 'Tier name' } })
    TriggerEvent('chat:addSuggestion', '/bankdashboard', 'Admin: total cash/bank overview')
    TriggerEvent('chat:addSuggestion', '/bankaudit', 'Admin: export account history', { { name = 'identifier', help = 'Identifier or IBAN' } })
end)

AddEventHandler('playerSpawned', requestBalance)

RegisterCommand('bankmenu', function()
    openBank('command')
end)

RegisterKeyMapping('bankmenu', 'Open the banking tablet', 'keyboard', 'F6')

RegisterCommand('mobilebank', function()
    if uiPreferences.mobileApp == false then
        showNotification('Mobile banking is disabled for your account.', 'error')
        return
    end
    openBank('mobile', { type = 'mobile' })
end)

RegisterNUICallback('close', function(_, cb)
    closeBank()
    cb('ok')
end)

RegisterNUICallback('deposit', function(data, cb)
    TriggerServerEvent('banking:uiAction', 'deposit', { amount = data.amount, context = uiContext })
    cb('ok')
end)

RegisterNUICallback('withdraw', function(data, cb)
    TriggerServerEvent('banking:uiAction', 'withdraw', { amount = data.amount, context = uiContext })
    cb('ok')
end)

RegisterNUICallback('transfer', function(data, cb)
    TriggerServerEvent('banking:uiAction', 'transfer', { target = data.target, amount = data.amount, pin = data.pin })
    cb('ok')
end)

RegisterNUICallback('history', function(data, cb)
    TriggerServerEvent('banking:uiAction', 'history', { page = data.page, filter = data.filter })
    cb('ok')
end)

RegisterNUICallback('favorite', function(data, cb)
    TriggerServerEvent('banking:uiAction', 'favorite', { name = data.name, target = data.target })
    cb('ok')
end)

RegisterNUICallback('completeTutorial', function(data, cb)
    TriggerServerEvent('banking:completeTutorial', data and data.id or nil)
    cb('ok')
end)

RegisterNUICallback('setTheme', function(data, cb)
    if data and data.theme then
        uiPreferences.theme = data.theme
        TriggerServerEvent('banking:updatePreference', { theme = data.theme })
    end
    cb('ok')
end)

RegisterNUICallback('toggleHud', function(data, cb)
    uiPreferences.hud = data.enabled ~= false
    updateHud()
    TriggerServerEvent('banking:updatePreference', { hud = uiPreferences.hud })
    cb('ok')
end)

RegisterNUICallback('analytics', function(data, cb)
    if uiPreferences.analytics ~= false and data then
        TriggerServerEvent('banking:uiAnalytics', data)
    end
    cb('ok')
end)

RegisterNUICallback('scheduleReorder', function(data, cb)
    if data and data.order then
        TriggerServerEvent('banking:reorderSchedules', data.order)
    end
    cb('ok')
end)

RegisterNUICallback('quickAction', function(data, cb)
    if data and data.action and data.amount then
        if data.action == 'withdraw' then
            TriggerServerEvent('banking:uiAction', 'withdraw', { amount = data.amount, context = uiContext })
        else
            TriggerServerEvent('banking:uiAction', 'deposit', { amount = data.amount, context = uiContext })
        end
    end
    cb('ok')
end)

RegisterNUICallback('scanQr', function(data, cb)
    if data and data.target and data.amount then
        TriggerServerEvent('banking:uiAction', 'transfer', { target = data.target, amount = data.amount, pin = data.pin })
    end
    cb('ok')
end)

RegisterNUICallback('requestWorldData', function(_, cb)
    TriggerServerEvent('banking:requestWorldData')
    cb('ok')
end)

local function DrawText3D(coords, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)
    SetDrawOrigin(coords.x, coords.y, coords.z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function nearAtm(coords)
    local playerCoords = GetEntityCoords(PlayerPedId())
    return #(playerCoords - coords) <= 1.5
end

local function spawnTeller(data)
    local model = joaat(data.model or 's_m_m_highsec_01')
    RequestModel(model)
    while not HasModelLoaded(model) do
        Wait(0)
    end
    local ped = CreatePed(4, model, data.coords.x, data.coords.y, data.coords.z - 1.0, data.coords.w, false, true)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    spawnedTellers[data.id or ('teller_' .. ped)] = ped
end

CreateThread(function()
    while true do
        Wait(2000)
        for _, data in ipairs(tellerLocations) do
            if data.id and not spawnedTellers[data.id] then
                spawnTeller(data)
            end
        end
    end
end)

CreateThread(function()
    while true do
        local waitTime = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        for _, atm in ipairs(atmLocations) do
            local coords = vector3(atm.coords.x, atm.coords.y, atm.coords.z)
            local distance = #(playerCoords - coords)
            if distance < 2.0 then
                waitTime = 0
                local state = atmNetworkState[atm.id] or {}
                local prompt = state.online ~= false and ('~g~E~s~ ' .. (atm.prompt or 'Use ATM') .. ' | ~r~H~s~ Rob') or '~o~ATM offline'
                local risk = math.floor((state.robberyRisk or 0) * 100)
                local queue = state.queue or 0
                DrawText3D(vector3(coords.x, coords.y, coords.z + 1.0), ('%s | Risk %d%% Queue %d'):format(prompt, risk, queue))
                if state.online ~= false and IsControlJustReleased(0, 38) then
                    openBank('atm', {
                        type = 'atm',
                        x = coords.x,
                        y = coords.y,
                        z = coords.z,
                        id = atm.id,
                        label = atm.label,
                        prompt = atm.prompt,
                        signage = atm.signage,
                        camera = atm.camera,
                        fee = atmMeta.fee
                    })
                elseif IsControlJustReleased(0, 74) then
                    TriggerServerEvent('banking:atmRobbery', { x = coords.x, y = coords.y, z = coords.z })
                end
            end
        end
        for _, teller in ipairs(tellerLocations) do
            local coords = vector3(teller.coords.x, teller.coords.y, teller.coords.z)
            local distance = #(playerCoords - coords)
            if distance < 2.0 then
                waitTime = 0
                DrawText3D(vector3(coords.x, coords.y, coords.z + 1.0), teller.prompt or '~g~E~s~ Speak with banker')
                if IsControlJustReleased(0, 38) then
                    openBank('teller', { type = 'teller', label = teller.prompt, id = teller.id })
                end
            end
        end
        Wait(waitTime)
    end
end)
