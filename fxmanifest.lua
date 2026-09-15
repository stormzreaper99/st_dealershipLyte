fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'st_dealership'
author 'Storms Technologies'
description 'Dynamic vehicle dealership framework - inventory, acquisition, negotiation, financing, market economy'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'config/config.lua',
    'config/dealerships.lua',
    'config/financing.lua',
    'config/commissions.lua',
    'config/market.lua',
    'shared/vehicles.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/main.lua',
    'client/sync.lua',
    'client/registry.lua',
    'client/catalog.lua',
    'client/admin.lua',
    'client/zones.lua',
    'client/lighting.lua',
    'client/display.lua',
    'client/vehiclekeys.lua',
    'client/financing.lua',
    'client/vehiclephoto.lua',
    'client/factorydelivery.lua',
    'client/tradein.lua',
    'client/testdrive.lua',
    'client/purchase.lua',
    'client/nui.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/style.css',
    'web/js/app.js',
    'web/js/frame.js',
    'web/img/laptop-frame.png',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/money.lua',
    'server/registry.lua',
    'server/jobcreation.lua',
    'server/admin.lua',
    'server/catalog.lua',
    'server/staff.lua',
    'server/inventory.lua',
    'server/market.lua',
    'server/ownership.lua',
    'server/factorydelivery.lua',
    'server/sales.lua',
    'server/financing.lua',
    'server/financingrequests.lua',
    'server/trades.lua',
    'server/transfers.lua',
    'server/auctions.lua',
    'server/employees.lua',
    'server/branding.lua',
    'server/lighting.lua',
    'server/zones.lua',
    'server/display.lua',
    'server/vehiclekeys.lua',
    'server/photoupload.lua',
    'server/vehiclephoto.lua',
    'server/aging.lua',
}

dependencies {
    'qbx_core',
    'oxmysql',
    'ox_lib',
    'ox_target',
}

server_exports {
    'GetDealership',
    'AcquireVehicle',
    'SellVehicle',
    'GetDealershipInventory',
    'GetVehicleByVin',
    'AdjustVehiclePrice',
    'GetMarketPrice',
    'TransferInventory',
    'OpenAuction',
    'CompleteRepo',
    'MakeLoanPayment',
}
