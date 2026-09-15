local QBX = exports.qbx_core

function ST.GetCreditScore(citizenId)
    -- Allow an external banking resource to own credit scores if present.
    if GetResourceState('st_banking') == 'started' then
        local ok, score = pcall(function() return exports.st_banking:GetPlayerCreditScore(citizenId) end)
        if ok and score then return score end
    end

    local row = MySQL.single.await('SELECT score FROM st_dealership_credit WHERE citizenid = ?', { citizenId })
    if row then return tonumber(row.score) end

    MySQL.insert('INSERT INTO st_dealership_credit (citizenid, score) VALUES (?, 600)', { citizenId })
    return 600
end

local function adjustCreditScore(citizenId, delta)
    local score = Utils.Clamp(ST.GetCreditScore(citizenId) + delta, 300, 900)
    MySQL.update('UPDATE st_dealership_credit SET score = ? WHERE citizenid = ?', { score, citizenId })
end

--- Set once a loan of theirs is ever repossessed - gates the self-service
--- (kiosk) auto-approval path. Staff-assisted sales are unaffected, since
--- a human already reviewing the deal in person is the manual check.
function ST.IsFlaggedForFinancing(citizenId)
    local row = MySQL.single.await('SELECT flagged_for_financing FROM st_dealership_credit WHERE citizenid = ?', { citizenId })
    return row and row.flagged_for_financing == 1 or false
end

local function getAprForScore(score)
    for _, tier in ipairs(Config.Financing.aprByTier) do
        if score >= tier.min and score <= tier.max then return tier.apr end
    end
    return Config.Financing.aprByTier[#Config.Financing.aprByTier].apr
end
ST.GetAprForScore = getAprForScore -- exposed for server/financingrequests.lua

local function computeMonthlyPayment(principal, apr, termMonths)
    local monthlyRate = apr / 12
    if monthlyRate == 0 then
        return principal / termMonths
    end
    return principal * (monthlyRate * (1 + monthlyRate) ^ termMonths) / ((1 + monthlyRate) ^ termMonths - 1)
end

-- Staff notifications go through ST.NotifyDealershipStaff (server/main.lua).
local notifyDealershipStaff = function(...) return ST.NotifyDealershipStaff(...) end

--- Quotes a financing offer for a vehicle before the sale is finalized.
--- Flagged customers (a past repossession) get 'requires_manual_review'
--- instead of an auto-computed offer - the NUI shows a "submit request"
--- flow for that case rather than treating it as a flat decline.
--- The single source of truth for "what financing would this customer get".
--- server/sales.lua re-runs this at sale time rather than trusting whatever
--- apr/term the NUI sends back, so this must stay side-effect free.
function ST.QuoteFinancing(buyerCitizenId, price, downPayment, termMonths)
    if not Config.Financing.enabled then return { approved = false, reason = 'disabled' } end
    if not buyerCitizenId then return { approved = false, reason = 'no_player' } end

    price = math.floor(tonumber(price) or 0)
    if price <= 0 then return { approved = false, reason = 'invalid_price' } end

    if ST.IsFlaggedForFinancing(buyerCitizenId) then
        return { approved = false, reason = 'requires_manual_review', flagged = true }
    end

    local score = ST.GetCreditScore(buyerCitizenId)
    if score < Config.Financing.minApprovalScore then
        return { approved = false, reason = 'credit_score', score = score }
    end

    downPayment = math.floor(tonumber(downPayment) or 0)
    if downPayment < 0 then downPayment = 0 end
    if downPayment > price then downPayment = price end

    local minDown = math.floor(price * Config.Financing.minDownPaymentPercent)
    if downPayment < minDown then
        return { approved = false, reason = 'down_payment_too_low', minDownPayment = minDown }
    end

    -- Only the terms actually offered in config are accepted; anything
    -- else (including a hand-crafted 999) snaps to the closest allowed one.
    termMonths = math.floor(tonumber(termMonths) or 36)
    local allowed = nil
    for _, t in ipairs(Config.Financing.terms) do
        if t == termMonths then allowed = t break end
    end
    if not allowed then
        for _, t in ipairs(Config.Financing.terms) do
            if not allowed or math.abs(t - termMonths) < math.abs(allowed - termMonths) then allowed = t end
        end
    end
    termMonths = math.min(allowed or 36, Config.Financing.maxTermMonths)

    local principal = price - downPayment
    if principal <= 0 then return { approved = false, reason = 'nothing_to_finance' } end
    if principal > price * Config.Financing.maxLoanToValue then
        return { approved = false, reason = 'loan_to_value' }
    end

    local apr = getAprForScore(score)
    local monthlyPayment = computeMonthlyPayment(principal, apr, termMonths)

    return {
        approved = true, apr = apr, termMonths = termMonths,
        downPayment = downPayment,
        principal = Utils.Round(principal), monthlyPayment = Utils.Round(monthlyPayment, 2),
        score = score,
    }
end

lib.callback.register('st_dealership:server:quoteFinancing', function(src, buyerCitizenId, price, downPayment, termMonths)
    -- Quotes are always for the CALLER, never for an arbitrary citizenid
    -- the client names - otherwise anyone could probe other players' credit.
    return ST.QuoteFinancing(ST.GetPlayerCitizenId(src), price, downPayment, termMonths)
end)

function ST.OpenLoan(contractId, citizenId, vin, principal, apr, termMonths)
    local monthlyPayment = computeMonthlyPayment(principal, apr, termMonths)

    MySQL.insert([[
        INSERT INTO st_dealership_loans
            (contract_id, citizenid, vin, principal, apr, term_months, monthly_payment, balance, next_due_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? HOUR))
    ]], { contractId, citizenId, vin, principal, apr, termMonths, Utils.Round(monthlyPayment, 2), principal, Config.Financing.monthLengthHours })
