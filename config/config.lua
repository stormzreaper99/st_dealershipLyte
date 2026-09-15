Config = Config or {}

Config.Framework = 'qbx_core'
Config.Target = 'ox_target'
Config.Debug = false
Config.AdminPermission = 'st_dealership.admin'
Config.CurrencySymbol = '$'

Config.Money = {
    playerAccount = 'bank',
    fallbackAccounts = { 'cash' },
    societyProvider = 'auto',
    providerPriority = { 'Renewed-Banking', 'qb-banking', 'fd_banking', 'okokBanking', 'qb-management' },
    financedChargesDownPaymentOnly = true,
}

Config.PurchaseGarage = nil
Config.MarketIntervalMs = 30 * 60 * 1000

Config.ConditionParts = {
    'engine', 'transmission', 'suspension', 'brakes',
    'tires', 'electrical', 'body', 'interior',
    'cooling', 'drivetrain',
}
Config.RepairThreshold = 70
Config.TitleStatuses = { 'clean', 'salvage', 'rebuilt', 'lemon', 'flood' }

Config.Departments = {
    sales = { label = 'Sales', perms = { 'sell', 'negotiate', 'testdrive', 'tradein_offer' } },
    finance = { label = 'Finance', perms = { 'approve_financing', 'manage_loans', 'collect_payments' } },
    service = { label = 'Service', perms = { 'inspect', 'repair', 'install_mods' } },
    inventory = { label = 'Inventory Manager', perms = { 'purchase_inventory', 'move_inventory', 'set_pricing' } },
    management = { label = 'Management', perms = { 'hire', 'fire', 'configure_commissions', 'manage_finances' } },
    owner = { label = 'Owner', perms = { 'all' } },
}

Config.ZoneTypes = {
    perimeter = { label = 'Property Perimeter', shape = 'poly', icon = 'fa-solid fa-draw-polygon' },
    office = { label = 'Owner / Manager Office', shape = 'poly', icon = 'fa-solid fa-door-closed' },
    management_pc = { label = 'Management PC', shape = 'point', icon = 'fa-solid fa-desktop', interactable = true },
    customer_showroom = { label = 'Customer Showroom', shape = 'point', icon = 'fa-solid fa-car-side', interactable = true },
    tradein_appraisal = { label = 'Trade-In Appraisal', shape = 'point', icon = 'fa-solid fa-right-left', interactable = true },
    vehicle_display = { label = 'Vehicle Display Slot', shape = 'point', icon = 'fa-solid fa-car-side' },
    testdrive_spawn = { label = 'Test Drive Spawn', shape = 'point', icon = 'fa-solid fa-key' },
    purchase_spawn = { label = 'Purchase Spawn', shape = 'point', icon = 'fa-solid fa-flag-checkered' },
    custom = { label = 'Custom Zone', shape = 'point', icon = 'fa-solid fa-location-dot', interactable = true },
}

Config.StaffGrades = {
    { level = 0, label = 'Sales (grade 0)' },
    { level = 1, label = 'Service (grade 1)' },
    { level = 2, label = 'Finance / Inventory (grade 2)' },
    { level = 3, label = 'Management (grade 3)' },
    { level = 4, label = 'Owner (grade 4)' },
}

Config.UITheme = {
    primary = '#d6b36a',
    secondary = '#8e9aad',
    background = '#090b0f',
    surface = '#11151c',
    surfaceAlt = '#171c25',
    text = '#f4f6f8',
    muted = '#8f98a8',
    success = '#63c48a',
    warning = '#e7b85c',
    danger = '#e16b6b',
    border = 'rgba(255,255,255,.08)',
    radius = '16px',
    blur = '18px',
    shadow = '0 24px 80px rgba(0,0,0,.45)',
}

Config.DefaultGradeRequirements = {
    sales = 0,
    finance = 2,
    service = 1,
    inventory = 2,
    management = 3,
    owner = 4,
}

return Config
