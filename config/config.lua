Config = Config or {}

-- ---------------------------------------------------------------------------
-- GENERAL
-- ---------------------------------------------------------------------------
Config.Framework = 'qbx_core'      -- Qbox
Config.Target = 'ox_target'
Config.Debug = false

-- Any player granted this ACE permission gets full Owner-level access to
-- EVERY dealership (Settings, Dashboard, sell/hire/etc.) regardless of
-- their job or grade there, plus access to /admindealership. This is a
-- specific permission node (not a bare group name) so it resolves the
-- same reliable way `command.newdealership` already does - grant it with:
--   add_ace group.admin st_dealership.admin allow
-- (swap group.admin for whatever your admin group is actually called)
Config.AdminPermission = 'st_dealership.admin'

-- Currency shown in NUI/chat, does not affect math
Config.CurrencySymbol = '$'

-- ---------------------------------------------------------------------------
-- MONEY (see server/money.lua)
-- ---------------------------------------------------------------------------
Config.Money = {
    -- Which player account customers pay from / get paid into by default.
    -- 'cash' | 'bank' | 'crypto'
    playerAccount = 'bank',

    -- If the default account can't cover a purchase, these are tried in
    -- order before the sale is refused. Set to {} to only ever use the
    -- account above.
    fallbackAccounts = { 'cash' },

    -- Where dealership (society) balances live.
    --   'auto'     - use the first running provider in providerPriority
    --   'internal' - always use st_dealership_accounts (no banking script)
    --   or force one by name: 'Renewed-Banking', 'qb-banking',
    --   'qb-management', 'okokBanking', 'fd_banking'
    societyProvider = 'auto',

    -- Checked in this order when societyProvider = 'auto'. Reorder to
    -- change which one wins if you run more than one.
    providerPriority = { 'Renewed-Banking', 'qb-banking', 'fd_banking', 'okokBanking', 'qb-management' },

    -- Whether a customer paying cash/bank for a financed vehicle only pays
    -- the down payment up front (true) or the whole price (false - the
    -- loan then exists purely as a repayment schedule to the dealership).
    financedChargesDownPaymentOnly = true,
}

-- Which qbx_garages garage new purchases get registered to when
-- qbx_vehicles is installed (see server/ownership.lua). Must match one of
-- your actual garage names - if left nil, purchases fall back to the old
-- non-persistent spawn-and-drive-off behavior with a console warning.
Config.PurchaseGarage = nil

-- ---------------------------------------------------------------------------
-- FACTORY ORDER DELIVERY (the truck-and-trailer run for factory orders)
-- ---------------------------------------------------------------------------
Config.FactoryDelivery = {
    -- The real Rockstar-canon combo used for vehicle-transport scenes in
    -- the base game - hauler (semi cab) + tr4 (car-carrier flatbed).
    truckModel = 'hauler',
    trailerModel = 'tr4',

    -- Where the pickup ped and the delivery is - one fixed location
    -- shared by every dealership (the "factory"), not per-dealership.
    -- x, y, z, heading (heading is for the ped, not required precision).
    pickupLocation = vector4(1201.0, -3199.0, 6.0, 90.0),

    -- The two cars loaded onto the trailer once the order is picked up -
    -- purely cosmetic (frozen, locked, invincible), never given to
    -- anyone or made driveable, just visual flavor for the trip back.
    cargoCars = { 'asea', 'asbo' },

    -- Local offsets (relative to the trailer entity) where the cargo cars
    -- above get attached, one slot per car in cargoCars, nose-to-tail
    -- along tr4's flatbed - these are a best-effort estimate for tr4's
    -- actual deck, not measured in-game, so you'll likely want to nudge
    -- them (particularly z, the height) once you see it for real.
    trailerSlots = {
        { x = 0.0, y = -2.6, z = 1.05, heading = 0.0 },
        { x = 0.0, y = 2.0, z = 1.05, heading = 0.0 },
    },
}

-- How many factory orders one dealership can have in flight at once.
-- Ordering charges the dealership up front and is allowed to overdraw, so
-- this is what stops that being used to run the account arbitrarily negative.
Config.MaxPendingFactoryOrders = 10

