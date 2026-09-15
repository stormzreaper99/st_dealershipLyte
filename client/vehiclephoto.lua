-- ---------------------------------------------------------------------------
-- VEHICLE PREVIEW PHOTOS
--
-- Three things were wrong with the old version of this flow, and they
-- compounded into "press Enter, nothing happens, and the car stays there":
--
--   1. The callback handed to screenshot-basic called lib.callback.await
--      inside itself. That callback is a cross-resource function reference,
--      so screenshot-basic invokes it across a C-call boundary - yielding
--      in there throws "attempt to yield across a C-call boundary". The
--      error killed the callback before it reached cleanup(), which is why
--      the spawned car was left sitting in the world. Everything that
--      yields now runs in its own thread.
--
--   2. The options argument was being skipped "because it breaks the call".
--      It doesn't - the documented signature really is
--      requestScreenshot(options?, cb) / requestScreenshotUpload(url,
--      field, options?, cb). Skipping it meant every capture used the
--      default encoding and 0.92 quality, which matters a lot for (3).
--
--   3. With no webhook configured the photo is a base64 data URI of the
--      whole screen, sent to the server through a callback event. A
--      full-quality 1080p PNG/JPG data URI runs well past FiveM's net
--      event size limit, so the save silently went nowhere. The encoding
--      and quality from config are applied now, and anything still too
--      large is refused with a message that actually explains the fix
--      instead of failing quietly.
-- ---------------------------------------------------------------------------

-- Tracked at module scope so a resource stop can't strand a photo car in
-- the world the way an errored callback used to.
local activePhotoVehicle = nil

local function deletePhotoVehicle(veh)
    ST.DeleteVehicle(veh)
end

