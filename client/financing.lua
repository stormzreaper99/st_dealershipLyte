--- Server asks every client "do you have a vehicle with this plate loaded
--- right now" when a manager pings a financed vehicle's location. Only
--- the first reply counts (server-side), so it's fine if multiple clients
--- have it streamed in and all reply.
RegisterNetEvent('st_dealership:client:locateVehicleRequest', function(requestId, plate)
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) then
            local vehPlate = GetVehicleNumberPlateText(veh):gsub('^%s+', ''):gsub('%s+$', '')
            if vehPlate == plate then
                local coords = GetEntityCoords(veh)
                TriggerServerEvent('st_dealership:server:locateVehicleResponse', requestId, { x = coords.x, y = coords.y, z = coords.z })
                return
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Customer-side loan repayment
--
-- There was previously no way for a customer to pay a car loan at all -
-- ST.MakeLoanPayment existed as an export but nothing in the resource ever
-- called it, so every financed vehicle ran to its grace period and got
-- repossessed. This is an ox_lib menu rather than another NUI view so it
-- works anywhere, not just standing at a dealership.
-- ---------------------------------------------------------------------------

local function money(n)
    return Utils.FormatMoney(tonumber(n) or 0)
end

local function payLoan(loan, amount)
    local ok, result = lib.callback.await('st_dealership:server:payMyLoan', false, loan.id, amount)
    if ok then
        lib.notify({
            title = 'Car Payment',
            description = result and result.status == 'paid_off'
                and 'Paid in full - the vehicle is yours outright.'
                or ('Payment accepted. Remaining balance: %s'):format(money(result and result.balance or 0)),
            type = 'success',
        })
    else
        local reasons = {
            insufficient_funds = "You don't have that much on you.",
            not_your_loan = 'That loan is not yours.',
            not_found = 'That loan is no longer active.',
            invalid_amount = 'Enter a valid amount.',
        }
        lib.notify({ title = 'Car Payment', description = reasons[result] or 'Payment failed.', type = 'error' })
    end
end

local function openLoanDetail(loan)
    local due = math.min(tonumber(loan.monthly_payment) or 0, tonumber(loan.balance) or 0)

    lib.registerContext({
        id = 'st_dealership_loan_detail',
        title = ('%s - %s'):format(loan.model or loan.vin, money(loan.balance)),
        menu = 'st_dealership_my_loans',
        options = {
            {
                title = ('Make scheduled payment (%s)'):format(money(due)),
                description = ('APR %.1f%% over %s months'):format((tonumber(loan.apr) or 0) * 100, loan.term_months or '?'),
                icon = 'fa-solid fa-money-bill',
                onSelect = function() payLoan(loan, due) end,
            },
            {
                title = ('Pay off in full (%s)'):format(money(loan.balance)),
                icon = 'fa-solid fa-flag-checkered',
                onSelect = function() payLoan(loan, tonumber(loan.balance)) end,
            },
            {
                title = 'Pay a custom amount',
                icon = 'fa-solid fa-pen',
                onSelect = function()
                    local input = lib.inputDialog('Car Payment', {
                        { type = 'number', label = 'Amount', min = 1, max = math.ceil(tonumber(loan.balance) or 1), required = true },
                    })
                    if input and input[1] then payLoan(loan, math.floor(input[1])) end
                end,
            },
        },
    })
    lib.showContext('st_dealership_loan_detail')
end

function ST.OpenMyLoans()
    local loans = lib.callback.await('st_dealership:server:getMyLoans', false) or {}

    if #loans == 0 then
        lib.notify({ title = 'Car Payments', description = "You don't have any active vehicle loans.", type = 'inform' })
        return
    end

    local options = {}
    for _, loan in ipairs(loans) do
        local overdue = tonumber(loan.missed_payments) or 0
        options[#options + 1] = {
            title = ('%s  -  %s owed'):format(loan.model or loan.vin, money(loan.balance)),
            description = loan.status == 'defaulted'
                and 'DEFAULTED - this vehicle is eligible for repossession. Pay now to stop it.'
                or (overdue > 0
                    and ('%d missed payment(s). Next due: %s'):format(overdue, tostring(loan.next_due_at))
                    or ('Next payment %s, due %s'):format(money(loan.monthly_payment), tostring(loan.next_due_at))),
            icon = loan.status == 'defaulted' and 'fa-solid fa-triangle-exclamation' or 'fa-solid fa-car',
            iconColor = loan.status == 'defaulted' and '#e5484d' or (overdue > 0 and '#f5a524' or nil),
            arrow = true,
            onSelect = function() openLoanDetail(loan) end,
        }
    end

    lib.registerContext({ id = 'st_dealership_my_loans', title = 'My Vehicle Loans', options = options })
    lib.showContext('st_dealership_my_loans')
end

RegisterCommand('myloans', function()
    ST.OpenMyLoans()
end, false)

CreateThread(function()
    TriggerEvent('chat:addSuggestion', '/myloans', 'View and pay off your financed vehicles')
end)