end

--- Called by a payment kiosk/phone app/or a scheduled job elsewhere. Any
--- payment (even partial) clears a missed/repo-tracking state - "until a
--- payment is made" is what stops the repo clock, not necessarily being
--- fully caught up. Fully paying off the loan closes the contract out
--- entirely: it stops appearing in the active financing list and stops
--- being swept altogether.
--- `payer` is optional: pass a citizenid/server id and that player is
--- actually charged for the payment. Omit it (the export's original
--- behaviour) to credit the loan without moving player money - that path
--- is for other resources that have already taken the money themselves.
function ST.MakeLoanPayment(loanId, amount, payer)
    local loan = MySQL.single.await([[
        SELECT l.*, c.dealership FROM st_dealership_loans l
        JOIN st_dealership_contracts c ON c.id = l.contract_id
        WHERE l.id = ? AND l.status = 'active'
    ]], { loanId })
    if not loan then return false, 'not_found' end

    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'invalid_amount' end

    -- Never let someone overpay into a refund: cap at the outstanding balance.
    amount = math.min(amount, math.ceil(tonumber(loan.balance)))

    if payer then
        if not ST.Money.CanPlayerAfford(payer, amount) then return false, 'insufficient_funds' end
        if not ST.Money.RemovePlayer(payer, amount, 'vehicle-loan-payment') then
            return false, 'insufficient_funds'
        end
    end

    local newBalance = math.max(0, tonumber(loan.balance) - amount)
    local status = newBalance <= 0 and 'paid_off' or 'active'

    MySQL.update([[
        UPDATE st_dealership_loans SET balance = ?, missed_payments = 0, missed_at = NULL, status = ?,
            next_due_at = DATE_ADD(NOW(), INTERVAL ? HOUR) WHERE id = ?
    ]], { newBalance, status, Config.Financing.monthLengthHours, loanId })

    ST.AdjustBalance(loan.dealership, amount, true, 'vehicle-loan-payment')

    if status == 'paid_off' then
        adjustCreditScore(loan.citizenid, 15)
        ST.LogVehicleHistory(loan.vin, 'loan_paid_off', { citizenid = loan.citizenid, loanId = loanId })

        local player = QBX:GetPlayerByCitizenId(loan.citizenid)
        if player then
            TriggerClientEvent('ox_lib:notify', player.PlayerData.source, {
                title = 'Loan Paid Off', description = 'Your vehicle is fully paid off - congratulations!', type = 'success',
            })
        end
    else
        adjustCreditScore(loan.citizenid, 2)
    end

    return true, { balance = newBalance, status = status }
end
exports('MakeLoanPayment', ST.MakeLoanPayment)

