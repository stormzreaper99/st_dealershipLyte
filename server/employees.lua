local function currentMonthKey() return os.date('%Y-%m') end
ST.CurrentMonthKey = currentMonthKey

function ST.RecordEmployeeSale(citizenId, dealershipName, salePrice, meta)
    MySQL.insert([[
        INSERT INTO st_dealership_employees (citizenid, dealership, vehicles_sold, sales_volume, month_units_sold, month_key)
        VALUES (?, ?, 1, ?, 1, ?)
        ON DUPLICATE KEY UPDATE
            vehicles_sold = vehicles_sold + 1,
            sales_volume = sales_volume + VALUES(sales_volume),
            month_units_sold = IF(month_key = VALUES(month_key), month_units_sold + 1, 1),
            month_key = VALUES(month_key)
    ]], { citizenId, dealershipName, salePrice, currentMonthKey() })
    if meta.satisfaction then MySQL.update('UPDATE st_dealership_employees SET satisfaction_total = satisfaction_total + ?, satisfaction_count = satisfaction_count + 1 WHERE citizenid = ? AND dealership = ?', { meta.satisfaction, citizenId, dealershipName }) end
    if meta.tradeIn then MySQL.update('UPDATE st_dealership_employees SET trade_ins_handled = trade_ins_handled + 1 WHERE citizenid = ? AND dealership = ?', { citizenId, dealershipName }) end
    if meta.financed then MySQL.update('UPDATE st_dealership_employees SET financing_deals = financing_deals + 1 WHERE citizenid = ? AND dealership = ?', { citizenId, dealershipName }) end
end

function ST.PayCommission(citizenId, dealershipName, salePrice, meta)
    local settings = ST.GetDealershipSettings(dealershipName)
    local rate = (settings and settings.commissionBaseRate) or Config.Commissions.baseRatePercent
    if meta.satisfaction and meta.satisfaction >= 4 then rate = rate + Config.Commissions.bonuses.highSatisfaction end
    if meta.financed then rate = rate + Config.Commissions.bonuses.financingDeal end
    if meta.tradeIn then rate = rate + Config.Commissions.bonuses.tradeInIncluded end
    local employeeRow = MySQL.single.await('SELECT month_units_sold, month_key FROM st_dealership_employees WHERE citizenid = ? AND dealership = ?', { citizenId, dealershipName })
    if employeeRow and employeeRow.month_key == currentMonthKey() and tonumber(employeeRow.month_units_sold) >= Config.Commissions.monthlyUnitTarget then rate = rate + Config.Commissions.bonuses.monthlyTargetHit end
    local commission = Utils.Round(salePrice * (rate / 100), 2)
    if commission <= 0 then return 0 end
    if not ST.AdjustBalance(dealershipName, -commission, true, 'sales-commission') then return 0 end
    if not ST.Money.AddPlayer(citizenId, commission, 'dealership-commission') then ST.AdjustBalance(dealershipName, commission, true, 'sales-commission-reversal'); return 0 end
    return commission
end

function ST.GetDealershipSettings(dealershipName)
    local row = MySQL.single.await('SELECT settings_json FROM st_dealership_settings WHERE dealership = ?', { dealershipName })
    if not row or not row.settings_json then return {} end
    local ok, decoded = pcall(json.decode, row.settings_json)
    return (ok and type(decoded) == 'table') and decoded or {}
end

lib.callback.register('st_dealership:server:getEmployeeStats', function(src, citizenId, dealershipName)
    local callerCitizenId = ST.GetPlayerCitizenId(src)
    if not callerCitizenId then return nil end
    if citizenId ~= callerCitizenId and not ST.HasPermission(src, dealershipName, 'hire') then return nil end
    return MySQL.single.await('SELECT * FROM st_dealership_employees WHERE citizenid = ? AND dealership = ?', { citizenId, dealershipName })
end)

lib.callback.register('st_dealership:server:getLeaderboard', function(src, dealershipName)
    if not ST.HasPermission(src, dealershipName, 'hire') then return {} end
    return MySQL.query.await([[
        SELECT citizenid, vehicles_sold, sales_volume,
            ROUND(sales_volume / GREATEST(vehicles_sold, 1), 2) AS avg_deal,
            ROUND(satisfaction_total / GREATEST(satisfaction_count, 1), 2) AS avg_satisfaction
        FROM st_dealership_employees WHERE dealership = ? ORDER BY sales_volume DESC LIMIT 20
    ]], { dealershipName }) or {}
end)
