local QBX = exports.qbx_core

--- 'YYYY-MM' for the current real month. month_units_sold is scoped to
--- this, so the monthly target bonus resets instead of staying earned
--- forever after the tenth lifetime sale.
local function currentMonthKey()
    return os.date('%Y-%m')
end
ST.CurrentMonthKey = currentMonthKey

function ST.RecordEmployeeSale(citizenId, dealershipName, salePrice, meta)
    -- MySQL evaluates ON DUPLICATE KEY assignments left to right, so
    -- month_units_sold must be updated while month_key still holds the
    -- OLD value - hence the ordering here.
    MySQL.insert([[
        INSERT INTO st_dealership_employees (citizenid, dealership, vehicles_sold, sales_volume, month_units_sold, month_key)
        VALUES (?, ?, 1, ?, 1, ?)
        ON DUPLICATE KEY UPDATE
            vehicles_sold = vehicles_sold + 1,
            sales_volume = sales_volume + VALUES(sales_volume),
            month_units_sold = IF(month_key = VALUES(month_key), month_units_sold + 1, 1),
            month_key = VALUES(month_key)
    ]], { citizenId, dealershipName, salePrice, currentMonthKey() })

    if meta.satisfaction then
        MySQL.update([[
            UPDATE st_dealership_employees SET satisfaction_total = satisfaction_total + ?, satisfaction_count = satisfaction_count + 1
            WHERE citizenid = ? AND dealership = ?
        ]], { meta.satisfaction, citizenId, dealershipName })
    end
    if meta.tradeIn then
        MySQL.update('UPDATE st_dealership_employees SET trade_ins_handled = trade_ins_handled + 1 WHERE citizenid = ? AND dealership = ?',
            { citizenId, dealershipName })
    end
    if meta.financed then
        MySQL.update('UPDATE st_dealership_employees SET financing_deals = financing_deals + 1 WHERE citizenid = ? AND dealership = ?',
            { citizenId, dealershipName })
    end
end

--- Pays a salesperson their commission for a completed sale via qbx_core
--- money functions. Bonuses stack per config/commissions.lua.
function ST.PayCommission(citizenId, dealershipName, salePrice, meta)
    local settings = ST.GetDealershipSettings(dealershipName)
    local baseRate = (settings and settings.commissionBaseRate) or Config.Commissions.baseRatePercent

    local rate = baseRate
    if meta.satisfaction and meta.satisfaction >= 4 then rate = rate + Config.Commissions.bonuses.highSatisfaction end
    if meta.financed then rate = rate + Config.Commissions.bonuses.financingDeal end
    if meta.tradeIn then rate = rate + Config.Commissions.bonuses.tradeInIncluded end
    if meta.daysOnLot and meta.daysOnLot >= Config.Aging.slow then rate = rate + Config.Commissions.bonuses.difficultSale end

    local employeeRow = MySQL.single.await('SELECT month_units_sold, month_key FROM st_dealership_employees WHERE citizenid = ? AND dealership = ?',
        { citizenId, dealershipName })
    if employeeRow and employeeRow.month_key == currentMonthKey()
        and tonumber(employeeRow.month_units_sold) >= Config.Commissions.monthlyUnitTarget then
        rate = rate + Config.Commissions.bonuses.monthlyTargetHit
    end

    local commission = Utils.Round(salePrice * (rate / 100), 2)
    if commission <= 0 then return 0 end

    -- Debit the dealership first; only pay out if that actually succeeded,
    -- so a broke dealership can't mint commission out of nothing.
    if not ST.AdjustBalance(dealershipName, -commission, true, 'sales-commission') then
        return 0
    end

    -- Goes through the money bridge (server/money.lua) rather than the
    -- legacy Player.Functions API, so it works on current qbx_core and
    -- respects Config.Money.playerAccount.
    if not ST.Money.AddPlayer(citizenId, commission, 'dealership-commission') then
        ST.AdjustBalance(dealershipName, commission, true, 'sales-commission-reversal')
        return 0
    end

    return commission
end

function ST.GetDealershipSettings(dealershipName)
    local row = MySQL.single.await('SELECT settings_json FROM st_dealership_settings WHERE dealership = ?', { dealershipName })
    if not row or not row.settings_json then return {} end

    -- A malformed blob shouldn't take down branding/commission lookups.
    local ok, decoded = pcall(json.decode, row.settings_json)
    return (ok and type(decoded) == 'table') and decoded or {}
end

--- You can always read your own stats; reading someone else's needs the
--- 'hire' perm (management and up). Previously this returned any
--- citizenid's sales record to any caller.
lib.callback.register('st_dealership:server:getEmployeeStats', function(src, citizenId, dealershipName)
    local callerCitizenId = ST.GetPlayerCitizenId(src)
    if not callerCitizenId then return nil end

    if citizenId ~= callerCitizenId and not ST.HasPermission(src, dealershipName, 'hire') then
        return nil
    end

    return MySQL.single.await('SELECT * FROM st_dealership_employees WHERE citizenid = ? AND dealership = ?', { citizenId, dealershipName })
end)

lib.callback.register('st_dealership:server:getLeaderboard', function(src, dealershipName)
    return MySQL.query.await([[
        SELECT citizenid, vehicles_sold, sales_volume,
            ROUND(sales_volume / GREATEST(vehicles_sold, 1), 2) AS avg_deal,
            ROUND(satisfaction_total / GREATEST(satisfaction_count, 1), 2) AS avg_satisfaction
        FROM st_dealership_employees WHERE dealership = ? ORDER BY sales_volume DESC LIMIT 20
    ]], { dealershipName }) or {}
end)

-- ---------------------------------------------------------------------------
-- Reputation
-- ---------------------------------------------------------------------------

local repFields = { 'overall', 'customer_service', 'pricing', 'honesty', 'vehicle_quality', 'financing_rep', 'sales_experience', 'after_sales_support' }
local repFieldSet = {}
for _, f in ipairs(repFields) do repFieldSet[f] = true end

function ST.AdjustReputation(dealershipName, deltas)
    MySQL.insert('INSERT INTO st_dealership_reputation (dealership) VALUES (?) ON DUPLICATE KEY UPDATE dealership = dealership',
        { dealershipName })

    for field, delta in pairs(deltas) do
        -- `field` ends up directly inside a SQL statement below (there's no
        -- way to parameterize a column name), so it's checked against the
        -- known reputation columns first - the only current caller
        -- (server/sales.lua) always passes fixed literal keys, but this
        -- keeps it safe even if a future caller doesn't.
        if repFieldSet[field] and delta and delta ~= 0 then
            MySQL.update(('UPDATE st_dealership_reputation SET %s = LEAST(100, GREATEST(0, %s + ?)) WHERE dealership = ?')
                :format(field, field), { delta, dealershipName })
        end
    end

    -- recompute overall as the average of the tracked sub-metrics
    MySQL.update([[
        UPDATE st_dealership_reputation SET overall = (
            customer_service + pricing + honesty + vehicle_quality + financing_rep + sales_experience + after_sales_support
        ) / 7 WHERE dealership = ?
    ]], { dealershipName })
end

lib.callback.register('st_dealership:server:getReputation', function(src, dealershipName)
    return MySQL.single.await('SELECT * FROM st_dealership_reputation WHERE dealership = ?', { dealershipName })
end)