-- ---------------------------------------------------------------------------
-- Customer-facing repayment. Without these a financed vehicle could never
-- actually be paid off - the loan sweep would default every single one.
-- ---------------------------------------------------------------------------

lib.callback.register('st_dealership:server:getMyLoans', function(src)
    local citizenId = ST.GetPlayerCitizenId(src)
    if not citizenId then return {} end

    return MySQL.query.await([[
        SELECT l.id, l.vin, l.balance, l.monthly_payment, l.missed_payments,
               l.next_due_at, l.status, l.term_months, l.apr,
               v.model, c.dealership
        FROM st_dealership_loans l
        JOIN st_dealership_contracts c ON c.id = l.contract_id
        LEFT JOIN st_dealership_vehicles v ON v.vin = l.vin
        WHERE l.citizenid = ? AND l.status IN ('active', 'defaulted')
        ORDER BY l.next_due_at ASC
    ]], { citizenId }) or {}
end)

lib.callback.register('st_dealership:server:payMyLoan', function(src, loanId, amount)
    local citizenId = ST.GetPlayerCitizenId(src)
    if not citizenId then return false, 'no_player' end

    -- Ownership check: you can only ever pay your OWN loan.
    local loan = MySQL.single.await('SELECT citizenid FROM st_dealership_loans WHERE id = ?', { loanId })
    if not loan or loan.citizenid ~= citizenId then return false, 'not_your_loan' end

    return ST.MakeLoanPayment(loanId, amount, citizenId)
end)

