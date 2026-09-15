local registryCache = {} -- name -> normalized dealership def, same shape as Config.Dealerships entries

local function normalizeRow(row)
    return {
        label = row.label,
        type = row.type,
        job = row.job,
        account = row.name .. '_bank',
        startingBalance = tonumber(row.starting_balance) or 0,
        fromRegistry = true,
        location = {
            blip = { x = row.pos_x, y = row.pos_y, z = row.pos_z, sprite = row.blip_sprite, color = row.blip_color, scale = row.blip_scale },
            showroom = { x = row.pos_x, y = row.pos_y, z = row.pos_z },
            spawns = {}, -- populated at runtime via testdrive_spawn/purchase_spawn zones the owner sets up
            testDriveReturn = nil,
        },
        rules = { marginTarget = 0.18, requiresInspectionBeforeSale = true, reputationWeight = { pricing = 1.0, honesty = 1.0, quality = 1.0 } },
    }
end

--- Single source of truth for "does this dealership exist and what does it
--- look like" - checks runtime-created dealerships first, then falls back
--- to the static config/dealerships.lua entries. Every other server file
--- should call this instead of reading Config.Dealerships directly.
function ST.GetDealership(name)
    return registryCache[name] or Config.Dealerships[name]
end

function ST.GetAllDealerships()
    local out = {}
    for name, def in pairs(Config.Dealerships) do out[name] = def end
    for name, def in pairs(registryCache) do out[name] = def end
    return out
end

--- Removes a runtime-created dealership from the in-memory cache. Only
--- called after its DB rows are already gone (see adminDeleteDealership in
--- server/admin.lua) - never touches config/dealerships.lua entries, which
--- aren't in this cache to begin with.
function ST.RemoveFromRegistry(name)
    registryCache[name] = nil
end

local function loadRegistry()
    local rows = MySQL.query.await('SELECT * FROM st_dealership_registry') or {}
    for _, row in ipairs(rows) do
        registryCache[row.name] = normalizeRow(row)
    end
end

--- IsPlayerAceAllowed is checked here (not just the command's `restricted`
--- flag) so a modified client can't reach dealership creation by calling
--- the callback directly. /newdealership is registered client-side, where
--- `restricted` does nothing at all, so this IS the only real gate.
---
--- Grant with:  add_ace group.admin command.newdealership allow
local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'command.newdealership')
end

lib.callback.register('st_dealership:server:canCreateDealership', function(src, name, job)
    if not isAdmin(src) then return false, 'not_authorized' end
    if not name or name == '' or name:match('%s') or name:match('[^%w_%-]') then return false, 'invalid_name' end
    if ST.GetDealership(name) then return false, 'name_taken' end
    if not job or job == '' then return false, 'invalid_job' end
    return true
end)

lib.callback.register('st_dealership:server:createDealership', function(src, data)
    if not isAdmin(src) then return false, 'not_authorized' end
    if not data or not data.name or ST.GetDealership(data.name) then return false, 'name_taken' end

    local ok, err = pcall(function()
        MySQL.insert.await([[
            INSERT INTO st_dealership_registry
                (name, label, type, job, blip_sprite, blip_color, blip_scale, pos_x, pos_y, pos_z, heading, starting_balance, created_by)
            VALUES (?, ?, ?, ?, 225, 3, 0.8, ?, ?, ?, ?, ?, ?)
        ]], {
            data.name, data.label, data.type or 'used', data.job,
            data.pos.x, data.pos.y, data.pos.z, data.heading or 0.0,
            data.startingBalance or 25000, ST.GetPlayerCitizenId(src),
        })

        local row = MySQL.single.await('SELECT * FROM st_dealership_registry WHERE name = ?', { data.name })
        if not row then
            error('insert succeeded but the row was not found on read-back for name "' .. tostring(data.name) .. '"')
        end
        registryCache[data.name] = normalizeRow(row)

        -- Register the management PC at the exact spot the admin just placed,
        -- so the owner's Dashboard target exists immediately - they don't have
        -- to add it themselves in Settings before the dealership is usable.
        MySQL.insert([[
            INSERT INTO st_dealership_zones (dealership, zone_type, shape, label, pos_x, pos_y, pos_z, heading)
            VALUES (?, 'management_pc', 'point', "Owner's PC", ?, ?, ?, ?)
        ]], { data.name, data.pos.x, data.pos.y, data.pos.z, data.heading or 0.0 })

        ST.SeedAccount(data.name, data.startingBalance or 25000)

        -- Create the qbx_core job to go with it. Without this the
        -- dealership exists but nobody can ever hold its job, so
        -- /dealershipowner silently fails later.
        local runtimeOk, fileResult = ST.CreateDealershipJob(data.job, data.label)
        if not runtimeOk then
            print(('[st_dealership] job "%s" could not be registered at runtime (file layer: %s) - create it manually in qbx_core/shared/jobs.lua'):format(tostring(data.job), tostring(fileResult)))
        end

        TriggerClientEvent('st_dealership:client:dealershipCreated', -1, data.name, {
            label = registryCache[data.name].label, type = registryCache[data.name].type,
            job = registryCache[data.name].job, location = registryCache[data.name].location,
        })
        TriggerClientEvent('st_dealership:client:syncZones', -1, data.name, ST.GetZones(data.name))
    end)

    if not ok then
        -- pcall caught a real error (bad query, missing table, MySQL
        -- rejecting the insert, etc) - print the actual reason to the
        -- server console instead of letting it fail silently, and roll
        -- back the in-memory cache entry so a retry isn't blocked by a
        -- half-created dealership.
        registryCache[data.name] = nil
        print(('[st_dealership] /newdealership failed for "%s": %s'):format(tostring(data.name), tostring(err)))
        return false, 'internal_error'
    end

    return true
end)

CreateThread(function()
    loadRegistry()
    ST.SeedAllAccounts()

    local configCount, registryCount = 0, 0
    for _ in pairs(Config.Dealerships) do configCount = configCount + 1 end
    for _ in pairs(registryCache) do registryCount = registryCount + 1 end
    print(('[st_dealership] loaded %d config dealership(s), %d registry dealership(s)'):format(configCount, registryCount))
end)
