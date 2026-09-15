local QBX = exports.qbx_core

--- Flagged customers can't use the instant kiosk approval (see
--- quoteFinancing's 'requires_manual_review' branch in financing.lua) -
--- this is what they hit "submit request" against instead. Reserves the
--- vehicle so it can't be sold out from under the pending request while
--- staff review it.
lib.callback.register('st_dealership:server:submitFinancingRequest', function(src, dealershipName, vin, finalPrice, downPayment, termMonths)
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle or vehicle.dealership ~= dealershipName then return false, 'not_found' end
    if vehicle.status ~= 'in_stock' then return false, 'not_in_stock' end

    local buyerCitizenId = ST.GetPlayerCitizenId(src)
    if not buyerCitizenId then return false, 'no_player' end

    -- finalPrice used to be taken entirely on trust, so a tampered client
    -- could submit a request to finance a $150k car at $1 and hope staff
    -- clicked approve. It's now held to the same floor every other sale
    -- path uses.
    finalPrice = math.floor(tonumber(finalPrice) or 0)
    local minPrice = math.floor(tonumber(vehicle.min_price) or 0)
    if finalPrice < minPrice then return false, 'below_minimum' end

    downPayment = math.floor(tonumber(downPayment) or 0)
    if downPayment < 0 then downPayment = 0 end
    if downPayment < math.floor(finalPrice * Config.Financing.minDownPaymentPercent) then
        return false, 'down_payment_too_low'
    end

    termMonths = math.min(math.floor(tonumber(termMonths) or 36), Config.Financing.maxTermMonths)
    local principal = finalPrice - downPayment
    if principal <= 0 then return false, 'nothing_to_finance' end
    if principal > finalPrice * Config.Financing.maxLoanToValue then
        return false, 'loan_to_value'
    end

    -- One open request per customer per vehicle.
    local existing = MySQL.scalar.await(
        "SELECT 1 FROM st_dealership_financing_requests WHERE vin = ? AND citizenid = ? AND status = 'pending'",
        { vin, buyerCitizenId })
    if existing then return false, 'already_pending' end

    local score = ST.GetCreditScore(buyerCitizenId)
    local apr = ST.GetAprForScore(score)

    MySQL.update("UPDATE st_dealership_vehicles SET status = 'reserved' WHERE vin = ?", { vin })

    MySQL.insert([[
        INSERT INTO st_dealership_financing_requests
            (dealership, vin, citizenid, sale_price, down_payment, term_months, apr)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { dealershipName, vin, buyerCitizenId, finalPrice, downPayment, termMonths, apr })

    ST.NotifyDealershipStaff(dealershipName, 'approve_financing', {
        title = 'Financing Request',
        description = ('New financing request for %s (VIN %s) - needs manual review.'):format(vehicle.model, vin),
        type = 'inform',
    })

    return true
end)

lib.callback.register('st_dealership:server:getFinancingRequests', function(src, dealershipName)
    if not ST.HasPermission(src, dealershipName, 'approve_financing') then return {} end

    return MySQL.query.await([[
        SELECT r.*, v.model FROM st_dealership_financing_requests r
        LEFT JOIN st_dealership_vehicles v ON v.vin = r.vin
        WHERE r.dealership = ? AND r.status = 'pending'
        ORDER BY r.created_at ASC
    ]], { dealershipName }) or {}
end)

lib.callback.register('st_dealership:server:approveFinancingRequest', function(src, dealershipName, requestId)
    if not ST.HasPermission(src, dealershipName, 'approve_financing') then return false, 'no_permission' end

    local request = MySQL.single.await("SELECT * FROM st_dealership_financing_requests WHERE id = ? AND status = 'pending'", { requestId })
    if not request then return false, 'not_found' end

    MySQL.update("UPDATE st_dealership_financing_requests SET status = 'approved' WHERE id = ?", { requestId })

    -- This request is what reserved the vehicle in the first place
    -- (submitFinancingRequest), so releasing it back to in_stock here,
    -- immediately before finalizing, is safe - completeSale only accepts
    -- in_stock vehicles (see server/sales.lua) specifically so a vehicle
    -- reserved for something else can't be raced by an unrelated sale.
    MySQL.update("UPDATE st_dealership_vehicles SET status = 'in_stock' WHERE vin = ?", { request.vin })

    local approverCitizenId = ST.GetPlayerCitizenId(src)
    local ok, result = ST.CompleteSale(request.vin, request.citizenid, tonumber(request.sale_price), {
        financed = true,
        downPayment = tonumber(request.down_payment),
        apr = tonumber(request.apr),
        termMonths = request.term_months,
        satisfactionRating = 5,
    }, approverCitizenId)

    if not ok then
        -- Sale itself failed for some other reason (vehicle no longer
        -- available, etc) - put the request back to pending rather than
        -- silently eating it, so staff can see it needs attention again.
        MySQL.update("UPDATE st_dealership_financing_requests SET status = 'pending' WHERE id = ?", { requestId })
        return false, result
    end

    local player = QBX:GetPlayerByCitizenId(request.citizenid)
    if player then
        TriggerClientEvent('ox_lib:notify', player.PlayerData.source, {
            title = 'Financing Approved',
            description = 'Your financing request was approved - the sale is complete.',
            type = 'success',
        })
    end

    return true
end)

lib.callback.register('st_dealership:server:denyFinancingRequest', function(src, dealershipName, requestId)
    if not ST.HasPermission(src, dealershipName, 'approve_financing') then return false, 'no_permission' end

    local request = MySQL.single.await("SELECT * FROM st_dealership_financing_requests WHERE id = ? AND status = 'pending'", { requestId })
    if not request then return false, 'not_found' end

    MySQL.update("UPDATE st_dealership_financing_requests SET status = 'denied' WHERE id = ?", { requestId })
    MySQL.update("UPDATE st_dealership_vehicles SET status = 'in_stock' WHERE vin = ?", { request.vin })

    local player = QBX:GetPlayerByCitizenId(request.citizenid)
    if player then
        TriggerClientEvent('ox_lib:notify', player.PlayerData.source, {
            title = 'Financing Denied',
            description = 'Your financing request was denied by dealership staff.',
            type = 'error',
        })
    end

    return true
end)