-- How often (ms) the aging + market passes run
Config.AgingIntervalMs   = 15 * 60 * 1000    -- every 15 minutes -> +1 "day" on lot
Config.MarketIntervalMs  = 30 * 60 * 1000    -- every 30 minutes -> recompute demand/prices

-- Vehicle "days on lot" thresholds
Config.Aging = {
    normal   = 7,
    aging    = 30,
    slow     = 60,
    problem  = 90,
}

-- Condition categories tracked per vehicle. Each starts at 100 for a brand
-- new/factory-ordered vehicle. Used vehicles get randomized/inspected values.
Config.ConditionParts = {
    'engine', 'transmission', 'suspension', 'brakes',
    'tires', 'electrical', 'body', 'interior',
    'cooling', 'drivetrain',
}

-- Overall condition (average of parts) below this is flagged "needs repair"
-- in the UI / inspection report.
Config.RepairThreshold = 70

-- Title statuses a vehicle can carry
Config.TitleStatuses = { 'clean', 'salvage', 'rebuilt', 'lemon', 'flood' }

-- Departments / job grades allowed to use each permission.
-- Maps to qbx_core job grade names configured per dealership job.
Config.Departments = {
    sales = {
        label = 'Sales',
        perms = { 'sell', 'negotiate', 'testdrive', 'tradein_offer' },
    },
    finance = {
        label = 'Finance',
        perms = { 'approve_financing', 'manage_loans', 'collect_payments' },
    },
    service = {
        label = 'Service',
        perms = { 'inspect', 'repair', 'install_mods' },
    },
    inventory = {
        label = 'Inventory Manager',
        perms = { 'purchase_inventory', 'move_inventory', 'set_pricing' },
    },
    management = {
        label = 'Management',
        perms = { 'hire', 'fire', 'configure_commissions', 'manage_finances', 'order_inventory' },
    },
    owner = {
        label = 'Owner',
        -- 'all' short-circuits ST.HasPermission for ANY perm string, so the
        -- owner grade can always reach configure_dealership/lighting/zones
        -- below without listing them out individually.
        perms = { 'all' },
    },
}

-- ---------------------------------------------------------------------------
-- CUSTOM LIGHTING (owner-placed)
-- ---------------------------------------------------------------------------
Config.LightTypes = {
    point = { label = 'Point Light',  defaultRange = 8.0,  defaultBrightness = 4.0,  defaultRadius = 5.0,  hasDirection = false },
    spot  = { label = 'Spot Light',   defaultRange = 15.0, defaultBrightness = 8.0,  defaultRadius = 4.0,  hasDirection = true  },
    flood = { label = 'Flood Light',  defaultRange = 25.0, defaultBrightness = 12.0, defaultRadius = 12.0, hasDirection = true  },
}

-- Lights only get drawn (DrawLightWithRange/DrawSpotLightWithShadow run
-- every frame, so distance-culling matters for performance) within this
-- radius of the player.
Config.LightRenderDistance = 60.0

-- ---------------------------------------------------------------------------
-- CUSTOM ZONES (owner-placed)
-- ---------------------------------------------------------------------------
Config.ZoneTypes = {
    perimeter        = { label = 'Property Perimeter',   shape = 'poly',  icon = 'fa-solid fa-draw-polygon' },
    office           = { label = 'Owner/Manager Office',  shape = 'poly',  icon = 'fa-solid fa-door-closed' },
    management_pc    = { label = "Owner's PC",             shape = 'point', icon = 'fa-solid fa-desktop', interactable = true },
    customer_showroom = { label = 'Customer Inventory Viewing', shape = 'point', icon = 'fa-solid fa-car-side', interactable = true },
    tradein_appraisal = { label = 'Trade-In Appraisal',    shape = 'point', icon = 'fa-solid fa-right-left', interactable = true },
    vehicle_display  = { label = 'Vehicle Display Slot',  shape = 'point', icon = 'fa-solid fa-car-side' },
    testdrive_spawn  = { label = 'Test Drive Spawn',      shape = 'point', icon = 'fa-solid fa-key' },
    purchase_spawn   = { label = 'Purchase Spawn',        shape = 'point', icon = 'fa-solid fa-flag-checkered' },
    photo_ped_spawn  = { label = 'Preview Photo Ped Spawn', shape = 'point', icon = 'fa-solid fa-camera' },
    photo_car_spawn  = { label = 'Preview Photo Car Spawn', shape = 'point', icon = 'fa-solid fa-camera-retro' },
    order_truck_spawn  = { label = 'Factory Order Truck Spawn', shape = 'point', icon = 'fa-solid fa-truck', interactable = true },
    order_receive_zone = { label = 'Factory Order Receive Zone', shape = 'point', icon = 'fa-solid fa-warehouse', interactable = true },
    custom           = { label = 'Custom Zone',           shape = 'point', icon = 'fa-solid fa-location-dot', interactable = true },
}

