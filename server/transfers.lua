
-- Staff notifications go through ST.NotifyDealershipStaff (server/main.lua).
local function notifyDealershipStaff(...) return ST.NotifyDealershipStaff(...) end

--- Every OTHER dealership, for the "send to" picker in the NUI.
lib.callback.register('st_dealership:server:getAllDealershipNames', function(src, excludeDealership)
    local out = {}
    for name, def in pairs(ST.GetAllDealerships()) do
        if name ~= excludeDealership then
            out[#out + 1] = { name = name, label = def.label }
        end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

--- Proposes sending one of this dealership's own in-stock vehicles to
--- another dealership, optionally for a cash adjustment either way
--- (positive = the target pays the sender; negative = the sender pays
--- the target - e.g. to offload junk inventory). Reserves the vehicle so
--- it can't be sold elsewhere while the offer is pending, same pattern as
--- financing requests and auctions.
lib.callback.register('st_dealership:server:submitTransferOffer', function(src, fromDealership, toDealership, vin, cashAdjustment)
    if not ST.HasPermission(src, fromDealership, 'purchase_inventory') then return false, 'no_permission' end
    if fromDealership == toDealership then return false, 'same_dealership' end
    if not ST.GetDealership(toDealership) then return false, 'target_not_found' end

    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= fromDealership then return false, 'not_found' end
    if vehicle.status ~= 'in_stock' then return false, 'not_in_stock' end

    MySQL.update("UPDATE st_dealership_vehicles SET status = 'reserved' WHERE vin = ?", { vin })

    MySQL.insert([[
        INSERT INTO st_dealership_transfers (from_dealership, to_dealership, vin, cash_adjustment)
        VALUES (?, ?, ?, ?)
    ]], { fromDealership, toDealership, vin, tonumber(cashAdjustment) or 0 })

    local fromLabel = ST.GetDealership(fromDealership).label
    notifyDealershipStaff(toDealership, 'purchase_inventory', {
        title = 'Trade Offer', description = ('%s wants to send you a vehicle - check Dealer Trade to review it.'):format(fromLabel),
        type = 'inform',
    })

    return true
end)

lib.callback.register('st_dealership:server:getIncomingTransfers', function(src, dealershipName)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return {} end

    return MySQL.query.await([[
        SELECT t.*, v.model, v.asking_price FROM st_dealership_transfers t
        LEFT JOIN st_dealership_vehicles v ON v.vin = t.vin
        WHERE t.to_dealership = ? AND t.status = 'pending'
        ORDER BY t.created_at ASC
    ]], { dealershipName }) or {}
end)

lib.callback.register('st_dealership:server:getOutgoingTransfers', function(src, dealershipName)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return {} end

    return MySQL.query.await([[
        SELECT t.*, v.model, v.asking_price FROM st_dealership_transfers t
        LEFT JOIN st_dealership_vehicles v ON v.vin = t.vin
        WHERE t.from_dealership = ? AND t.status = 'pending'
        ORDER BY t.created_at ASC
    ]], { dealershipName }) or {}
end)

lib.callback.register('st_dealership:server:acceptTransferOffer', function(src, dealershipName, transferId)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return false, 'no_permission' end

    local offer = MySQL.single.await("SELECT * FROM st_dealership_transfers WHERE id = ? AND status = 'pending'", { transferId })
    if not offer then return false, 'not_found' end
    if offer.to_dealership ~= dealershipName then return false, 'not_your_offer' end

    MySQL.update("UPDATE st_dealership_transfers SET status = 'accepted' WHERE id = ?", { transferId })

    -- Release the reservation right before the actual (permission-checked
    -- above, so this is safe) transfer - ST.TransferInventory only accepts
    -- in_stock vehicles, same guard as every other sale path.
    MySQL.update("UPDATE st_dealership_vehicles SET status = 'in_stock' WHERE vin = ?", { offer.vin })

    local ok, err = ST.TransferInventory(src, offer.from_dealership, offer.to_dealership, offer.vin, tonumber(offer.cash_adjustment))
    if not ok then
        MySQL.update("UPDATE st_dealership_transfers SET status = 'pending' WHERE id = ?", { transferId })
        return false, err
    end

    notifyDealershipStaff(offer.from_dealership, 'purchase_inventory', {
        title = 'Trade Accepted', description = ('%s accepted your vehicle transfer.'):format(ST.GetDealership(offer.to_dealership).label),
        type = 'success',
    })

    return true
end)

lib.callback.register('st_dealership:server:declineTransferOffer', function(src, dealershipName, transferId)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return false, 'no_permission' end

    local offer = MySQL.single.await("SELECT * FROM st_dealership_transfers WHERE id = ? AND status = 'pending'", { transferId })
    if not offer then return false, 'not_found' end
    if offer.to_dealership ~= dealershipName then return false, 'not_your_offer' end

    MySQL.update("UPDATE st_dealership_transfers SET status = 'declined' WHERE id = ?", { transferId })
    MySQL.update("UPDATE st_dealership_vehicles SET status = 'in_stock' WHERE vin = ?", { offer.vin })

    notifyDealershipStaff(offer.from_dealership, 'purchase_inventory', {
        title = 'Trade Declined', description = ('%s declined your vehicle transfer.'):format(ST.GetDealership(offer.to_dealership).label),
        type = 'error',
    })

    return true
end)

lib.callback.register('st_dealership:server:cancelTransferOffer', function(src, dealershipName, transferId)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return false, 'no_permission' end

    local offer = MySQL.single.await("SELECT * FROM st_dealership_transfers WHERE id = ? AND status = 'pending'", { transferId })
    if not offer then return false, 'not_found' end
    if offer.from_dealership ~= dealershipName then return false, 'not_your_offer' end

    MySQL.update("UPDATE st_dealership_transfers SET status = 'cancelled' WHERE id = ?", { transferId })
    MySQL.update("UPDATE st_dealership_vehicles SET status = 'in_stock' WHERE vin = ?", { offer.vin })

    return true
end)
