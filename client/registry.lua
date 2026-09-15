ST = ST or {}
-- `or {}` rather than a plain reset: client/main.lua declares this too and
-- loads first, so overwriting it here would discard anything its startup
-- thread had already resolved.
ST.RuntimeDealerships = ST.RuntimeDealerships or {} -- name -> { label, type, job, location }

--- Every dealership currently known to this client - config/dealerships.lua
--- entries plus anything created at runtime. client/*.lua should call this
--- instead of reading Config.Dealerships directly, the same rule as server-side.
function ST.ResolveDealership(name)
    return ST.RuntimeDealerships[name] or Config.Dealerships[name]
end

function ST.GetAllDealershipNames()
    local out = {}
    for name in pairs(Config.Dealerships) do out[#out + 1] = name end
    for name in pairs(ST.RuntimeDealerships) do out[#out + 1] = name end
    return out
end

RegisterNetEvent('st_dealership:client:dealershipCreated', function(name, def)
    ST.RuntimeDealerships[name] = def
    if ST.SetupDealershipEntryPoint then
        ST.SetupDealershipEntryPoint(name, def)
    end
end)

-- ---------------------------------------------------------------------------
-- /newdealership - raycast placement for the owner's management PC
-- ---------------------------------------------------------------------------

--- Casts a ray from the camera out to `maxDistance` and returns where it
--- hits world geometry (falls back to the max-range point over open sky).
local function getRaycastGroundPoint(maxDistance)
    local camCoord = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local rad = vector3(math.rad(camRot.x), math.rad(camRot.y), math.rad(camRot.z))
    local direction = vector3(
        -math.sin(rad.z) * math.abs(math.cos(rad.x)),
        math.cos(rad.z) * math.abs(math.cos(rad.x)),
        math.sin(rad.x)
    )
    local destination = camCoord + direction * maxDistance

    local rayHandle = StartShapeTestRay(camCoord.x, camCoord.y, camCoord.z, destination.x, destination.y, destination.z, 1, PlayerPedId(), 0)
    local _, hit, endCoords = GetShapeTestResult(rayHandle)

    if hit == 1 then
        return endCoords
    end
    return destination
end

--- Aim-and-confirm with E, matching the request: point the camera at the
--- floor where the management PC should go, press E to lock it in,
--- Backspace to cancel.
function ST.RunRaycastPlacement()
    lib.showTextUI('[E] confirm this location   [Backspace] cancel')

    local startedAt = GetGameTimer()
    local result

    while true do
        Wait(0)
        local point = getRaycastGroundPoint(50.0)
        DrawMarker(28, point.x, point.y, point.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.4, 0.4, 0.4, 80, 200, 255, 190, false, true, 2, false, nil, nil, false)

        -- Bounded like the other placement tools, so an abandoned
        -- /newdealership can't leave the player in a permanent key loop.
        if (GetGameTimer() - startedAt) > 120000 then
            lib.notify({ title = 'New Dealership', description = 'Placement timed out.', type = 'error' })
            break
        end

        if IsControlJustPressed(0, 38) then -- E
            result = { pos = { x = point.x, y = point.y, z = point.z }, heading = GetEntityHeading(PlayerPedId()) }
            break
        end
        if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then -- Backspace
            break
        end
    end

    lib.hideTextUI()
    return result
end

RegisterCommand('newdealership', function(_, args)
    if #args < 3 then
        lib.notify({ title = 'New Dealership', description = 'Usage: /newdealership <name> <job> <label>', type = 'error' })
        return
    end

    local name, job = args[1], args[2]
    local label = table.concat(args, ' ', 3)

    local ok, reason = lib.callback.await('st_dealership:server:canCreateDealership', false, name, job)
    if not ok then
        lib.notify({ title = 'New Dealership', description = ({
            not_authorized = "You don't have permission to do that.",
            invalid_name = 'Name must be a single word (letters, numbers, - or _ only).',
            name_taken = 'A dealership with that name already exists.',
            invalid_job = 'You need to specify a job name.',
        })[reason] or 'Cannot create that dealership.', type = 'error' })
        return
    end

    lib.notify({ title = 'New Dealership', description = "Aim at the floor where the owner's PC should go and press E.", type = 'inform' })

    local placement = ST.RunRaycastPlacement()
    if not placement then
        lib.notify({ title = 'New Dealership', description = 'Cancelled.', type = 'error' })
        return
    end

    local created, reason = lib.callback.await('st_dealership:server:createDealership', false, {
        name = name, job = job, label = label, type = 'used',
        pos = placement.pos, heading = placement.heading,
    })

    if created then
        lib.notify({ title = 'New Dealership', description = ('%s created. Its owner can finish setup from the PC you just placed.'):format(label), type = 'success' })
    else
        lib.notify({ title = 'New Dealership', description = ({
            not_authorized = "You don't have permission to do that.",
            name_taken = 'A dealership with that name already exists.',
            internal_error = 'Something went wrong on the server - check the server console for details.',
        })[reason] or ('Could not create that dealership (%s).'):format(tostring(reason)), type = 'error' })
    end
-- The `restricted` bool on RegisterCommand does nothing for client-side
-- commands (FiveM ignores it outside server scripts), so it was never
-- what gated this. The real check lives server-side in
-- server/registry.lua's canCreateDealership/createDealership callbacks -
-- but per your request, that check is currently hardcoded to always
-- pass (see the "TEMPORARILY DISABLED" comment there) until you finish
-- setting up ACE permissions. Right now ANY player can run this command.
end, false)

-- Registers /newdealership with the chat resource's `/` autocomplete so it
-- shows up while typing, same as any other slash command. RegisterCommand
-- alone does not populate that dropdown.
CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/newdealership', 'Create a new dealership (admin only)', {
        { name = 'name', help = 'Unique one-word slug, e.g. moto1' },
        { name = 'job', help = 'Existing qbx_core job name for its staff' },
        { name = 'label', help = "Display label, e.g. Stormline Motorcycles" },
    })
    TriggerEvent('chat:addSuggestion', '/dealershipowner', 'Assign a dealership\'s first owner (admin only)', {
        { name = 'dealership', help = 'Dealership slug, e.g. moto1' },
        { name = 'playerId', help = 'Server ID, or "me"/leave blank to make yourself the owner' },
    })
end)
