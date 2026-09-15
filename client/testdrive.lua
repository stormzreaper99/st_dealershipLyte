local TEST_DRIVE_SECONDS = 180
local EXIT_GRACE_MS = 1500 -- ignore the brief "not in vehicle yet" window right after TaskWarpPedIntoVehicle
local activeTestDrive = nil

function ST.IsTestDriveActive()
    return activeTestDrive ~= nil
end

local function pickTestDriveSpawn(dealershipName)
    local dynamic = ST.GetZonesOfType(dealershipName, 'testdrive_spawn')
    if #dynamic > 0 then
        local z = dynamic[math.random(#dynamic)]
        return vector4(z.pos_x, z.pos_y, z.pos_z, z.heading)
    end

    -- Hard-errored before if the name didn't resolve (a deleted or
    -- not-yet-synced dealership).
    local dealership = ST.ResolveDealership(dealershipName)
    local spawns = dealership and dealership.location and dealership.location.spawns
    if spawns and #spawns > 0 then
        local s = spawns[math.random(#spawns)]
        return vector4(s.x, s.y, s.z, s.w)
    end

    return nil
end

function ST.StartTestDrive(dealershipName, vehicle)
    if activeTestDrive then
        lib.notify({ title = 'Test Drive', description = 'You are already on a test drive.', type = 'error' })
        return
    end

    local spawn = pickTestDriveSpawn(dealershipName)
    if not spawn then
        lib.notify({ title = 'Test Drive', description = 'No test drive vehicle available here.', type = 'error' })
        return
    end

    -- Through ST.SpawnVehicle so the car is claimed as a mission entity.
    -- Created bare, it was ambient traffic as far as the engine was
    -- concerned and the population system deleted it within a second.
    local veh, spawnErr = ST.SpawnVehicle(vehicle.model, spawn, spawn.w, {
        plate = 'TESTDRV',
        fuel = 80.0,
    })

    if not veh then
        lib.notify({ title = 'Test Drive', description = ('Could not spawn that vehicle: %s'):format(spawnErr), type = 'error' })
        return
    end

    local ped = PlayerPedId()
    TaskWarpPedIntoVehicle(ped, veh, -1)
    ST.GiveKeysForVehicle(veh)

    activeTestDrive = { vehicle = veh, dealership = dealershipName, startedAt = GetGameTimer() }

    lib.notify({ title = 'Test Drive Started', description = ('You have %d minutes. Get out of the vehicle at any point to end it early.'):format(TEST_DRIVE_SECONDS / 60), type = 'inform' })

    -- Countdown / timeout
    CreateThread(function()
        local remaining = TEST_DRIVE_SECONDS
        while activeTestDrive and activeTestDrive.vehicle == veh and remaining > 0 do
            Wait(1000)
            remaining = remaining - 1
            if remaining == 30 and activeTestDrive then
                lib.notify({ title = 'Test Drive', description = '30 seconds remaining.', type = 'inform' })
            end
        end
        if activeTestDrive and activeTestDrive.vehicle == veh then
            ST.EndTestDrive('timed_out')
        end
    end)

    -- Exit monitor - the moment the player is no longer in this specific
    -- vehicle (got out, got thrown out, vehicle got destroyed, etc), the
    -- test drive ends immediately: no grace period once driving has begun,
    -- only right at the very start so the warp-in itself isn't mistaken
    -- for "already got out".
    CreateThread(function()
        Wait(EXIT_GRACE_MS)
        while activeTestDrive and activeTestDrive.vehicle == veh do
            Wait(250)
            if GetVehiclePedIsIn(PlayerPedId(), false) ~= veh then
                if activeTestDrive and activeTestDrive.vehicle == veh then
                    ST.EndTestDrive('exited_vehicle')
                end
                break
            end
        end
    end)
end

function ST.EndTestDrive(reason)
    if not activeTestDrive then return end

    local veh = activeTestDrive.vehicle
    if DoesEntityExist(veh) then
        ST.RemoveKeysForVehicle(veh)
        DeleteEntity(veh)
    end

    local messages = {
        timed_out = 'Time expired - vehicle returned.',
        exited_vehicle = 'Test drive ended - you got out of the vehicle.',
        manual = 'Vehicle returned to the lot.',
    }

    lib.notify({ title = 'Test Drive Ended', description = messages[reason] or messages.manual, type = 'inform' })

    activeTestDrive = nil
end

RegisterCommand('returntestdrive', function()
    if activeTestDrive then ST.EndTestDrive('manual') end
end, false)
