local function validPhotoUrl(url)
    if type(url) ~= 'string' then return nil end
    url = url:match('^%s*(.-)%s*$')
    if url == '' or #url > 2048 or not url:match('^https?://') then return nil end
    return url
end

lib.callback.register('st_dealership:server:setVehiclePhoto', function(src, dealershipName, vin, photoUrl)
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= dealershipName then return false, 'not_found' end
    local url = validPhotoUrl(photoUrl)
    if not url then return false, 'invalid_image_url' end
    MySQL.update('UPDATE st_dealership_vehicles SET photos_json = ? WHERE vin = ?', { json.encode({ url }), vin })
    ST.LogVehicleHistory(vin, 'photo_updated', { source = 'url' })
    return true, url
end)

lib.callback.register('st_dealership:server:clearVehiclePhoto', function(src, dealershipName, vin)
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= dealershipName then return false, 'not_found' end
    MySQL.update('UPDATE st_dealership_vehicles SET photos_json = NULL WHERE vin = ?', { vin })
    ST.LogVehicleHistory(vin, 'photo_removed', {})
    return true
end)
