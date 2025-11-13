local balances = { cash = 0, bank = 0, crypto = 0 }
local history = {}
local favorites = {}
local locale = 'en'
local uiVisible = false
local uiContext = 'command'
local currentIban = ''
local currentTier = 'default'

local ATM_MODELS = {
    -870868698,
    506770882,
    -1364697528,
    -1126237515
}

local ATM_POINTS = {
    vector3(150.266, -1040.203, 29.374),
    vector3(-1212.980, -330.841, 37.787),
    vector3(-2962.582, 482.627, 15.703),
    vector3(314.187, -278.621, 54.170)
}

local TELLERS = {
    { model = `s_m_m_highsec_01`, coords = vector4(148.74, -1042.36, 29.37, 340.0) }
}

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

local function updateUiBalances()
    sendUiMessage({
        action = 'updateBalances',
        data = {
            cash = balances.cash,
            bank = balances.bank,
            crypto = balances.crypto,
            iban = currentIban,
            tier = currentTier
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
            locale = locale
        })
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
    if uiVisible then
        updateUiBalances()
        sendUiMessage({ action = 'updateHistory', entries = history })
    else
        TriggerEvent('chat:addMessage', {
            color = { 0, 200, 120 },
            multiline = true,
            args = { 'Banking', ('Cash: %s | Bank: %s'):format(formatCurrency(balances.cash), formatCurrency(balances.bank)) }
        })
    end
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
end)

RegisterNetEvent('banking:playSound', function(sound)
    if sound then
        PlaySoundFrontend(-1, sound, 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
end)

RegisterNetEvent('banking:promptPin', function()
    showNotification('Enter your PIN via /bankpin <current pin> [new pin] for high-value transfers.', 'info')
end)

local function requestBalance()
    TriggerServerEvent('banking:requestBalance', 'ui')
end

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then
        return
    end
    requestBalance()
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

CreateThread(function()
    for _, data in ipairs(TELLERS) do
        local model = data.model
        RequestModel(model)
        while not HasModelLoaded(model) do
            Wait(0)
        end
        local ped = CreatePed(4, model, data.coords.x, data.coords.y, data.coords.z - 1.0, data.coords.w, false, true)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
    end
end)

CreateThread(function()
    while true do
        local waitTime = 1000
        local playerCoords = GetEntityCoords(PlayerPedId())
        for _, coords in ipairs(ATM_POINTS) do
            local distance = #(playerCoords - coords)
            if distance < 2.0 then
                waitTime = 0
                DrawText3D(vector3(coords.x, coords.y, coords.z + 1.0), '~g~E~s~ Use ATM | ~r~H~s~ Rob')
                if IsControlJustReleased(0, 38) then
                    openBank('atm', { x = coords.x, y = coords.y, z = coords.z })
                elseif IsControlJustReleased(0, 74) then
                    TriggerServerEvent('banking:atmRobbery', { x = coords.x, y = coords.y, z = coords.z })
                end
            end
        end
        for _, teller in ipairs(TELLERS) do
            local coords = vector3(teller.coords.x, teller.coords.y, teller.coords.z)
            local distance = #(playerCoords - coords)
            if distance < 2.0 then
                waitTime = 0
                DrawText3D(vector3(coords.x, coords.y, coords.z + 1.0), '~g~E~s~ Speak with banker')
                if IsControlJustReleased(0, 38) then
                    openBank('teller')
                end
            end
        end
        Wait(waitTime)
    end
end)
