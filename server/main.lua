local QBX = exports.qbx_core

ST = ST or {}

-- ---------------------------------------------------------------------------
-- Permission helpers
-- ---------------------------------------------------------------------------

--- Returns true if the player's job/grade in `dealershipName` grants `perm`.
--- `perm` is one of the strings listed under Config.Departments[x].perms,
--- or 'all' (owner department automatically passes everything). Works the
--- same for a config/dealerships.lua entry or one created with
--- /newdealership - both resolve through ST.GetDealership (server/registry.lua).
function ST.HasPermission(src, dealershipName, perm)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return false end

    -- Server admins get owner-equivalent access to every dealership,
    -- independent of whether they hold that dealership's job at all.
    if Config.AdminPermission and IsPlayerAceAllowed(src, Config.AdminPermission) then
        return true
    end

    local player = QBX:GetPlayer(src)
    if not player then return false end

    local job = player.PlayerData.job
    if not job or job.name ~= dealership.job then return false end

    for deptKey, dept in pairs(Config.Departments) do
        local hasPerm = false
        for _, p in ipairs(dept.perms) do
            if p == perm or p == 'all' then hasPerm = true break end
        end
        if hasPerm then
            local required = Config.DefaultGradeRequirements[deptKey] or 0
            if job.grade.level >= required then
                return true
            end
        end
    end

    return false
end

--- Notifies every currently-online player who holds `perm` at
--- `dealershipName`. Lives here because financing.lua, financingrequests.lua
--- and transfers.lua each had their own private copy of it.
function ST.NotifyDealershipStaff(dealershipName, perm, notification)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return end

    for playerId, player in pairs(QBX:GetQBPlayers()) do
        if player.PlayerData.job and player.PlayerData.job.name == dealership.job then
            if ST.HasPermission(playerId, dealershipName, perm) then
                TriggerClientEvent('ox_lib:notify', playerId, notification)
            end
        end
    end
end

function ST.GetPlayerCitizenId(src)
    local player = QBX:GetPlayer(src)
    return player and player.PlayerData.citizenid or nil
end

-- ---------------------------------------------------------------------------
-- Dealership account (bank) helpers
-- ---------------------------------------------------------------------------

--- Resolves a dealership's account KEY (what the banking provider stores
--- the balance under). config/dealerships.lua entries can name their own;
--- runtime-created ones use "<name>_bank" (see server/registry.lua).
local function accountKeyFor(dealershipName)
    local dealership = ST.GetDealership(dealershipName)
    return (dealership and dealership.account) or dealershipName
end
ST.AccountKeyFor = accountKeyFor

--- Ensures an account exists for `dealershipName`. Safe to call repeatedly.
function ST.SeedAccount(dealershipName, startingBalance)
    ST.Money.SeedSociety(dealershipName, startingBalance)
end

--- Seeds every known dealership (config + registry). Called once by
--- server/registry.lua after it loads any runtime-created dealerships.
function ST.SeedAllAccounts()
    for name, def in pairs(ST.GetAllDealerships()) do
        ST.SeedAccount(name, def.startingBalance)
    end
    -- Refresh the internal ledger cache after seeding, so the first read
    -- doesn't race money.lua's own startup load.
    ST.Money.LoadInternalBalances()
end

function ST.GetBalance(dealershipName)
    return ST.Money.GetSociety(dealershipName)
end

--- Adjust a dealership's balance by `amount` (positive or negative).
--- Returns false if the change would overdraw and `allowNegative` isn't set.
function ST.AdjustBalance(dealershipName, amount, allowNegative, reason)
    return ST.Money.AdjustSociety(dealershipName, amount, reason, allowNegative)
end

--- Directly sets a dealership's balance to an exact value (as opposed to
--- AdjustBalance's relative +/-). Used by the /admindealership console.
function ST.SetBalance(dealershipName, amount)
    return ST.Money.SetSociety(dealershipName, amount)
end

exports('GetDealership', function(name) return ST.GetDealership(name) end)

-- ---------------------------------------------------------------------------
-- Vehicle history log (server/inventory.lua and others call this)
-- ---------------------------------------------------------------------------

function ST.LogVehicleHistory(vin, event, details)
    MySQL.insert('INSERT INTO st_dealership_vehicle_history (vin, event, details) VALUES (?, ?, ?)',
        { vin, event, json.encode(details or {}) })
end

lib.callback.register('st_dealership:server:hasPermission', function(src, dealershipName, perm)
    return ST.HasPermission(src, dealershipName, perm)
end)

lib.callback.register('st_dealership:server:getDealershipMeta', function(src, dealershipName)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return nil end
    local branding = ST.GetBranding(dealershipName)
    return { label = branding.label, type = dealership.type, balance = ST.GetBalance(dealershipName) }
end)

lib.callback.register('st_dealership:server:getPermissions', function(src, dealershipName)
    local perms = {}
    for _, dept in pairs(Config.Departments) do
        for _, p in ipairs(dept.perms) do
            if p ~= 'all' and not perms[p] then
                perms[p] = ST.HasPermission(src, dealershipName, p)
            end
        end
    end
    perms.all = ST.HasPermission(src, dealershipName, 'all')
    return perms
end)

--- The client needs every dealership that currently exists (config +
--- runtime-created) to build blips/targets and resolve fallback spawn
--- points, without needing a resource restart when a new one is created
--- mid-session (see the 'dealershipCreated' broadcast in server/registry.lua).
lib.callback.register('st_dealership:server:getAllDealerships', function(src)
    local out = {}
    for name, def in pairs(ST.GetAllDealerships()) do
        out[name] = { label = def.label, type = def.type, job = def.job, location = def.location }
    end
    return out
end)

--- Explicit, guaranteed resync path: the client asks for this itself on
--- QBCore:Client:OnPlayerLoaded (client/sync.lua) rather than depending
--- solely on a server-side "player loaded" event whose exact name isn't
--- fully certain across qbx_core versions. Covers zones, lights, and
--- display vehicle assignments for every dealership in one go.
RegisterNetEvent('st_dealership:server:requestFullSync', function()
    local src = source
    for name in pairs(ST.GetAllDealerships()) do
        TriggerClientEvent('st_dealership:client:syncZones', src, name, ST.GetZones(name))
        TriggerClientEvent('st_dealership:client:syncLights', src, name, ST.GetLights(name))
        TriggerClientEvent('st_dealership:client:syncDisplays', src, name, ST.GetDisplayAssignments(name))
    end
end)
