--- Legacy/client-capture path: `photoData` is either a raw base64 data URI
--- or an already-uploaded CDN URL - either way it's just a string stored
--- as the vehicle's photo. Still used when
--- Config.VehiclePhotos.captureMode is 'client'.
lib.callback.register('st_dealership:server:saveVehiclePhoto', function(src, dealershipName, vin, photoData)
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end
    if not photoData then return false, 'no_photo' end

    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= dealershipName then return false, 'not_found' end

    MySQL.update('UPDATE st_dealership_vehicles SET photos_json = ? WHERE vin = ?', { json.encode({ photoData }), vin })
    ST.LogVehicleHistory(vin, 'photo_updated', {})

    return true
end)

--- Server-driven capture (the default). The client asks the server to take
--- the photo instead of taking it itself, so:
---   * the Discord webhook stays on the server and is never sent to a client
---   * the image travels over screenshot-basic's HTTP channel rather than a
---     net event, so there's no size limit to fall foul of
---
--- Returns ok, resultOrReason.
lib.callback.register('st_dealership:server:captureVehiclePhoto', function(src, dealershipName, vin)
    if not ST.HasPermission(src, dealershipName, 'set_pricing') then return false, 'no_permission' end

    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= dealershipName then return false, 'not_found' end

    local p = promise.new()
    ST.CaptureClientPhoto(src, function(photoData, reason)
        p:resolve({ photoData = photoData, reason = reason })
    end)

    local result = Citizen.Await(p)

    if not result.photoData then
        return false, result.reason or 'capture_failed'
    end

    MySQL.update('UPDATE st_dealership_vehicles SET photos_json = ? WHERE vin = ?',
        { json.encode({ result.photoData }), vin })
    ST.LogVehicleHistory(vin, 'photo_updated', { uploaded = ST.GetPhotoWebhook() ~= nil })

    return true
end)