--- Sweeps loans in two passes:
--- 1. Newly-overdue loans (due date passed, not yet flagged as missed) -
---    flagged immediately, no grace at all before the dealership is
---    notified, matching "as soon as a player does miss a payment".
--- 2. Already-missed loans that have now gone Config.Financing.repoGraceDays
---    real days without any payment - these become repo-eligible.
function ST.ProcessOverdueLoans()
    local newlyMissed = MySQL.query.await([[
        SELECT l.*, c.dealership FROM st_dealership_loans l
        JOIN st_dealership_contracts c ON c.id = l.contract_id
        WHERE l.status = 'active' AND l.missed_at IS NULL AND l.next_due_at < NOW()
    ]]) or {}

    for _, loan in ipairs(newlyMissed) do
        MySQL.update('UPDATE st_dealership_loans SET missed_payments = missed_payments + 1, missed_at = NOW() WHERE id = ?', { loan.id })
        adjustCreditScore(loan.citizenid, -25)

        notifyDealershipStaff(loan.dealership, 'manage_loans', {
            title = 'Missed Payment',
            description = ('A financed vehicle (VIN %s) just missed its payment. It becomes repo-eligible in %d days if unpaid.')
                :format(loan.vin, Config.Financing.repoGraceDays),
            type = 'error',
        })
    end

    local repoEligible = MySQL.query.await([[
        SELECT l.*, c.dealership FROM st_dealership_loans l
        JOIN st_dealership_contracts c ON c.id = l.contract_id
        WHERE l.status = 'active' AND l.missed_at IS NOT NULL
          AND l.missed_at < DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { Config.Financing.repoGraceDays }) or {}

    for _, loan in ipairs(repoEligible) do
        MySQL.update("UPDATE st_dealership_loans SET status = 'defaulted' WHERE id = ?", { loan.id })
        ST.IssueRepoOrder(loan)
    end
end

--- Fires once a loan actually becomes repo-eligible (repoGraceDays
--- unpaid). Live tracking (see below) only ever watches 'defaulted'
--- loans, so this is also what turns tracking on for this vehicle.
function ST.IssueRepoOrder(loan)
    ST.LogVehicleHistory(loan.vin, 'repo_order_issued', { citizenid = loan.citizenid, loanId = loan.id })
    TriggerEvent('st_dealership:repoOrderIssued', loan) -- other resources (e.g. a repo job) can hook this

    notifyDealershipStaff(loan.dealership, 'manage_loans', {
        title = 'Vehicle Repo Eligible',
        description = ('VIN %s is now repo-eligible. Its live location will show in Financing once it leaves the garage.'):format(loan.vin),
        type = 'error',
    })
end

--- Marks a defaulted loan's vehicle as recovered: closes the contract,
--- returns the vehicle to the dealership's own inventory, clears the
--- customer's qbx_vehicles ownership record for it (if qbx_vehicles is
--- installed), flags the customer for manual financing review on any
--- future request, and notifies them either way. No `src`/permission
--- check in here - that's the caller's job (see the NUI callback and the
--- export below, which are the two sanctioned ways in).
function ST.CompleteRepo(loanId)
    local loan = MySQL.single.await([[
        SELECT l.*, c.dealership FROM st_dealership_loans l
        JOIN st_dealership_contracts c ON c.id = l.contract_id
        WHERE l.id = ? AND l.status = 'defaulted'
    ]], { loanId })
    if not loan then return false, 'not_found' end

    MySQL.update("UPDATE st_dealership_loans SET status = 'repossessed' WHERE id = ?", { loanId })
    MySQL.update("UPDATE st_dealership_vehicles SET status = 'in_stock', acquisition_source = 'repo', dealership = ? WHERE vin = ?", { loan.dealership, loan.vin })
    ST.LogVehicleHistory(loan.vin, 'repossessed', { citizenid = loan.citizenid })

    if GetResourceState('qbx_vehicles') == 'started' then
        pcall(function() exports.qbx_vehicles:DeletePlayerVehicles('plate', loan.vin:sub(-8)) end)
    end

    MySQL.insert([[
        INSERT INTO st_dealership_credit (citizenid, score, flagged_for_financing) VALUES (?, 600, 1)
        ON DUPLICATE KEY UPDATE flagged_for_financing = 1
    ]], { loan.citizenid })

    local player = QBX:GetPlayerByCitizenId(loan.citizenid)
    if player then
        TriggerClientEvent('ox_lib:notify', player.PlayerData.source, {
            title = 'Vehicle Repossessed',
            description = ('Your financed vehicle (VIN %s) has been repossessed. Future financing requests will need dealership approval.'):format(loan.vin),
            type = 'error',
        })
    end

    return true
end
exports('CompleteRepo', ST.CompleteRepo)

lib.callback.register('st_dealership:server:completeRepo', function(src, dealershipName, loanId)
    if not ST.HasPermission(src, dealershipName, 'manage_loans') then return false, 'no_permission' end
    return ST.CompleteRepo(loanId)
end)

-- ---------------------------------------------------------------------------
-- Management NUI: active financing list + live/on-demand location tracking
-- ---------------------------------------------------------------------------

--- Active + defaulted loans for a dealership, joined through the sale
--- contract (loans don't carry a dealership column directly) and the
--- vehicle record (for its model - the vehicle row survives the sale as
--- status='sold', so this still resolves even long after the sale).
lib.callback.register('st_dealership:server:getActiveLoans', function(src, dealershipName)
    if not ST.HasPermission(src, dealershipName, 'manage_loans') then return {} end

    return MySQL.query.await([[
        SELECT l.id, l.citizenid, l.vin, l.balance, l.monthly_payment, l.missed_payments,
               l.missed_at, l.next_due_at, l.status, v.model
        FROM st_dealership_loans l
        JOIN st_dealership_contracts c ON c.id = l.contract_id
        LEFT JOIN st_dealership_vehicles v ON v.vin = l.vin
        WHERE c.dealership = ? AND l.status IN ('active', 'defaulted')
        ORDER BY (l.status = 'defaulted') DESC, l.next_due_at ASC
    ]], { dealershipName }) or {}
end)

local pendingLocateRequests = {} -- requestId -> coords, filled in by the first client to respond
local lastKnownLocation = {}     -- loanId (string) -> { coords, at = GetGameTimer() }, kept fresh by the sweep below

local function requestVehicleLocation(plate, timeoutMs)
    local requestId = ('%s_%d_%d'):format(plate, os.time(), math.random(1000, 9999))
    pendingLocateRequests[requestId] = false

    TriggerClientEvent('st_dealership:client:locateVehicleRequest', -1, requestId, plate)

    local waited = 0
    while pendingLocateRequests[requestId] == false and waited < (timeoutMs or 2500) do
        Wait(100)
        waited = waited + 100
    end

    local result = pendingLocateRequests[requestId]
    pendingLocateRequests[requestId] = nil
    return result or nil
end

--- Only replies to a request WE issued, only the first one, and only a
--- well-formed coordinate. Previously any client could push arbitrary
--- coords into the tracker by guessing/replaying a request id.
RegisterNetEvent('st_dealership:server:locateVehicleResponse', function(requestId, coords)
    if type(requestId) ~= 'string' then return end
    if pendingLocateRequests[requestId] ~= false then return end

    if type(coords) ~= 'table' then return end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return end
    if math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then return end

    pendingLocateRequests[requestId] = { x = x, y = y, z = z }
end)

--- On-demand fresh ping, same as before - still useful even with the
--- background sweep, since staff may want an up-to-the-second check
--- rather than whatever the last sweep cached.
lib.callback.register('st_dealership:server:pingFinancedVehicle', function(src, dealershipName, loanId)
    if not ST.HasPermission(src, dealershipName, 'manage_loans') then return false, 'no_permission' end

    local loan = MySQL.single.await('SELECT vin FROM st_dealership_loans WHERE id = ?', { loanId })
    if not loan then return false, 'not_found' end

    local coords = requestVehicleLocation(loan.vin:sub(-8))
    if coords then
        lastKnownLocation[tostring(loanId)] = { coords = coords, at = GetGameTimer() }
        return true, { coords = coords }
    end
    return false, 'not_located'
end)

--- The "live" part: for every defaulted (repo-eligible) loan, periodically
--- checks whether its vehicle is currently loaded anywhere (i.e. out of
--- the garage being driven/parked, not sitting stored away) and caches
--- the result. getRepoTracking below just reads this cache, so the
--- Financing panel's repo rows update automatically without staff having
--- to click anything - it "goes live" the moment the vehicle is pulled
--- out, matching how it was asked for.
--- Each ping blocks for up to `perPingMs`, so a server with a lot of
--- defaulted loans would otherwise spend longer sweeping than the interval
--- between sweeps and back up on itself. The list is walked in rotating
--- slices instead: every loan still gets checked, just across several
--- passes rather than all in one.
local sweepCursor = 0
local SWEEP_PER_PING_MS = 1200
local SWEEP_MAX_PER_PASS = 8

local function sweepRepoTracking()
    local defaulted = MySQL.query.await("SELECT id, vin FROM st_dealership_loans WHERE status = 'defaulted' ORDER BY id") or {}
    if #defaulted == 0 then
        sweepCursor = 0
        return
    end

    if sweepCursor >= #defaulted then sweepCursor = 0 end

    local checked = 0
    while checked < SWEEP_MAX_PER_PASS and checked < #defaulted do
        sweepCursor = (sweepCursor % #defaulted) + 1
        local loan = defaulted[sweepCursor]
        local coords = requestVehicleLocation(loan.vin:sub(-8), SWEEP_PER_PING_MS)
        if coords then
            lastKnownLocation[tostring(loan.id)] = { coords = coords, at = GetGameTimer() }
        end
        checked = checked + 1
    end
end

--- Scoped to the requesting dealership's own loans. The cache is global
--- (one sweep serves every dealership), so returning it whole would have
--- leaked every other dealership's repo locations to any manager.
lib.callback.register('st_dealership:server:getRepoTracking', function(src, dealershipName)
    if not ST.HasPermission(src, dealershipName, 'manage_loans') then return {} end

    local mine = MySQL.query.await([[
        SELECT l.id FROM st_dealership_loans l
        JOIN st_dealership_contracts c ON c.id = l.contract_id
        WHERE c.dealership = ? AND l.status = 'defaulted'
    ]], { dealershipName }) or {}

    local out = {}
    for _, row in ipairs(mine) do
        local entry = lastKnownLocation[tostring(row.id)]
        if entry then
            out[tostring(row.id)] = { coords = entry.coords, ageMs = GetGameTimer() - entry.at }
        end
    end
    return out
end)

CreateThread(function()
    while true do
        Wait(15 * 60 * 1000) -- 15 minutes - tight enough for the 24hr-per-month clock
        ST.ProcessOverdueLoans()
    end
end)

CreateThread(function()
    while true do
        Wait(Config.Financing.repoTrackingIntervalMs)
        sweepRepoTracking()
    end
end)