-- ---------------------------------------------------------------------------
-- STAFF GRADES (display labels for the Hire dropdown in Dealership Ops)
-- ---------------------------------------------------------------------------
Config.StaffGrades = {
    { level = 0, label = 'Sales (grade 0)' },
    { level = 1, label = 'Service (grade 1)' },
    { level = 2, label = 'Finance / Inventory (grade 2)' },
    { level = 3, label = 'Management (grade 3)' },
    { level = 4, label = 'Owner (grade 4)' },
}

-- ---------------------------------------------------------------------------
-- VEHICLE PREVIEW PHOTOS (requires the `screenshot-basic` resource)
-- ---------------------------------------------------------------------------
Config.VehiclePhotos = {
    -- 'server' (default) - the server asks the client for the capture and
    --   handles storage/upload itself. The Discord webhook stays on the
    --   server, and the image travels over screenshot-basic's HTTP channel
    --   instead of a net event, so NO SIZE LIMIT APPLIES. Use this.
    -- 'client' - the old behaviour: the client captures, resizes and sends
    --   the image up through a callback event. Subject to the size limit
    --   and the resize/quality-ladder settings further down.
    captureMode = 'server',

    -- ---- Discord upload -------------------------------------------------
    -- The webhook URL is NOT set here. A webhook is a credential, and
    -- anything in config/ is shipped to every connecting client. Put it in
    -- server.cfg instead, using `set` (never `setr`, which replicates to
    -- clients):
    --
    --     set st_dealership:photoWebhook "https://discord.com/api/webhooks/..."
    --
    -- With it set, only the resulting Discord CDN link is stored in the
    -- database. Without it, the photo is stored as a base64 data URI -
    -- which is fine on captureMode 'server', just heavier on the database.
    -- Passed to screenshot-basic, whose documented signature is
    -- requestScreenshot(options?, cb) / requestScreenshotUpload(url,
    -- field, options?, cb). 'jpg' is the only sensible choice when
    -- webhookUrl is nil; PNG is far too large to send.
    encoding = 'jpg',

    -- Quality used for the resize, and the first rung of the ladder below.
    quality = 0.6,

    -- THE setting that actually fixes "photo too large". screenshot-basic
    -- always captures at the player's native resolution, so a 1440p or 4K
    -- client produces a data URI far too big for a server event no matter
    -- how far quality drops. With this on, the capture is resized in the
    -- NUI page (which, unlike Lua, can decode an image) down to maxWidth
    -- before it's measured or stored. Leave it on unless you've set
    -- webhookUrl and specifically want full-resolution uploads.
    downscale = true,
    maxWidth = 960,   -- width of the stored photo in pixels; 640 if still too big

    -- Fallback only, for when downscale is off or the NUI resize fails:
    -- re-capture at each of these qualities until one fits the budget.
    qualityLadder = { 0.6, 0.4, 0.25, 0.15, 0.08 },

    -- Only used by captureMode = 'client'. Prefer the server convar above:
    -- anything set here is visible to every player on the server.
    webhookUrl = nil,

    -- Final safety net for the base64 path: refuse to send anything larger
    -- than this (bytes) rather than letting it blow past FiveM's net event
    -- limit, which is what made photos appear to save and then never
    -- appear. Ignored when webhookUrl is set.
    maxDataUriBytes = 150000,
}

-- Minimum grade (qbx job grade level) required per department, per dealership
-- job. Overridden per-dealership in config/dealerships.lua if needed.
Config.DefaultGradeRequirements = {
    sales      = 0,
    finance    = 2,
    service    = 1,
    inventory  = 2,
    management = 3,
    owner      = 4,
}

return Config
