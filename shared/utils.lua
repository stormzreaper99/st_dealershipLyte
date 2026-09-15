Utils = Utils or {}

function Utils.GenerateVIN()
    local chars = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789' -- VIN-safe charset (no I/O/Q)
    local vin = 'ST-'
    for _ = 1, 8 do
        local idx = math.random(1, #chars)
        vin = vin .. string.sub(chars, idx, idx)
    end
    return vin
end

function Utils.Round(value, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    return math.floor(value * mult + 0.5) / mult
end

function Utils.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utils.FormatMoney(amount)
    local formatted = tostring(math.floor(amount + 0.5))
    local k
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return (Config and Config.CurrencySymbol or '$') .. formatted
end

-- Average of a part-condition table, e.g. {engine=90, brakes=70, ...}
function Utils.AverageCondition(parts)
    local total, count = 0, 0
    for _, v in pairs(parts) do
        total = total + v
        count = count + 1
    end
    if count == 0 then return 100 end
    return Utils.Round(total / count, 1)
end

return Utils
