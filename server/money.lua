-- ---------------------------------------------------------------------------
-- MONEY BRIDGE
--
-- Two separate concerns live in here:
--
--   1. PLAYER money (cash/bank). On Qbox/QBCore this always belongs to the
--      core, never to the banking script - Renewed-Banking, qb-banking,
--      okokBanking etc. all read and write the core's money. So player
--      money goes through qbx_core's documented exports, with a fallback
--      to the legacy Player.Functions API for older cores.
--
--   2. DEALERSHIP (society/business) accounts. This one genuinely differs
--      per banking script, so it's bridged. Auto-detection picks the first
--      running provider in Config.Money.providerPriority; set
--      Config.Money.societyProvider to force one.
--
-- Every bridged call is pcall-guarded: if a provider's export signature
-- doesn't match what's here (they do change between versions), the call
-- fails soft, gets logged once, and the internal table takes over rather
-- than silently losing money.
-- ---------------------------------------------------------------------------

local QBX = exports.qbx_core

ST = ST or {}
ST.Money = {}

-- ---------------------------------------------------------------------------
-- Player money
-- ---------------------------------------------------------------------------

--- `identifier` is a server id OR a citizenid - qbx_core accepts both.
local function resolvePlayer(identifier)
    if type(identifier) == 'number' then
        return QBX:GetPlayer(identifier)
    end
    return QBX:GetPlayerByCitizenId(identifier)
end

function ST.Money.GetPlayerBalance(identifier, account)
    local player = resolvePlayer(identifier)
    if not player then return 0 end
    return tonumber(player.PlayerData.money[account or Config.Money.playerAccount]) or 0
end

--- Returns true only if the money actually moved.
function ST.Money.AddPlayer(identifier, amount, reason, account)
    if not amount or amount <= 0 then return false end
    account = account or Config.Money.playerAccount

    local ok, result = pcall(function()
        return QBX:AddMoney(identifier, account, math.floor(amount + 0.5), reason or 'st_dealership')
    end)
    if ok and result then return true end

    -- Legacy core fallback
    local player = resolvePlayer(identifier)
    if player and player.Functions and player.Functions.AddMoney then
        return player.Functions.AddMoney(account, math.floor(amount + 0.5), reason or 'st_dealership') ~= false
    end
    return false
end

