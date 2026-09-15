--- Opens an auction listing for a VIN currently sitting in the auction
--- house's own inventory (repos, fleet, damaged, rare pulls, etc).
--- `sellerDealership` is who gets paid when the lot closes. It's optional
--- (house stock / seeded listings have no seller), but a consignment that
--- doesn't record one means the winning bid is debited from the buyer and
--- credited to nobody - which is exactly what used to happen to every
--- consigned vehicle.
function ST.OpenAuction(vin, sourceType, startingBid, durationMinutes, sellerDealership)
    startingBid = math.floor(tonumber(startingBid) or 0)
    if startingBid <= 0 then return nil end

    durationMinutes = math.floor(tonumber(durationMinutes) or 30)
    durationMinutes = Utils.Clamp(durationMinutes, 1, 1440)

    if not sellerDealership then
        local vehicle = ST.GetVehicleByVin(vin)
        sellerDealership = vehicle and vehicle.dealership or nil
    end

    local endsAt = os.time() + durationMinutes * 60
    local auctionId = MySQL.insert.await([[
        INSERT INTO st_dealership_auctions (vin, source_type, starting_bid, current_bid, ends_at, seller_dealership)
        VALUES (?, ?, ?, ?, FROM_UNIXTIME(?), ?)
    ]], { vin, sourceType or 'random', startingBid, startingBid, endsAt, sellerDealership })

    MySQL.update("UPDATE st_dealership_vehicles SET status = 'reserved' WHERE vin = ?", { vin })
    ST.LogVehicleHistory(vin, 'auction_opened', { auctionId = auctionId, startingBid = startingBid, seller = sellerDealership })
    return auctionId
end
exports('OpenAuction', ST.OpenAuction)

lib.callback.register('st_dealership:server:getOpenAuctions', function(src)
    return MySQL.query.await([[
        SELECT a.*, v.model, v.mileage, v.condition_json, v.title_status
        FROM st_dealership_auctions a
        JOIN st_dealership_vehicles v ON v.vin = a.vin
        WHERE a.status = 'open' ORDER BY a.ends_at ASC
    ]]) or {}
end)

--- Places a bid on behalf of `bidderDealership`. Requires 'purchase_inventory'
--- perm at the bidding dealership.
lib.callback.register('st_dealership:server:placeBid', function(src, auctionId, bidderDealership, amount)
    if not ST.HasPermission(src, bidderDealership, 'purchase_inventory') then return false, 'no_permission' end

    local auction = MySQL.single.await("SELECT * FROM st_dealership_auctions WHERE id = ? AND status = 'open'", { auctionId })
    if not auction then return false, 'not_found' end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_bid' end
    if amount <= tonumber(auction.current_bid) then return false, 'bid_too_low' end

    -- A dealership can't bid on the lot it consigned itself.
    if auction.seller_dealership == bidderDealership then return false, 'own_listing' end

    if ST.GetBalance(bidderDealership) < amount then return false, 'insufficient_funds' end

    MySQL.update('UPDATE st_dealership_auctions SET current_bid = ?, current_bidder = ? WHERE id = ?',
        { amount, bidderDealership, auctionId })
    MySQL.insert('INSERT INTO st_dealership_auction_bids (auction_id, dealership, amount) VALUES (?, ?, ?)',
        { auctionId, bidderDealership, amount })

    return true
end)

function ST.CloseAuction(auctionId)
    local auction = MySQL.single.await("SELECT * FROM st_dealership_auctions WHERE id = ? AND status = 'open'", { auctionId })
    if not auction then return false, 'not_found' end

    MySQL.update("UPDATE st_dealership_auctions SET status = 'closed' WHERE id = ?", { auctionId })

    if auction.current_bidder then
        local winningBid = math.floor(tonumber(auction.current_bid) or 0)

        ST.AdjustBalance(auction.current_bidder, -winningBid, true, 'auction-purchase')

        -- The seller side was missing entirely: the winner paid and the
        -- money left the economy. Consigned lots now pay out to whoever
        -- listed the vehicle.
        if auction.seller_dealership and auction.seller_dealership ~= auction.current_bidder then
            ST.AdjustBalance(auction.seller_dealership, winningBid, true, 'auction-sale')
        end

        MySQL.update("UPDATE st_dealership_vehicles SET dealership = ?, status = 'in_stock', purchase_cost = ? WHERE vin = ?",
            { auction.current_bidder, winningBid, auction.vin })
        ST.LogVehicleHistory(auction.vin, 'auction_won', {
            dealership = auction.current_bidder, seller = auction.seller_dealership, amount = winningBid,
        })
    else
        -- no bids: return to unsold/wholesale pool
        MySQL.update("UPDATE st_dealership_vehicles SET status = 'wholesaled' WHERE vin = ?", { auction.vin })
        ST.LogVehicleHistory(auction.vin, 'auction_unsold', {})
    end

    return true
end

--- Lets an Inventory Manager (or above) consign one of their own in-stock
--- vehicles to the dealer auction house instead of selling it retail.
--- Without this, ST.OpenAuction was never actually called from anywhere -
--- the Auctions tab had full browse/bid/close logic but no way to ever
--- populate a listing in the first place.
lib.callback.register('st_dealership:server:sendToAuction', function(src, dealershipName, vin, startingBid, durationMinutes)
    if not ST.HasPermission(src, dealershipName, 'purchase_inventory') then return false, 'no_permission' end

    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= dealershipName then return false, 'not_found' end
    if vehicle.status ~= 'in_stock' then return false, 'not_in_stock' end

    startingBid = tonumber(startingBid)
    if not startingBid or startingBid <= 0 then return false, 'invalid_bid' end

    local auctionId = ST.OpenAuction(vin, 'dealer_consignment', startingBid, tonumber(durationMinutes) or 30, dealershipName)
    if not auctionId then return false, 'invalid_bid' end
    return true, { auctionId = auctionId }
end)

CreateThread(function()
    while true do
        Wait(60 * 1000)
        local expired = MySQL.query.await(
            "SELECT id FROM st_dealership_auctions WHERE status = 'open' AND ends_at <= NOW()") or {}
        for _, row in ipairs(expired) do
            ST.CloseAuction(row.id)
        end
    end
end)
