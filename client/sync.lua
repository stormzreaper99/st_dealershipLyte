--- QBCore:Client:OnPlayerLoaded is confirmed/documented on both qb-core and
--- qbx_core. Requesting our own sync data here (instead of relying only on
--- a server-side "player loaded" broadcast whose exact event name varies
--- across core versions) means zones/lights/displays reliably reappear
--- after every reconnect, regardless of which server-side event does or
--- doesn't fire in a given qbx_core version.
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('st_dealership:server:requestFullSync')
end)
