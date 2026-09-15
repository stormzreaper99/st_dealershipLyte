function ST.GetBranding(dealershipName)
    local dealership = ST.GetDealership(dealershipName)
    if not dealership then return nil end
    local settings = ST.GetDealershipSettings(dealershipName)
    local branding = settings.branding or {}
    local theme = settings.theme or dealership.theme or Config.UITheme
    return {
        label = branding.label or dealership.label,
        blipSprite = branding.blipSprite or (dealership.location.blip and dealership.location.blip.sprite) or 225,
        blipColor = branding.blipColor or (dealership.location.blip and dealership.location.blip.color) or 3,
        blipScale = branding.blipScale or (dealership.location.blip and dealership.location.blip.scale) or 0.8,
        theme = theme,
    }
end

lib.callback.register('st_dealership:server:getBranding', function(src, dealershipName)
    return ST.GetBranding(dealershipName)
end)

lib.callback.register('st_dealership:server:updateBranding', function(src, dealershipName, branding)
    if not ST.HasPermission(src, dealershipName, 'configure_dealership') then return false, 'no_permission' end
    if not ST.GetDealership(dealershipName) then return false, 'not_found' end
    local settings = ST.GetDealershipSettings(dealershipName)
    local current = settings.branding or {}
    local incoming = type(branding) == 'table' and branding or {}
    settings.branding = {
        label = incoming.label and tostring(incoming.label):sub(1, 60) or current.label,
        blipSprite = tonumber(incoming.blipSprite) or current.blipSprite,
        blipColor = tonumber(incoming.blipColor) or current.blipColor,
        blipScale = tonumber(incoming.blipScale) or current.blipScale,
    }
    if type(incoming.theme) == 'table' then
        local theme = {}
        for key, value in pairs(incoming.theme) do if type(value) == 'string' then theme[key] = value:sub(1, 80) end end
        settings.theme = theme
    end
    MySQL.insert([[
        INSERT INTO st_dealership_settings (dealership, settings_json) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE settings_json = VALUES(settings_json)
    ]], { dealershipName, json.encode(settings) })
    local resolved = ST.GetBranding(dealershipName)
    TriggerClientEvent('st_dealership:client:brandingUpdated', -1, dealershipName, resolved)
    return true, resolved
end)
