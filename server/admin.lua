local QBX = exports.qbx_core

--- /admindealership is registered client-side, so its `restricted` flag
--- does nothing - this callback check is the real gate for every admin
--- action (set balance, assign owner, delete).
---
--- Grant with:  add_ace group.admin st_dealership.admin allow
local function isAdmin(src)
    return Config.AdminPermission ~= nil and IsPlayerAceAllowed(src, Config.AdminPermission)
end

lib.callback.register('st_dealership:server:isDealershipAdmin', function(src)
    return isAdmin(src)
end)

lib.callback.register('st_dealership:server:adminGetDealerships', function(src)
    if not isAdmin(src) then return {} end

    local out = {}
    for name, def in pairs(ST.GetAllDealerships()) do
        out[#out + 1] = {
            name = name,
            label = def.label,
            type = def.type,
            job = def.job,
            balance = ST.GetBalance(name),
            source = def.fromRegistry and 'registry' or 'config',
        }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

lib.callback.register('st_dealership:server:adminSetBalance', function(src, dealershipName, amount)
    if not isAdmin(src) then return false, 'not_authorized' end
    if not ST.GetDealership(dealershipName) then return false, 'not_found' end

    amount = tonumber(amount)
    if not amount then return false, 'invalid_amount' end

    ST.SetBalance(dealershipName, amount)
    return true
end)

lib.callback.register('st_dealership:server:adminAssignOwner', function(src, dealershipName, targetId)
    if not isAdmin(src) then return false, 'not_authorized' end

    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return false, 'not_found' end

    local targetPlayer = QBX:GetPlayer(tonumber(targetId))
    if not targetPlayer then return false, 'player_offline' end

    local ownerGrade = Config.DefaultGradeRequirements.owner or 4
    local ok, err = exports.qbx_core:SetJob(targetPlayer.PlayerData.citizenid, dealership.job, ownerGrade)
    if not ok then return false, (err and err.message) or 'set_job_failed' end

    return true
end)

--- Only dealerships created with /newdealership can be deleted - one
--- defined in config/dealerships.lua would just reappear on the next
--- restart, so deleting it would be misleading rather than useful.
lib.callback.register('st_dealership:server:adminDeleteDealership', function(src, dealershipName)
    if not isAdmin(src) then return false, 'not_authorized' end

    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return false, 'not_found' end
    if not dealership.fromRegistry then return false, 'cannot_delete_config' end

    local ok, err = pcall(function()
        MySQL.query.await('DELETE FROM st_dealership_registry WHERE name = ?', { dealershipName })
        MySQL.query.await('DELETE FROM st_dealership_zones WHERE dealership = ?', { dealershipName })
        MySQL.query.await('DELETE FROM st_dealership_lights WHERE dealership = ?', { dealershipName })
        MySQL.query.await('DELETE FROM st_dealership_accounts WHERE dealership = ?', { dealershipName })
        MySQL.query.await('DELETE FROM st_dealership_display_assignments WHERE dealership = ?', { dealershipName })
        ST.RemoveFromRegistry(dealershipName)
    end)

    if not ok then
        print(('[st_dealership] /admindealership delete failed for "%s": %s'):format(tostring(dealershipName), tostring(err)))
        return false, 'internal_error'
    end

    -- Inventory, sales contracts, and history for this dealership are left
    -- alone (historical record), and any staff keep their job - they just
    -- won't have a working dealership to use it at anymore. Reassign/fire
    -- them separately (e.g. /setjob) if that matters for your server.
    TriggerClientEvent('st_dealership:client:dealershipDeleted', -1, dealershipName)

    return true
end)