--- Removes `amount` from the player. Tries Config.Money.playerAccount first,
--- then the accounts listed in Config.Money.fallbackAccounts (so a customer
--- with the money in cash rather than bank isn't wrongly refused).
--- Returns success, accountUsed.
function ST.Money.RemovePlayer(identifier, amount, reason, account)
    if not amount or amount <= 0 then return true, nil end
    amount = math.floor(amount + 0.5)

    local order = {}
    if account then
        order[#order + 1] = account
    else
        order[#order + 1] = Config.Money.playerAccount
        for _, acc in ipairs(Config.Money.fallbackAccounts or {}) do
            if acc ~= Config.Money.playerAccount then order[#order + 1] = acc end
        end
    end

    for _, acc in ipairs(order) do
        if ST.Money.GetPlayerBalance(identifier, acc) >= amount then
            local ok, result = pcall(function()
                return QBX:RemoveMoney(identifier, acc, amount, reason or 'st_dealership')
            end)
            if ok and result then return true, acc end

            local player = resolvePlayer(identifier)
            if player and player.Functions and player.Functions.RemoveMoney then
                if player.Functions.RemoveMoney(acc, amount, reason or 'st_dealership') ~= false then
                    return true, acc
                end
            end
        end
    end

    return false, nil
end

--- Deliberately not a sum-across-accounts check: RemovePlayer only ever
--- draws from ONE account, so "can afford" means one account covers it.
function ST.Money.CanPlayerAfford(identifier, amount)
    if not amount or amount <= 0 then return true end
    local best = ST.Money.GetPlayerBalance(identifier, Config.Money.playerAccount)
    for _, acc in ipairs(Config.Money.fallbackAccounts or {}) do
        best = math.max(best, ST.Money.GetPlayerBalance(identifier, acc))
    end
    return best >= math.floor(amount + 0.5)
end

-- ---------------------------------------------------------------------------
-- Dealership (society) accounts
-- ---------------------------------------------------------------------------

local warned = {}
local function warnOnce(key, msg)
    if warned[key] then return end
    warned[key] = true
    print(('[st_dealership] %s'):format(msg))
end

--- Each provider implements get/add/remove against an EXTERNAL account
--- name - the dealership's `account` field from config/dealerships.lua,
--- or "<name>_bank" for runtime-created ones. All return nil/false on
--- failure so the caller can fall through to the internal ledger.
---
--- Note the internal ledger stays keyed on the dealership NAME (which is
--- what st_dealership_accounts has always used, and what
--- server/admin.lua's delete still cleans up), while providers are keyed
--- on the external account name. Mixing the two would have silently
--- orphaned every existing balance on upgrade.
local providers = {}

providers['Renewed-Banking'] = {
    resource = 'Renewed-Banking',
    get = function(account)
        return tonumber(exports['Renewed-Banking']:getAccountMoney(account))
    end,
    add = function(account, amount, reason)
        exports['Renewed-Banking']:addAccountMoney(account, amount)
        return true
    end,
    remove = function(account, amount, reason)
        exports['Renewed-Banking']:removeAccountMoney(account, amount)
        return true
    end,
}

providers['qb-banking'] = {
    resource = 'qb-banking',
    get = function(account)
        return tonumber(exports['qb-banking']:GetAccountBalance(account))
    end,
    add = function(account, amount, reason)
        return exports['qb-banking']:AddMoney(account, amount, reason) ~= false
    end,
    remove = function(account, amount, reason)
        return exports['qb-banking']:RemoveMoney(account, amount, reason) ~= false
    end,
}

providers['qb-management'] = {
    resource = 'qb-management',
    get = function(account)
        return tonumber(exports['qb-management']:GetAccount(account))
    end,
    add = function(account, amount)
        exports['qb-management']:AddMoney(account, amount)
        return true
    end,
    remove = function(account, amount)
        exports['qb-management']:RemoveMoney(account, amount)
        return true
    end,
}

providers['okokBanking'] = {
    resource = 'okokBanking',
    get = function(account)
        return tonumber(exports['okokBanking']:GetAccount(account))
    end,
    add = function(account, amount)
        exports['okokBanking']:AddMoney(account, amount)
        return true
    end,
    remove = function(account, amount)
        exports['okokBanking']:RemoveMoney(account, amount)
        return true
    end,
}

providers['fd_banking'] = {
    resource = 'fd_banking',
    get = function(account)
        return tonumber(exports.fd_banking:GetAccount(account))
    end,
    add = function(account, amount, reason)
        exports.fd_banking:AddMoney(account, amount, reason)
        return true
    end,
    remove = function(account, amount, reason)
        exports.fd_banking:RemoveMoney(account, amount, reason)
        return true
    end,
}

local activeProvider = nil    -- nil = internal st_dealership_accounts table
local activeProviderName = 'internal'

local function detectProvider()
    local forced = Config.Money.societyProvider
    if forced and forced ~= 'auto' then
        if forced == 'internal' then return nil, 'internal' end
        local p = providers[forced]
        if p and GetResourceState(p.resource) == 'started' then return p, forced end
        print(('[st_dealership] Config.Money.societyProvider is "%s" but that resource is not started - falling back to the internal account ledger.'):format(tostring(forced)))
        return nil, 'internal'
    end

    for _, name in ipairs(Config.Money.providerPriority or {}) do
        local p = providers[name]
        if p and GetResourceState(p.resource) == 'started' then return p, name end
    end
    return nil, 'internal'
end

function ST.Money.GetProviderName()
    return activeProviderName
end

-- Internal ledger (the original st_dealership_accounts behaviour) --------------

local balanceCache = {}

local function internalGet(account)
    return balanceCache[account] or 0
end

local function internalSet(account, amount)
    balanceCache[account] = amount
    MySQL.insert('INSERT INTO st_dealership_accounts (dealership, balance) VALUES (?, ?) '
        .. 'ON DUPLICATE KEY UPDATE balance = VALUES(balance)', { account, amount })
end

function ST.Money.LoadInternalBalances()
    local rows = MySQL.query.await('SELECT dealership, balance FROM st_dealership_accounts') or {}
    for _, row in ipairs(rows) do
        balanceCache[row.dealership] = tonumber(row.balance)
    end
end

-- Public society API ----------------------------------------------------------

--- `dealershipName` throughout: the external account key is resolved from
--- it via ST.AccountKeyFor (server/main.lua) only where a provider needs it.
function ST.Money.GetSociety(dealershipName)
    if activeProvider then
        local ok, value = pcall(activeProvider.get, ST.AccountKeyFor(dealershipName))
        if ok and value then return value end
        warnOnce('get_' .. activeProviderName,
            ('society balance lookup via "%s" failed - using the internal ledger instead. Check that provider\'s export signature.'):format(activeProviderName))
    end
    return internalGet(dealershipName)
end

--- Returns true if the money moved. `allowNegative` lets the dealership
--- overdraw (used for acquisitions in flight).
function ST.Money.AdjustSociety(dealershipName, amount, reason, allowNegative)
    amount = math.floor(tonumber(amount) or 0)
    if amount == 0 then return true end

    local current = ST.Money.GetSociety(dealershipName)
    if amount < 0 and (current + amount) < 0 and not allowNegative then
        return false
    end

    if activeProvider then
        local fn = amount > 0 and activeProvider.add or activeProvider.remove
        local ok, result = pcall(fn, ST.AccountKeyFor(dealershipName), math.abs(amount), reason or 'st_dealership')
        if ok and result ~= false then
            return true
        end
        warnOnce('adjust_' .. activeProviderName,
            ('society balance write via "%s" failed - using the internal ledger instead. Check that provider\'s export signature.'):format(activeProviderName))
    end

    internalSet(dealershipName, current + amount)
    return true
end

function ST.Money.SetSociety(dealershipName, amount)
    amount = math.floor(tonumber(amount) or 0)
    if activeProvider then
        local current = ST.Money.GetSociety(dealershipName)
        local delta = amount - current
        if delta ~= 0 then
            return ST.Money.AdjustSociety(dealershipName, delta, 'admin-set-balance', true)
        end
        return true
    end
    internalSet(dealershipName, amount)
    return true
end

--- Creates the internal ledger row if it doesn't exist yet. Provider-backed
--- accounts are expected to be created in that provider's own config.
function ST.Money.SeedSociety(dealershipName, startingBalance)
    MySQL.insert('INSERT INTO st_dealership_accounts (dealership, balance) VALUES (?, ?) '
        .. 'ON DUPLICATE KEY UPDATE dealership = dealership', { dealershipName, startingBalance or 0 })
    if balanceCache[dealershipName] == nil then
        balanceCache[dealershipName] = tonumber(startingBalance) or 0
    end
end

CreateThread(function()
    -- One tick so every other resource has finished starting before we probe.
    Wait(0)
    activeProvider, activeProviderName = detectProvider()
    ST.Money.LoadInternalBalances()
    print(('[st_dealership] money bridge: player money via qbx_core, dealership accounts via "%s"'):format(activeProviderName))
end)
