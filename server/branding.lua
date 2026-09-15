--- Reads the settings JSON blob and pulls out just the branding keys
--- (label, blipSprite, blipColor, blipScale). Anything not overridden
--- falls back to config/dealerships.lua at read time.
function ST.GetBranding(dealershipName)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return nil end

    local settings = ST.GetDealershipSettings(dealershipName)
    local branding = settings.branding or {}

    return {
        label = branding.label or dealership.label,
        blipSprite = branding.blipSprite or (dealership.location.blip and dealership.location.blip.sprite) or 225,
        blipColor = branding.blipColor or (dealership.location.blip and dealership.location.blip.color) or 3,
        blipScale = branding.blipScale or (dealership.location.blip and dealership.location.blip.scale) or 0.8,
    }
end

lib.callback.register('st_dealership:server:getBranding', function(src, dealershipName)
    return ST.GetBranding(dealershipName)
end)

lib.callback.register('st_dealership:server:updateBranding', function(src, dealershipName, branding)
    if not ST.HasPermission(src, dealershipName, 'configure_dealership') then return false, 'no_permission' end
    if not ST.GetDealership(dealershipName) then return false, 'not_found' end

    local settings = ST.GetDealershipSettings(dealershipName)
    settings.branding = {
        label = branding.label and tostring(branding.label):sub(1, 60) or nil,
        blipSprite = tonumber(branding.blipSprite),
        blipColor = tonumber(branding.blipColor),
        blipScale = tonumber(branding.blipScale),
    }

    MySQL.insert([[
        INSERT INTO st_dealership_settings (dealership, settings_json) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE settings_json = VALUES(settings_json)
    ]], { dealershipName, json.encode(settings) })

    local resolved = ST.GetBranding(dealershipName)
    TriggerClientEvent('st_dealership:client:brandingUpdated', -1, dealershipName, resolved)

    return true, resolved
end)
