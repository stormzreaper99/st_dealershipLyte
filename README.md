# st_dealership

Premium Qbox vehicle dealership software for FiveM using `qbx_core`, `ox_lib`, `ox_target`, and `oxmysql`.

## Included

- Full-screen dealership application with a premium automotive UI
- Dealership-specific branding and theme colors
- Live physical vehicle inventory with VINs, mileage, condition, titles and inspection reports
- Customer showroom and vehicle profiles
- Cash purchases and financing
- Negotiation / offers
- Credit scores and manual financing requests
- Missed-payment tracking and repossession eligibility/completion
- Vehicle ownership registration and spawning
- Trade-in appraisal and acquisition
- Vehicle inspection history
- Employee commissions and staff management
- Test drives
- Display vehicle slots
- Dealership management and operational zones
- Dealer auctions
- Supply-based market pricing
- MrNewbVehicleKeys compatibility
- Vehicle preview images entered as normal HTTP/HTTPS image URLs

## Removed

The resource no longer contains the factory-order workflow, factory delivery truck/trailer, factory-order or receive zones, custom dealership lighting system, dealership-to-dealership inventory transfers, vehicle aging/degradation, aging clearance sales, laptop frame UI/assets, dealership reputation/rating system, or global sales-statistics dashboard.

## Dependencies

- `qbx_core`
- `oxmysql`
- `ox_lib`
- `ox_target`

## Installation

1. Run `sql/install.sql` for a fresh database.
2. For an existing installation, run `sql/migrate_v4_dealership_refactor.sql` once.
3. Configure dealerships in `config/dealerships.lua`.
4. Configure financing and commissions in `config/financing.lua` and `config/commissions.lua`.
5. Start the resource after its dependencies.

## Vehicle photos

Employees with inventory/pricing permission can enter an image URL for a vehicle. The resource stores the URL in `photos_json`; no screenshot capture, photo zones, base64 capture pipeline, or Discord webhook is required.

## Vehicle keys

If `MrNewbVehicleKeys` is running, purchased/test-drive vehicles use its documented `GiveKeysByPlate` / `RemoveKeysByPlate` exports. Other supported key resources retain their existing compatibility paths.

## Database migration

`migrate_v4_dealership_refactor.sql` removes legacy tables for factory orders, dealer transfers, custom lighting and dealership reputation, removes the old `days_on_lot` field, and normalizes any historical `factory_order` acquisition source to `wholesale_in`.
