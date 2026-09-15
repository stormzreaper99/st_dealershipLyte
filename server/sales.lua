local QBX = exports.qbx_core

lib.callback.register('st_dealership:server:evaluateOffer', function(src, vin, offerAmount)
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle then return { verdict = 'invalid' } end
    offerAmount = tonumber(offerAmount)
    if not offerAmount then return { verdict = 'invalid' } end
    local asking, minPrice = tonumber(vehicle.asking_price), tonumber(vehicle.min_price)
    if offerAmount >= asking then return { verdict = 'accept', counter = asking } end
    if offerAmount >= minPrice then
        return { verdict = 'counter', counter = math.max(Utils.Round(minPrice + (asking - minPrice) * 0.6), offerAmount) }
    end
    return { verdict = 'reject', counter = Utils.Round(minPrice * 1.02) }
end)

local function sanitizeDealOptions(raw, vehicle, finalPrice, buyerCitizenId)
    raw = raw or {}
    local clean = { satisfactionRating = nil, tradeInVin = nil, warranty = type(raw.warranty) == 'table' and raw.warranty or {}, financed = false, downPayment = finalPrice, apr = nil, termMonths = nil }
    local rating = tonumber(raw.satisfactionRating)
    if rating then clean.satisfactionRating = Utils.Clamp(math.floor(rating), 1, 5) end
    if raw.tradeInVin then
        local tradeIn = ST.GetVehicleByVin(raw.tradeInVin)
        if tradeIn then clean.tradeInVin = tradeIn.vin end
    end
    if not raw.financed then return clean end
    if not Config.Financing.enabled then return nil, 'financing_disabled' end
    if tonumber(vehicle.financing_eligible) ~= 1 and vehicle.financing_eligible ~= true then return nil, 'not_financing_eligible' end
    local downPayment, termMonths = math.floor(tonumber(raw.downPayment) or 0), math.floor(tonumber(raw.termMonths) or 36)
    local quote = ST.QuoteFinancing(buyerCitizenId, finalPrice, downPayment, termMonths)
    if not quote.approved then return nil, quote.reason or 'financing_declined' end
    clean.financed, clean.downPayment, clean.apr, clean.termMonths = true, downPayment, quote.apr, quote.termMonths
    return clean
end

local function completeSale(vin, buyerCitizenId, finalPrice, dealOptions, salespersonId)
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle then return false, 'not_found' end
    if vehicle.status ~= 'in_stock' then return false, 'unavailable' end
    finalPrice = math.floor(tonumber(finalPrice) or 0)
    if finalPrice <= 0 then return false, 'invalid_price' end
    local minPrice = math.floor(tonumber(vehicle.min_price) or 0)
    if finalPrice < minPrice then return false, 'below_minimum' end

    local dealershipName = vehicle.dealership
    local clean, reason = sanitizeDealOptions(dealOptions, vehicle, finalPrice, buyerCitizenId)
    if not clean then return false, reason end
    local amountDue = (clean.financed and Config.Money.financedChargesDownPaymentOnly) and clean.downPayment or finalPrice
    if amountDue > 0 then
        if not ST.Money.CanPlayerAfford(buyerCitizenId, amountDue) then return false, 'insufficient_funds' end
        if not ST.Money.RemovePlayer(buyerCitizenId, amountDue, 'vehicle-purchase') then return false, 'insufficient_funds' end
    end

    MySQL.update("UPDATE st_dealership_vehicles SET status = 'sold' WHERE vin = ?", { vin })
    ST.ClearDisplayAssignmentForVin(dealershipName, vin)
    local contractId = MySQL.insert.await([[
        INSERT INTO st_dealership_contracts
            (vin, dealership, buyer_citizenid, salesperson_citizenid, sale_price, trade_in_vin, down_payment, financed, apr, term_months, warranty_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { vin, dealershipName, buyerCitizenId, salespersonId, finalPrice, clean.tradeInVin, clean.downPayment, clean.financed and 1 or 0, clean.apr, clean.termMonths, json.encode(clean.warranty) })
    ST.LogVehicleHistory(vin, 'sold', { buyer = buyerCitizenId, price = finalPrice, contractId = contractId, salesperson = salespersonId })
    ST.AdjustBalance(dealershipName, amountDue, true, 'vehicle-sale')
    if clean.financed then ST.OpenLoan(contractId, buyerCitizenId, vin, finalPrice - clean.downPayment, clean.apr, clean.termMonths) end
    ST.HandOverPurchasedVehicle(buyerCitizenId, dealershipName, vehicle.model, vin)
    if salespersonId then
        local meta = { satisfaction = clean.satisfactionRating, financed = clean.financed, tradeIn = clean.tradeInVin ~= nil }
        ST.RecordEmployeeSale(salespersonId, dealershipName, finalPrice, meta)
        ST.PayCommission(salespersonId, dealershipName, finalPrice, meta)
    end
    return true, { contractId = contractId, dealership = dealershipName, charged = amountDue, financed = clean.financed }
end
ST.CompleteSale = completeSale

function ST.SellVehicle(src, vin, buyerCitizenId, finalPrice, dealOptions)
    local vehicle = ST.GetVehicleByVin(vin)
    if not vehicle then return false, 'not_found' end
    if not ST.HasPermission(src, vehicle.dealership, 'sell') then return false, 'no_permission' end
    if not buyerCitizenId or not QBX:GetPlayerByCitizenId(buyerCitizenId) then return false, 'buyer_offline' end
    return completeSale(vin, buyerCitizenId, finalPrice, dealOptions, ST.GetPlayerCitizenId(src))
end
exports('SellVehicle', ST.SellVehicle)
lib.callback.register('st_dealership:server:sellVehicle', function(src, vin, buyerCitizenId, finalPrice, dealOptions) return ST.SellVehicle(src, vin, buyerCitizenId, finalPrice, dealOptions) end)
lib.callback.register('st_dealership:server:kioskPurchase', function(src, vin, finalPrice, dealOptions)
    local buyerCitizenId = ST.GetPlayerCitizenId(src)
    if not buyerCitizenId then return false, 'no_player' end
    return completeSale(vin, buyerCitizenId, finalPrice, dealOptions, nil)
end)
