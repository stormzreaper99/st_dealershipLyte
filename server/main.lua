local QBX = exports.qbx_core
ST = ST or {}

function ST.HasPermission(src, dealershipName, perm)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return false end
    if Config.AdminPermission and IsPlayerAceAllowed(src, Config.AdminPermission) then return true end
    local player = QBX:GetPlayer(src)
    if not player then return false end
    local job = player.PlayerData.job
    if not job or job.name ~= dealership.job then return false end

    for deptKey, dept in pairs(Config.Departments) do
        local hasPerm = false
        for _, p in ipairs(dept.perms) do
            if p == perm or p == 'all' then hasPerm = true break end
        end
        if hasPerm and job.grade.level >= (Config.DefaultGradeRequirements[deptKey] or 0) then return true end
    end
    return false
end

function ST.NotifyDealershipStaff(dealershipName, perm, notification)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return end
    for playerId, player in pairs(QBX:GetQBPlayers()) do
        if player.PlayerData.job and player.PlayerData.job.name == dealership.job
            and ST.HasPermission(playerId, dealershipName, perm) then
            TriggerClientEvent('ox_lib:notify', playerId, notification)
        end
    end
end

function ST.GetPlayerCitizenId(src)
    local player = QBX:GetPlayer(src)
    return player and player.PlayerData.citizenid or nil
end

function ST.SeedAccount(dealershipName, startingBalance) ST.Money.SeedSociety(dealershipName, startingBalance) end
function ST.SeedAllAccounts()
    for name, def in pairs(ST.GetAllDealerships()) do ST.SeedAccount(name, def.startingBalance) end
    ST.Money.LoadInternalBalances()
end
function ST.GetBalance(dealershipName) return ST.Money.GetSociety(dealershipName) end
function ST.AdjustBalance(dealershipName, amount, allowNegative, reason) return ST.Money.AdjustSociety(dealershipName, amount, reason, allowNegative) end
function ST.SetBalance(dealershipName, amount) return ST.Money.SetSociety(dealershipName, amount) end
exports('GetDealership', function(name) return ST.GetDealership(name) end)

function ST.LogVehicleHistory(vin, event, details)
    MySQL.insert('INSERT INTO st_dealership_vehicle_history (vin, event, details) VALUES (?, ?, ?)', { vin, event, json.encode(details or {}) })
end

lib.callback.register('st_dealership:server:hasPermission', function(src, dealershipName, perm)
    return ST.HasPermission(src, dealershipName, perm)
end)

lib.callback.register('st_dealership:server:getDealershipMeta', function(src, dealershipName)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return nil end
    local branding = ST.GetBranding(dealershipName)
    return { label = branding.label, type = dealership.type, balance = ST.GetBalance(dealershipName), theme = branding.theme }
end)

lib.callback.register('st_dealership:server:getPermissions', function(src, dealershipName)
    local perms = {}
    for _, dept in pairs(Config.Departments) do
        for _, p in ipairs(dept.perms) do
            if p ~= 'all' and not perms[p] then perms[p] = ST.HasPermission(src, dealershipName, p) end
        end
    end
    perms.all = ST.HasPermission(src, dealershipName, 'all')
    return perms
end)

lib.callback.register('st_dealership:server:getAllDealerships', function(src)
    local out = {}
    for name, def in pairs(ST.GetAllDealerships()) do
        out[name] = { label = def.label, type = def.type, job = def.job, location = def.location }
    end
    return out
end)

RegisterNetEvent('st_dealership:server:requestFullSync', function()
    local src = source
    for name in pairs(ST.GetAllDealerships()) do
        TriggerClientEvent('st_dealership:client:syncZones', src, name, ST.GetZones(name))
        TriggerClientEvent('st_dealership:client:syncDisplays', src, name, ST.GetDisplayAssignments(name))
    end
end)