--- One screenshot attempt. `cb(dataOrNil, errorReason)`.
---
--- `cb` is always invoked from a fresh thread, so callers are free to
--- yield (lib.callback.await, Wait, etc) inside it - see the note at the
--- top of this file about the C-call boundary.
local function requestOnce(encoding, quality, cb)
    local function finish(data, reason)
        CreateThread(function() cb(data, reason) end)
    end

    if GetResourceState('screenshot-basic') ~= 'started' then
        finish(nil, 'screenshot-basic is not running - this feature needs it installed and started.')
        return
    end

    local options = { encoding = encoding, quality = quality }

    local ok, err = pcall(function()
        if Config.VehiclePhotos.webhookUrl then
            exports['screenshot-basic']:requestScreenshotUpload(
                Config.VehiclePhotos.webhookUrl, 'files[]', options,
                function(data)
                    local decoded, resp = pcall(json.decode, data)
                    local url = decoded and resp and (
                        (resp.attachments and resp.attachments[1] and resp.attachments[1].url) or
                        (resp.files and resp.files[1] and resp.files[1].url) or
                        resp.url
                    )
                    finish(url, url and nil or 'The upload target did not return an image URL.')
                end)
        else
            exports['screenshot-basic']:requestScreenshot(options, function(dataUri)
                finish(dataUri, dataUri and nil or 'The capture returned no image data.')
            end)
        end
    end)

    if not ok then
        finish(nil, 'screenshot-basic rejected the capture request: ' .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Downscaling
--
-- screenshot-basic only exposes encoding and quality - it always captures
-- at the player's native resolution. That's the real reason these photos
-- are oversized: on a 1440p or 4K client, no quality setting on the ladder
-- below gets a full-resolution frame under the event limit, and a quality
-- low enough to manage it looks awful on a 1080p client.
--
-- Resizing needs an image decoder. Lua has none; the NUI page does. The
-- capture is handed to the page, drawn into a canvas at a bounded width,
-- re-encoded as JPEG, and handed back - so the stored photo comes out the
-- same modest size for every player whatever their monitor is.
-- ---------------------------------------------------------------------------
local pendingDownscale = nil

RegisterNUICallback('photoDownscaled', function(data, cb)
    cb('ok')
    local p = pendingDownscale
    if not p then return end
    pendingDownscale = nil
    p:resolve(data)
end)

--- Returns the resized data URI, or nil plus a reason. Safe to call with
--- the interface hidden: the NUI page stays loaded, and its fetch back to
--- Lua doesn't need focus.
local function downscalePhoto(dataUri)
    local p = promise.new()
    pendingDownscale = p

    SendNUIMessage({
        action = 'downscalePhoto',
        data = {
            dataUri = dataUri,
            maxWidth = Config.VehiclePhotos.maxWidth or 960,
            quality = Config.VehiclePhotos.quality or 0.6,
        },
    })

    -- The page could be mid-reload, or the frame could fail to decode -
    -- never block the capture path waiting on it.
    SetTimeout(10000, function()
        if pendingDownscale == p then
            pendingDownscale = nil
            p:resolve(nil)
        end
    end)

    local result = Citizen.Await(p)

    if not result then return nil, 'resize timed out' end
    if result.error then return nil, tostring(result.error) end
    if not result.dataUri then return nil, 'resize returned nothing' end

    return result.dataUri
end

--- Captures a photo that actually fits down the wire.
---
--- With a webhook configured only a short URL crosses the wire, so the
--- first attempt is taken as-is. Without one the image travels to the
--- server as a base64 data URI inside a callback event, and FiveM caps
--- how large an event can be - so this walks Config.VehiclePhotos.
--- qualityLadder downwards, re-capturing until the result fits the
--- budget. The car and the player are both still posed at this point, so
--- a retry photographs exactly the same shot, just compressed harder.
---
--- Refusing outright (what it did before) was the wrong call: the answer
--- to "too big" is a smaller picture, not no picture.
local function captureScreenshot(cb)
    local encoding = Config.VehiclePhotos.encoding or 'webp'
    local ladder = Config.VehiclePhotos.qualityLadder or { 0.6, 0.4, 0.25, 0.15, 0.08 }
    local limit = Config.VehiclePhotos.maxDataUriBytes or 150000

    -- Webhook path: size is not our problem, take the configured quality.
    if Config.VehiclePhotos.webhookUrl then
        requestOnce(encoding, Config.VehiclePhotos.quality or ladder[1], cb)
        return
    end

    CreateThread(function()
        local lastReason, smallest, smallestSize

        -- Turns itself off after one failure rather than paying the resize
        -- timeout again on every rung of the ladder.
        local canResize = Config.VehiclePhotos.downscale ~= false

        for attempt, quality in ipairs(ladder) do
            local done, result, reason = false, nil, nil

            requestOnce(encoding, quality, function(data, err)
                result, reason, done = data, err, true
            end)

            -- requestOnce hands back through a thread, so wait for it.
            local waited = 0
            while not done and waited < 15000 do
                Wait(50)
                waited = waited + 50
            end

            if not done then
                cb(nil, 'The capture did not respond in time.')
                return
            end

            if not result then
                lastReason = reason
                break -- a hard failure won't fix itself at lower quality
            end

            -- Resize BEFORE measuring. Pixel count is what actually blows
            -- the budget, so this usually gets the very first attempt under
            -- the limit and the ladder is never needed at all.
            if canResize then
                local resized, resizeErr = downscalePhoto(result)
                if resized then
                    result = resized
                else
                    canResize = false
                    print(('[st_dealership] photo resize unavailable (%s) - falling back to quality reduction only'):format(tostring(resizeErr)))
                end
            end

            if #result <= limit then
                if attempt > 1 then
                    lib.notify({
                        title = 'Vehicle Photo',
                        description = ('Saved at reduced quality (%d%%) to fit the size limit.'):format(math.floor(quality * 100)),
                        type = 'inform',
                    })
                end
                cb(result, nil)
                return
            end

            if not smallestSize or #result < smallestSize then
                smallest, smallestSize = result, #result
            end
        end

        if lastReason then
            cb(nil, lastReason)
            return
        end

        cb(nil, ('Even resized and at the lowest quality this photo is %dKB, over the %dKB limit. Lower Config.VehiclePhotos.maxWidth, or set webhookUrl to upload photos instead - that removes the limit entirely.')
            :format(math.floor((smallestSize or 0) / 1024), math.floor(limit / 1024)))
    end)
end

--- Office zones are polygons, but the server stores a centroid in
--- pos_x/y/z for every zone shape (see server/zones.lua createZone), so
--- this is a valid point to teleport back to even for a poly zone.
--- Falls back to wherever the player was standing when the shoot started,
--- so a dealership with no office zone doesn't leave them on the photo pad.
local function returnPlayer(dealershipName, fallbackCoords, fallbackHeading)
    local offices = ST.GetZonesOfType(dealershipName, 'office')
    if #offices > 0 then
        local o = offices[1]
        SetEntityCoords(PlayerPedId(), o.pos_x, o.pos_y, o.pos_z, false, false, false, true)
        return
    end
    if fallbackCoords then
        SetEntityCoords(PlayerPedId(), fallbackCoords.x, fallbackCoords.y, fallbackCoords.z, false, false, false, true)
        if fallbackHeading then SetEntityHeading(PlayerPedId(), fallbackHeading) end
    end
end

--- The full photo-shoot flow: teleport to the ped spawn, spawn the car at
--- the car spawn, force first-person, wait for Enter (capture) or
--- Backspace (cancel), clean up, and return to the office either way.
function ST.StartVehiclePhotoShoot(dealershipName, vin, model)
    local pedSpawns = ST.GetZonesOfType(dealershipName, 'photo_ped_spawn')
    local carSpawns = ST.GetZonesOfType(dealershipName, 'photo_car_spawn')

    if #pedSpawns == 0 or #carSpawns == 0 then
        lib.notify({ title = 'Vehicle Photo', description = 'Set up a Preview Photo Ped Spawn and Preview Photo Car Spawn zone in Settings first.', type = 'error' })
        return
    end

    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)

    local ped = PlayerPedId()
    local originCoords = GetEntityCoords(ped)
    local originHeading = GetEntityHeading(ped)

    local pedSpot = pedSpawns[1]
    local carSpot = carSpawns[math.random(#carSpawns)]

    SetEntityCoords(ped, pedSpot.pos_x, pedSpot.pos_y, pedSpot.pos_z, false, false, false, true)
    SetEntityHeading(ped, pedSpot.heading)

    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
        lib.notify({ title = 'Vehicle Photo', description = ('"%s" is not a vehicle model this client has.'):format(tostring(model)), type = 'error' })
        SetNuiFocus(true, true)
        ST.OpenDealershipUI(dealershipName, 'ops')
        return
    end

    local veh, spawnErr = ST.SpawnVehicle(hash,
        { x = carSpot.pos_x, y = carSpot.pos_y, z = carSpot.pos_z }, carSpot.heading, {
            networked = false,
            frozen = true,
            invincible = true,
        })

    if not veh then
        lib.notify({ title = 'Vehicle Photo', description = ('Could not spawn that vehicle: %s'):format(tostring(spawnErr)), type = 'error' })
        SetNuiFocus(true, true)
        ST.OpenDealershipUI(dealershipName, 'ops')
        return
    end

    activePhotoVehicle = veh

    local originalCamMode = GetFollowPedCamViewMode()
    SetFollowPedCamViewMode(4) -- force first person for the shot

    lib.showTextUI('[Enter] Capture photo   [Backspace] Cancel')

    -- Guaranteed to run exactly once no matter what happens (success,
    -- cancel, or an unexpected error anywhere in the capture/upload
    -- pipeline) - a vehicle spawned for a photo should never be able to
    -- get permanently stuck in the world again.
    local cleanedUp = false
    local function cleanup()
        if cleanedUp then return end
        cleanedUp = true

        pcall(lib.hideTextUI)
        SetFollowPedCamViewMode(originalCamMode)
        deletePhotoVehicle(veh)
        activePhotoVehicle = nil
        returnPlayer(dealershipName, originCoords, originHeading)
        SetNuiFocus(true, true)
        ST.OpenDealershipUI(dealershipName, 'ops')
    end

    CreateThread(function()
        local cancelled = false

        -- Composing the shot is deliberately untimed. The old 30s watchdog
        -- started here rather than at capture, so spending longer than that
        -- lining up a shot deleted the car and reopened the menu mid-pose -
        -- and any Enter pressed afterwards did nothing at all.
        while true do
            Wait(0)
            DisableControlAction(0, 24, true) -- attack
            DisableControlAction(0, 25, true) -- aim

            if not DoesEntityExist(veh) then
                -- Car vanished from under us somehow; don't sit here forever.
                break
            end

            if IsControlJustPressed(0, 18) or IsControlJustPressed(0, 201) then break end            -- Enter
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then cancelled = true break end -- Backspace
        end

        if cancelled then
            cleanup()
            return
        end

        lib.hideTextUI()
        Wait(0) -- let the prompt clear before the frame is grabbed

        -- The watchdog starts HERE, once there's actually an async
        -- operation that could hang. If the capture or upload never comes
        -- back, this still puts everything right.
        CreateThread(function()
            Wait(Config.VehiclePhotos.captureTimeoutMs or 60000)
            if not cleanedUp then
                print('[st_dealership] vehicle photo capture timed out - forcing cleanup')
                lib.notify({ title = 'Vehicle Photo', description = 'The capture timed out - nothing was saved.', type = 'error' })
                cleanup()
            end
        end)

        -- Default path: the SERVER drives the capture. Keeps the Discord
        -- webhook off every client, and routes the image over
        -- screenshot-basic's HTTP channel instead of a net event, so the
        -- size limit that was blocking these saves doesn't apply at all.
        if Config.VehiclePhotos.captureMode ~= 'client' then
            local ok, result = pcall(function()
                return table.pack(lib.callback.await('st_dealership:server:captureVehiclePhoto', false, dealershipName, vin))
            end)

            if ok and result[1] then
                lib.notify({ title = 'Vehicle Photo', description = 'Photo saved.', type = 'success' })
            else
                local reason = ok and result[2] or 'the request failed'
                print(('[st_dealership] server-side photo capture failed: %s'):format(tostring(reason)))
                lib.notify({
                    title = 'Vehicle Photo',
                    description = ('Could not save that photo: %s'):format(tostring(reason)),
                    type = 'error',
                })
            end

            cleanup()
            return
        end

        captureScreenshot(function(photoData, reason)
            -- This body runs in its own thread (see captureScreenshot), so
            -- lib.callback.await below is safe to yield here.
            local ok, err = pcall(function()
                if not photoData then
                    lib.notify({ title = 'Vehicle Photo', description = reason or 'Capture failed - nothing was saved.', type = 'error' })
                    return
                end

                local saved = lib.callback.await('st_dealership:server:saveVehiclePhoto', false, dealershipName, vin, photoData)
                lib.notify({
                    title = 'Vehicle Photo',
                    description = saved and 'Photo saved.' or 'Could not save that photo.',
                    type = saved and 'success' or 'error',
                })
            end)

            if not ok then
                print(('[st_dealership] vehicle photo save error: %s'):format(tostring(err)))
                lib.notify({ title = 'Vehicle Photo', description = 'Something went wrong saving that photo.', type = 'error' })
            end

            cleanup()
        end)
    end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        deletePhotoVehicle(activePhotoVehicle)
    end
end)
