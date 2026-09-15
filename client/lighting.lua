local lightsByDealership = {}
local highlightUntil = {}   -- lightId -> GetGameTimer() deadline, for the "Locate" preview

RegisterNetEvent('st_dealership:client:syncLights', function(dealershipName, lights)
    lightsByDealership[dealershipName] = lights
end)

RegisterNetEvent('st_dealership:client:dealershipDeleted', function(dealershipName)
    lightsByDealership[dealershipName] = nil
end)

--- Called from the NUI ("Locate" button on a light row) to confirm exactly
--- where a placed light actually is, independent of whether the light
--- effect itself is easy to see (e.g. in daylight).
function ST.HighlightLight(lightId, seconds)
    highlightUntil[lightId] = GetGameTimer() + (seconds or 6) * 1000
end

local function isLightOn(l)
    -- oxmysql can return TINYINT(1) as either a number (0/1) or a boolean
    -- depending on driver config - comparing across types with `~=` in Lua
    -- is always true, which silently broke the old `enabled ~= 0` check.
    return l.enabled == 1 or l.enabled == true
end

-- ---------------------------------------------------------------------------
-- Render loop - FiveM has no persistent light entity, so every configured
-- light has to be redrawn every frame it's visible. Distance-culled to
-- Config.LightRenderDistance to keep this cheap away from the lot.
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        local coords = GetEntityCoords(PlayerPedId())
        local anyNearby = false

        for _, lights in pairs(lightsByDealership) do
            for _, l in ipairs(lights) do
                local dist = #(coords - vector3(l.pos_x, l.pos_y, l.pos_z))
                if dist <= Config.LightRenderDistance then
                    if isLightOn(l) then
                        anyNearby = true
                        if l.type == 'point' then
                            DrawLightWithRange(l.pos_x, l.pos_y, l.pos_z, l.color_r, l.color_g, l.color_b, l.range, l.brightness)
                        else -- 'spot' or 'flood'
                            DrawSpotLightWithShadow(
                                l.pos_x, l.pos_y, l.pos_z, l.dir_x, l.dir_y, l.dir_z,
                                l.color_r, l.color_g, l.color_b, l.range, l.brightness,
                                0.0, l.radius, l.falloff, l.shadow == 1 and 1.0 or 0.0
                            )
                        end
                    end

                    if highlightUntil[l.id] and GetGameTimer() < highlightUntil[l.id] then
                        anyNearby = true
                        DrawMarker(28, l.pos_x, l.pos_y, l.pos_z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 80, 200, 255, 220, true, true, 2, false, nil, nil, false)
                    end
                end
            end
        end

        Wait(anyNearby and 0 or 500)
    end
end)

-- ---------------------------------------------------------------------------
-- Placement tool - shared "aim and confirm" flow used for adding/editing a
-- light. Hides the NUI, lets the player aim the light with their camera,
-- adjust distance/height/rotation, then hands the result back to the NUI.
-- Controls: mouse aims, scroll wheel = distance from camera, HOLD Left
-- Ctrl + scroll = height, Q/E = rotation (spot/flood direction), Enter =
-- confirm, Backspace = cancel.
--
-- Height previously used the arrow-key "FRONTEND" controls (172/173),
-- which only fire while a frontend-style menu has input focus - this tool
-- explicitly drops NUI focus so the player can walk around and aim, which
-- meant that control group was never active and height silently did
-- nothing. Ctrl+scroll reuses controls already confirmed working (14/15)
-- instead of relying on that.
-- ---------------------------------------------------------------------------
--- Returns the placement, or nil if cancelled/timed out. UI hiding and
--- restoring is owned by ST.RunPlacement (client/nui.lua) - see the note
--- in client/zones.lua about why the tools no longer do it themselves.
local INPUT_GUARD_MS = 250
local PLACEMENT_TIMEOUT_MS = 120000

local function runPlacementTool(seed)
    local dist = seed and seed.dist or 4.0
    local heightOffset = seed and seed.heightOffset or 0.0
    local yaw = seed and seed.yaw or 0.0
    local cancelled = false

    lib.showTextUI('[Scroll] distance   [Ctrl+Scroll] height   [Q/E] rotate   [Enter] confirm   [Backspace] cancel')

    local startedAt = GetGameTimer()
    local result
    while true do
        Wait(0)

        local elapsed = GetGameTimer() - startedAt
        if elapsed > PLACEMENT_TIMEOUT_MS then
            lib.notify({ title = 'Lighting', description = 'Placement timed out.', type = 'error' })
            cancelled = true
            break
        end
        DisableControlAction(0, 24, true) -- attack
        DisableControlAction(0, 25, true) -- aim

        local heightMode = IsControlPressed(0, 36) -- Left Ctrl (INPUT_DUCK)

        if IsControlPressed(0, 14) then -- scroll up
            if heightMode then heightOffset = heightOffset + 0.05 else dist = math.min(dist + 0.15, 30.0) end
        end
        if IsControlPressed(0, 15) then -- scroll down
            if heightMode then heightOffset = heightOffset - 0.05 else dist = math.max(dist - 0.15, 1.0) end
        end
        if IsControlPressed(0, 44) then yaw = yaw - 1.5 end -- Q
        if IsControlPressed(0, 38) then yaw = yaw + 1.5 end -- E

        local camCoord = GetGameplayCamCoord()
        local camRot = GetGameplayCamRot(2)
        local rad = math.rad(camRot.z)
        local forward = vector3(-math.sin(rad), math.cos(rad), 0.0)
        local pos = camCoord + forward * dist + vector3(0.0, 0.0, heightOffset)

        local dirRad = math.rad(yaw)
        local dir = vector3(-math.sin(dirRad), math.cos(dirRad), -0.35)

        DrawMarker(28, pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.35, 0.35, 0.35, 255, 200, 80, 180, false, true, 2, false, nil, nil, false)

        if elapsed > INPUT_GUARD_MS then
            if IsControlJustPressed(0, 18) or IsControlJustPressed(0, 201) then -- Enter / numpad Enter
                result = { pos = { x = pos.x, y = pos.y, z = pos.z }, dir = { x = dir.x, y = dir.y, z = dir.z }, dist = dist, heightOffset = heightOffset, yaw = yaw }
                break
            end
            if IsControlJustPressed(0, 177) or IsControlJustPressed(0, 194) then -- Backspace
                cancelled = true
                break
            end
        end
    end

    lib.hideTextUI()
    return cancelled and nil or result
end

--- Runs the in-world light placement tool and returns the placement (or
--- nil if cancelled). Called by ST.RunPlacement in client/nui.lua, which
--- handles hiding and restoring the interface around it.
function ST.RunLightPlacementTool(seed)
    return runPlacementTool(seed)
end
