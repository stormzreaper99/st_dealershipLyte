Config = Config or {}

Config.Financing = {
    enabled = true,

    -- Term options offered to customers (months)
    terms = { 12, 24, 36, 48, 60 },

    -- Base APR by "credit tier". Credit score is pulled from a simple
    -- server-tracked history (see server/financing.lua) unless another
    -- resource (banking script) is wired in via GetPlayerCreditScore export.
    aprByTier = {
        { min = 750, max = 999, apr = 0.039 },
        { min = 650, max = 749, apr = 0.069 },
        { min = 550, max = 649, apr = 0.099 },
        { min = 0,   max = 549, apr = 0.159 },
    },

    minDownPaymentPercent = 0.10,    -- 10% minimum down
    maxLoanToValue         = 1.10,   -- can finance up to 110% (tax/fees) of price
    maxTermMonths          = 60,

    -- One financed "month" = 24 real-world hours (so a 36-term loan takes
    -- 36 real days to pay off if never paid early). Every payment-cycle
    -- calculation in server/financing.lua uses this instead of a literal
    -- calendar month.
    monthLengthHours = 24,

    -- Missed-payment / repossession rules. A payment counts as missed
    -- immediately once its due date passes (no grace before the
    -- dealership is notified) - repoGraceDays is how much real-world time
    -- the customer then has to make ANY payment before the vehicle
    -- becomes eligible for repossession. This is explicitly real days,
    -- not scaled to the 24-hours-per-month clock above.
    repoGraceDays = 3,

    -- How often (ms) the background sweep checks whether any
    -- missed-payment vehicle is currently out of its garage, for the
    -- live location tracking shown in the Financing panel.
    repoTrackingIntervalMs = 20 * 1000,

    -- Minimum in-game "credit score" required for approval at all
    minApprovalScore = 400,
}

return Config.Financing
