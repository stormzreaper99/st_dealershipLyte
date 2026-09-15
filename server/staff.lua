local QBX = exports.qbx_core

--- Same ace as /newdealership. This command IS registered server-side, so
--- its `restricted` flag works too - this is belt and braces.
---
--- src 0 is the server console, which is always allowed.
local function isServerAdmin(src)
    if src == 0 then return true end
    return IsPlayerAceAllowed(src, 'command.newdealership')
end

--- Bootstraps a dealership's very first owner. Admin-only (same ace as
--- /newdealership) - before an owner exists, nobody else has a way to
--- grant that grade, since ST.HasPermission itself requires already
--- having it. Registered server-side, so `restricted` actually works here
--- (unlike a client-registered command) - this only needs a target player
--- id, not any in-world placement, so there's no reason to run it client-side.
RegisterCommand('dealershipowner', function(src, args)
    if not isServerAdmin(src) then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Dealership', "You don't have permission to do that." } })
        return
    end

    local dealershipName, targetIdArg = args[1], args[2]
    if not dealershipName then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Dealership', 'Usage: /dealershipowner <dealership> [playerId|me] - leave playerId off (or use "me") to make yourself the owner.' } })
        return
    end

    -- No target given, or explicitly "me"/"self" - default to whoever ran
    -- the command, so an admin doesn't need to look up their own player ID.
    if not targetIdArg or targetIdArg:lower() == 'me' or targetIdArg:lower() == 'self' then
        if src == 0 then
            TriggerClientEvent('chat:addMessage', src, { args = { 'Dealership', 'Run from the console? You need to name a player id: /dealershipowner <dealership> <playerId>' } })
            return
        end
        targetIdArg = tostring(src)
    end

    local dealership = ST.GetDealership(dealershipName)
    if not dealership then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Dealership', ('No dealership named "%s".'):format(dealershipName) } })
        return
    end

    local targetId = tonumber(targetIdArg)
    local targetPlayer = targetId and QBX:GetPlayer(targetId)
    if not targetPlayer then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Dealership', 'That player is not online.' } })
        return
    end

    local ownerGrade = Config.DefaultGradeRequirements.owner or 4
    local ok, err = exports.qbx_core:SetJob(targetPlayer.PlayerData.citizenid, dealership.job, ownerGrade)

    if ok then
        TriggerClientEvent('chat:addMessage', src, { args = { 'Dealership', ('%s is now the owner of %s.'):format(GetPlayerName(targetId) or targetIdArg, dealership.label) } })
        TriggerClientEvent('chat:addMessage', targetId, { args = { 'Dealership', ('You are now the owner of %s.'):format(dealership.label) } })
    else
        TriggerClientEvent('chat:addMessage', src, { args = { 'Dealership', 'Could not set that job: ' .. tostring(err and err.message or err or 'unknown error') } })
    end
end, true)

-- ---------------------------------------------------------------------------
-- Ongoing hiring/firing - once a dealership has an owner, they (or anyone
-- with the 'hire'/'fire' perms - Management grade and above) can manage
-- staff themselves from the Dealership Ops NUI tab without needing an
-- admin for every hire.
-- ---------------------------------------------------------------------------

lib.callback.register('st_dealership:server:getOnlineStaff', function(src, dealershipName)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return {} end
    if not ST.HasPermission(src, dealershipName, 'hire') and not ST.HasPermission(src, dealershipName, 'fire') then return {} end

    local staff = {}
    for playerId, player in pairs(QBX:GetQBPlayers()) do
        if player.PlayerData.job and player.PlayerData.job.name == dealership.job then
            staff[#staff + 1] = {
                id = playerId,
                name = GetPlayerName(playerId) or 'Unknown',
                citizenid = player.PlayerData.citizenid,
                grade = player.PlayerData.job.grade.level,
                gradeName = player.PlayerData.job.grade.name,
            }
        end
    end
    return staff
end)

--- `grade` is a raw job grade level (0-4 by default). Management can hire
--- up to (but not including) the Owner grade; only an existing Owner/admin
--- can hire another Owner.
lib.callback.register('st_dealership:server:hireStaff', function(src, dealershipName, targetId, grade)
    if not ST.HasPermission(src, dealershipName, 'hire') then return false, 'no_permission' end

    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return false, 'not_found' end

    local targetPlayer = QBX:GetPlayer(tonumber(targetId))
    if not targetPlayer then return false, 'player_offline' end

    grade = tonumber(grade) or 0
    local ownerGrade = Config.DefaultGradeRequirements.owner or 4
    if grade >= ownerGrade and not ST.HasPermission(src, dealershipName, 'all') then
        return false, 'cannot_hire_owner'
    end

    local ok, err = exports.qbx_core:SetJob(targetPlayer.PlayerData.citizenid, dealership.job, grade)
    if not ok then return false, (err and err.message) or 'set_job_failed' end

    return true
end)

lib.callback.register('st_dealership:server:fireStaff', function(src, dealershipName, targetId)
    if not ST.HasPermission(src, dealershipName, 'fire') then return false, 'no_permission' end

    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return false, 'not_found' end

    local targetPlayer = QBX:GetPlayer(tonumber(targetId))
    if not targetPlayer then return false, 'player_offline' end
    if not targetPlayer.PlayerData.job or targetPlayer.PlayerData.job.name ~= dealership.job then return false, 'not_staff' end

    local ok, err = exports.qbx_core:SetJob(targetPlayer.PlayerData.citizenid, 'unemployed', 0)
    if not ok then return false, (err and err.message) or 'set_job_failed' end

    return true
end)
