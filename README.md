# st_dealership

Dynamic dealership framework for Qbox (`qbx_core`). Individual vehicle
inventory (VIN, mileage, per-part condition, title status, days on lot)
instead of a static vehicle config, plus acquisition, negotiation,
financing/repossession, dealer auctions, trade-ins, market pricing,
reputation, employee stats/commissions, and aging inventory.

## Dependencies
- `qbx_core`
- `oxmysql`
- `ox_lib`
- `ox_target`

## Install
1. Copy this resource into your resources folder as `st_dealership`.
2. Import `sql/install.sql` into your database.
3. Create a job per dealership in `qbx_core` (matching the `job` field in
   `config/dealerships.lua`) with grades that line up with
   `Config.DefaultGradeRequirements` (sales=0, service=1, finance=2,
   inventory=2, management=3, owner=4 by default — adjust either side to
   match your job's grade levels).
4. Edit `config/dealerships.lua` with real coordinates for each lot's
   blip, showroom interaction point, test-drive spawn points, and return
   point.
5. Add `ensure st_dealership` after its dependencies in `server.cfg`.
6. To let admins create dealerships in-game instead of editing
   `config/dealerships.lua`, grant the command ace permission, e.g. in
   `server.cfg`:
   ```
   add_ace group.admin command.newdealership allow
   ```

## Creating a new dealership

**Option A — in-game, no restart needed:**

```
/newdealership <name> <job> <label...>
```

- `name` — a unique one-word slug (letters/numbers/-/_ only), e.g. `moto1`
- `job` — an existing `qbx_core` job name for this dealership's staff
- `label` — everything after that, e.g. `Stormline Motorcycles`

Example: `/newdealership moto1 stormline_moto Stormline Motorcycles`

Requires the `command.newdealership` ace permission (see setup step 6
above). After running it, aim at the floor where the owner's PC should
sit and press **E** to confirm (**Backspace** cancels). That spot becomes
the dealership's showroom entry point, blip, and management PC target in
one step — the dealership is usable immediately, and its owner (job
grade 4+) can finish the rest (zones, lighting, branding) from the
Settings tab without anyone touching a config file or restarting anything.
Dealerships created this way live in `st_dealership_registry` and survive
restarts on their own.

**Option B — static config**, for dealerships you want version-controlled
or set up before the server ever starts: add an entry to
`config/dealerships.lua` as shown in setup step 4. Both kinds of
dealerships work identically everywhere else in the resource — inventory,
sales, financing, zones, lighting, branding, all of it.

## What's implemented
- Per-vehicle inventory rows (VIN, mileage, condition-by-part, title
  status, previous owners, purchase cost, asking/min price, days on lot)
- Acquisition: factory order, dealer auction win, trade-in, repossession,
  dealer-to-dealer transfer
- Used-vehicle inspection that rolls part-level condition
- Dynamic per-model market pricing driven by live supply/demand
- Negotiation flow (offer → counter → accept/reject) with financing option
- Financing: credit score, APR tiers, amortized monthly payment, missed
  payment tracking, automatic repossession order after N missed payments.
  One financed "month" = 24 real hours (`Config.Financing.monthLengthHours`),
  not a calendar month - due dates, grace period, and the repo sweep all
  run on that clock. Paying a loan off fully closes it out: it drops out
  of the active financing list, stops being swept for missed payments,
  and the buyer gets notified directly if online.
- Dealer-only auction house with bidding and automatic close/payout
- Trade-in appraisal based on live market value, mileage, and condition
- Departments/permissions mapped to qbx job grades (Sales, Finance,
  Service, Inventory Manager, Management, Owner)
- Dealership bank account balance, adjusted by every purchase/sale/payout
- Sales contracts + full per-VIN history log
- Employee stats, leaderboard, and configurable commission payouts
  (base rate + bonuses for satisfaction, financing, trade-ins, hard sells,
  monthly targets)
- Dealership reputation across 7 sub-metrics
- Vehicle aging thresholds, warnings, and a one-click clearance sale
- "Dealer Intelligence" market snapshot (trending / low-supply / oversupply)
- A full custom NUI (`web/`) for customers, employees, and owners — see
  below

## NUI
`web/` is a single-page app served from `ui_page 'web/index.html'`, opened
by walking up to a dealership and interacting with it. One app, three
role views, gated live by the player's job grade:

- **Customer** — every player gets Showroom (search/sort/filter, a
  detail slide-over with a live condition report) and Trade-In. Buying is
  self-checkout ("kiosk"): negotiate → optional financing → purchase,
  server-validated against the vehicle's real minimum price so a customer
  can never talk the UI into an under-priced deal, and no employee needs
  to be online.
- **Employee** (anyone with a Sales/Finance/Service/Inventory Manager
  perm at that dealership) — an extra "Dealership Ops" tab: full
  inventory table with inline Inspect/Adjust Price/Close Sale actions
  (closing a sale here pays commission to the acting employee), an
  Order From Factory catalog, and the dealer auction house.
- **Owner/Management** — an extra "Dashboard" tab: Dealer Intelligence
  (trending/low-supply/oversupply), aging inventory with a one-click
  clearance sale, the employee leaderboard, and the 7-metric reputation
  breakdown.

## Vehicle catalog (what dealerships can order)
The "Order from Factory" list in Dealership Ops pulls from a catalog
that's no longer fixed to `shared/vehicles.lua`'s ~10 built-in entries.
Admins (same `Config.AdminPermission` as everything else admin-side) get
a **Vehicle Catalog** tab in `/admindealership` to add, edit, or remove
orderable vehicles server-wide - not per-dealership, every dealership
shares the same catalog. Built-in entries can be edited there but not
removed (they'd just reappear on restart, loaded fresh from
`shared/vehicles.lua`); anything added through the console can be edited
or removed freely. Model must be the exact spawn code, not the display
name - there's a quick client-side sanity check (`IsModelInCdimage`)
before saving that warns if it doesn't look right, but doesn't block
saving, since a model that isn't streamed on the *admin's* client could
still be valid on the server through some other means.

`client/nui.lua` is the only file that talks to the browser — every NUI
action forwards 1:1 to an existing server callback, so the permission
checks and pricing math all still live server-side; the NUI never trusts
anything it computes itself. `client/main.lua` opens it, `client/nui.lua`
runs it, `client/tradein.lua` and `client/testdrive.lua` hold the two bits
of logic that need real game natives (reading the vehicle you're sitting
in, spawning/returning the test-drive car).


## Intentionally left as hooks, not built out
These are wired with clear extension points (events/exports) rather than
full features, since they depend heavily on your other resources or would
make this a much bigger deliverable:
- **Credit score source** — falls back to an internal table but will defer
  to `st_banking`'s `GetPlayerCreditScore` export if that resource exists
  and is started.
- **Repossession recovery** — `st_dealership:repoOrderIssued` fires when a
  loan defaults; hook this from a repo-job resource to actually locate/tow
  the vehicle, then call the `CompleteRepo` export.
- **Real odometer/condition on trade-ins** — `client/tradein.lua` currently
  randomizes mileage; swap in your garage/mechanic resource's export.
- **Manufacturer order delivery delay** — `AcquireVehicle` with
  `source = 'factory_order'` adds inventory immediately; add a delayed
  `SetTimeout`/thread in `server/inventory.lua` if you want the "2-4 game
  days" delivery window from the original spec.
- **Advertising, vehicle events, dealer-to-dealer negotiation UI** — the
  data model supports these (reputation, market data, dealer transfer
  export) but no dedicated UI/workflow is built; wire them up the same way
  as the Dashboard tab.

## Vehicle ownership (qbx_vehicles integration)
Purchases now register real, persistent ownership if `qbx_vehicles` is
installed - not just a drivable copy that vanishes if the buyer logs off.
**Set `Config.PurchaseGarage`** to one of your actual `qbx_garages` garage
names for this to work; if it's left `nil`, or `qbx_vehicles` isn't
running, purchases fall back to the old behavior (spawn a drivable copy,
hand over keys, no persistence) with a console warning so it's obvious
why.

When it's configured:
1. `exports.qbx_vehicles:CreatePlayerVehicle()` creates the DB record
   (citizenid, model, garage), so it shows up in the buyer's garage like
   any other owned vehicle, even if they never touch the copy spawned at
   the pickup point.
2. `qbx.spawnVehicle()` (from `qbx_core`'s server lib) spawns that same
   drivable copy right now, with its `vehicleid` statebag set to the new
   DB record's id - per Qbox's own developer guidelines for anything
   meant to interoperate with the rest of their ecosystem (other
   resources can look the vehicle up by that id).
3. Keys are handed over the same way as before, once the vehicle streams
   in on the buyer's client.

**Trade-ins mirror this on the way out**: accepting a trade-in also calls
`exports.qbx_vehicles:DeletePlayerVehicles('plate', ...)` for the traded
vehicle, so it doesn't linger as a phantom "still owned" car in the
trader's garage after the physical vehicle is gone. Test-drive vehicles
are unaffected either way - they're always temporary and were never
meant to touch ownership at all.

## Dealer-to-dealer trading
The Ops "Dealer Trade" subtab lets a dealership (`purchase_inventory` perm)
send one of its own in-stock vehicles to another dealership, with an
optional cash adjustment either direction. This is a **consent-gated
offer**, not an instant move - `ST.TransferInventory` itself (still
available as a plain export) is a unilateral, permission-checked-on-one-side
function only ever meant to be called once consent already exists; the NUI
never calls it directly. The vehicle is reserved the moment an offer is
sent so it can't be sold elsewhere while pending, and the target
dealership must explicitly Accept or Decline.

## Factory order delivery
Ordering from the catalog no longer creates the vehicle instantly - it
charges the dealership immediately, then queues the order for a
truck-and-trailer delivery run:

1. **`order_truck_spawn`** (a new placeable zone type, Settings > Zones) -
   interacting there claims the oldest order still awaiting pickup for
   this dealership, spawns an empty `hauler` + `tr4` (semi + car-carrier
   flatbed, the same combo Rockstar uses for vehicle-transport scenes in
   the base game), hands over keys, and sets a waypoint to
   `Config.FactoryDelivery.pickupLocation`.
2. Drive to that location, where a persistent ped is waiting. Targeting it
   ("Receive Order") **swaps the empty truck+trailer for a freshly-spawned
   loaded one** at the same spot - two cargo cars (`Config.FactoryDelivery.cargoCars`,
   default `asea`/`asbo`) already attached to the trailer bed. This is a
   swap rather than attaching cars onto the already-driven trailer, since
   a freshly-spawned pair's transform is fully known and controlled the
   moment it's created.
3. **`order_receive_zone`** (also new) back at the dealership - interacting
   there (matches however you configure the zone's interaction, target or
   press-E) finalizes the order server-side (this is what actually creates
   the vehicle - payment already happened at step 1, tracked via a new
   `skipPayment` override on `ST.AcquireVehicle` so it isn't charged
   twice), then despawns the truck, trailer, and both cargo cars.

Only one delivery run can be active per player at a time, and only the
player who claimed a run can turn it in - if someone else could complete
it, whoever placed the order could get scooped by another staff member
mid-delivery.

**`Config.FactoryDelivery.trailerSlots`** (the cargo cars' attachment
offsets) are a best-effort estimate, not measured against the real `tr4`
model in-game - you'll likely want to nudge the height/spacing once you
see it for yourself.

## Financing management & repossession
The Dashboard's **Active financing** panel (visible to Finance department
grade+ and up, not just Owner) lists every open and defaulted loan:
customer, vehicle, balance, monthly payment, next due date, missed
payments, and a status column.

**Missed payments** are flagged the moment a due date passes - no grace
before the dealership is notified (every online player with `manage_loans`
at that dealership gets a toast). From there, the customer has
`Config.Financing.repoGraceDays` (3 by default) **real days** to make any
payment at all before the vehicle becomes repo-eligible - this is
explicitly real time, not scaled to the 24-hours-per-month financing
clock. Any payment at all resets the clock, not just being fully caught up.

**Once repo-eligible**, a background sweep (`Config.Financing.repoTrackingIntervalMs`,
20s by default) checks whether that vehicle is currently loaded anywhere
in the world - the same plate-matching broadcast the manual "Ping
location" button already used, just running automatically now. The
Financing panel's status column updates live off this cache while the
Dashboard is open, so it effectively "goes live" the moment the vehicle
leaves its garage, without staff needing to click anything. There's still
no true qbx_garages integration behind this - "out of the garage" is
approximated as "loaded on someone's client," which in practice is the
same thing.

**Recovering it**: once staff physically get to the vehicle (however you
handle that in-game - towing, driving it back, whatever), **Mark
recovered** in the panel closes the loop server-side: the contract closes
out as `repossessed`, the vehicle returns to the dealership's own
inventory, its `qbx_vehicles` ownership record is cleared (if installed),
and the customer is flagged (`st_dealership_credit.flagged_for_financing`)
for manual review on any future financing.

**Flagged customers** can still request financing, but the instant kiosk
auto-approval is skipped for them - the negotiation UI instead submits a
request into a new **Financing requests** panel (visible to
`approve_financing` - Finance department), where staff must explicitly
Approve or Deny each one. The vehicle is reserved the moment a request is
submitted so it can't be sold elsewhere while pending. Approving runs the
exact same sale-completion logic as any other financed sale (commission
included, credited to whoever approved it); denying just releases the
vehicle back to inventory and notifies the customer.

## Vehicle keys, test drives, and display vehicles

**Keys** — both a completed purchase and the start of a test drive call
`ST.GiveKeysForVehicle` (`client/vehiclekeys.lua`), which tries known key
scripts in priority order and stops at the first one it finds running:
`qbx_vehiclekeys` (Qbox's own, checked first), `qb-vehiclekeys`,
`qs-vehiclekeys`, `wasabi_carlock`, `cd_garage`, `mk_vehiclekeys`,
`okokGarage`, `t1ger_keys`. If none of those are running, it fires a
generic `st_dealership:client:vehicleKeysNeeded` event so you can wire in
whatever you actually use with a one-line handler. Removal (test drive
ending) is confirmed for `qbx_vehiclekeys` and `wasabi_carlock`; a couple
of others are inferred by naming symmetry with their own give call
rather than independently confirmed - worth a quick test with whichever
one you run. The vehicle still gets deleted either way even if a given
script's removal call isn't wired up, so a test drive never leaves a
real car behind, just a possible orphaned key entry for a car that no
longer exists.

**Test drives** — end immediately the moment the player is no longer in
the vehicle (got out, got thrown out, etc.), not just on timeout or
`/returntestdrive`. There's a short grace window right after being warped
in so the warp itself isn't mistaken for "already got out," but once
driving has started, exiting ends it instantly - no grace period, per
how this was asked for.

**Display vehicles** — assign an in-stock vehicle (by VIN) to any
`vehicle_display` zone from the new "Display Slots" tab under Dealership
Ops. The assigned car spawns at that zone (distance-culled like lights),
locked, frozen, and invincible - `SetEntityInvincible` +
`SetVehicleCanBeVisiblyDamaged(false)` for damage immunity, door lock
state 2 (can't be entered) for anyone, on every client. It's spawned
unnetworked per-client (same reasoning as the lighting system: purely
decorative and stationary, no need to sync ownership across players).
Selling the assigned vehicle clears its display slot automatically.

## Vehicle preview photos
Requires the [`screenshot-basic`](https://github.com/citizenfx/screenshot-basic)
resource (official Cfx.re resource) - not bundled, and not a hard
`dependencies{}` requirement in the manifest (so the rest of `st_dealership`
still works fine without it), but this one feature won't function until
it's installed and started.

Anyone with `set_pricing` (Inventory Manager grade+, Owner, or an admin)
gets a "Take photo" / "Retake preview photo" button on any vehicle in
Dealership Ops > Inventory or its detail panel. Pressing it:
1. Teleports them to a `photo_ped_spawn` zone
2. Spawns that exact vehicle model (frozen, locked, invincible - purely a
   photo prop, same treatment as display vehicles) at a `photo_car_spawn`
   zone, chosen at random if more than one exists
3. Forces first-person view so they're looking through the character's
   eyes, not the chase cam
4. Waits for **Enter** (capture) or **Backspace** (cancel) - they can
   still walk around and look around freely in between to line up the shot
5. Captures the screenshot, cleans up the car, and teleports them back to
   the dealership's `office` zone (its centroid, since office is a
   polygon zone - see below) either way, cancelled or not

By default (`Config.VehiclePhotos.webhookUrl = nil`) the photo is
captured as a raw base64 data URI and stored directly in
`st_dealership_vehicles.photos_json` - works immediately with zero setup
beyond installing `screenshot-basic`, at the cost of bloating that table
over time as more vehicles get photographed. Set `webhookUrl` to a
Discord webhook URL instead to upload there and store only the returned
CDN link, keeping the database small. Once set, the photo shows up
everywhere that vehicle is displayed - Showroom cards, the detail
slide-over, and the Ops inventory table.

Both new zone types (`photo_ped_spawn`, `photo_car_spawn`) are placed the
same way as any other point zone, in Settings > Zones.

## Laptop frame
The NUI now renders inside a laptop frame (`web/img/laptop-frame.png`) rather
than filling the whole screen. The whole composition (frame + app) is
authored at 1920x1080 and scales as one uniform unit to the client's actual
resolution - exactly 1:1 at 1920x1080, scaled up proportionally above that,
scaled down (never cropped or distorted) below it. Separately, the app UI
itself - which was built assuming a full 1920x1080 canvas, not the smaller
area inside the laptop's screen - gets shrunk to fit the screen cutout
specifically (currently ~58% size, since the cutout is smaller than the full
frame). Both scale factors are computed in `web/js/frame.js` and update live
on window resize.

If you swap in a different frame image, update the four percentages in
`web/css/style.css`'s `#screen-cutout` rule (`left`/`top`/`width`/`height`)
to match your new image's transparent screen cutout, as fractions of its
total width/height. This only works cleanly for a flat, straight-on
rectangular cutout - a screen shown at an angle or with perspective can't be
matched by a plain CSS rectangle without warping the UI itself.

## Owner configuration (in-game, no config edits needed)
Any player with the Owner department (grade 4+ on the dealership's job by
default) gets a Settings tab in the NUI with three sections. Anyone
granted `Config.AdminPermission` (`st_dealership.admin` by default) also
gets full Owner-level access to every dealership automatically, regardless
of job or grade, plus access to `/admindealership` - grant it in
`server.cfg`:
```
add_ace group.admin st_dealership.admin allow
```
(swap `group.admin` for whatever your admin group is actually called).
Changes are
saved to the database immediately and apply live to everyone on the
server - a restart doesn't lose anything.

- **Branding** — rename the dealership and change its blip (sprite/color/
  scale) on the fly.
- **Zones & targets** — place: property perimeter, owner/manager office,
  the owner's PC (opens the Management Dashboard), a customer inventory
  viewing point, a trade-in appraisal point, vehicle display slots,
  test-drive spawns, purchase spawns, or a generic custom zone.
  - **Perimeter and office** are walked out corner-by-corner: press
    **E** at each corner, **Backspace** undoes the last one (or cancels
    if none are placed yet), **Enter** finishes once you have 3+.
  - **Owner's PC, customer inventory viewing, trade-in appraisal, and
    custom zones** are point zones with a configurable interaction:
    **Target** (an `ox_target` prompt) or **Press E** (a plain proximity
    prompt) - pick whichever fits your server when you save the zone.
  - Once any `testdrive_spawn` or `purchase_spawn` zones exist they're
    used instead of the static `config/dealerships.lua` spawn list
    automatically.
- **Lighting** — place point, spot, or flood lights directly in the
  world: aim with the camera, scroll to adjust distance, **hold Left
  Ctrl + scroll for height**, Q/E to rotate (spot/flood direction), Enter
  to confirm, then set color/brightness/range/radius/shadow in a
  follow-up prompt. Lights persist to `st_dealership_lights` and are
  redrawn every frame for any player within `Config.LightRenderDistance`
  (FiveM has no persistent light entity, so this is a per-frame draw
  call, distance-culled for performance). Each light can be turned
  on/off individually from its row in the Lighting list, and a "Locate"
  button on each row drops a bright marker at its exact position for a
  few seconds - useful for confirming placement even in daylight, when
  the actual light glow can be hard to spot.

The default `config/dealerships.lua` showroom target and blip still work
out of the box before an owner configures anything - zones/lighting are
additive, not required to get a working dealership.

## Upgrading an existing install (schema changes)
If you already had zones set up before this update, run
`sql/migrate_zones_v2.sql` once against your database (adds the
`interaction` and `points_json` columns `st_dealership_zones` now needs),
then restart. Any perimeter/office zones created before this change used
the old box (center + length/width/height) shape, which no longer
applies - delete and re-place those two specifically with the new
corner-by-corner tool; everything else is unaffected.

Also run `sql/migrate_display_v2.sql` (a plain `CREATE TABLE`, safe on a
fresh install too) to add the table vehicle display slot assignments use.

Also run `sql/migrate_catalog_v2.sql` (also a plain `CREATE TABLE`) for
the admin-managed vehicle catalog.

Also run `sql/migrate_repo_v2.sql` for the repossession/financing-request
system - adds `missed_at` to loans, `flagged_for_financing` to credit
records, and the new financing requests table.

Also run `sql/migrate_trade_delivery_v2.sql` for dealer-to-dealer trading
and the factory delivery system - two new tables, both plain
`CREATE TABLE`s.

## Reconnect sync
Zones, lights, and display vehicle assignments all sync to your client
when the resource first sees you - both via `client/sync.lua` requesting
its own data on load (the reliable path, since it only depends on
`QBCore:Client:OnPlayerLoaded`, which is documented on both `qb-core` and
`qbx_core`) and via a best-effort server-side broadcast on
`QBCore:Server:PlayerLoaded` for anyone else already listening for that.
If you ever place a zone/light/display and it works immediately in that
same session but disappears after a restart, that's this sync path -
worth checking client (F8) and server console for anything mentioning
`requestFullSync`, `syncZones`, `syncLights`, or `syncDisplays`.

## Commands
| Command | Who | Does |
|---|---|---|
| `/newdealership <name> <job> <label>` | `command.newdealership` ace | Creates a new dealership; ends with a raycast placement for the owner's PC (E to confirm, Backspace to cancel) |
| `/dealershipowner <dealership> [playerId]` | `command.newdealership` ace | Bootstraps a dealership's first owner - sets the target (must be online) to that dealership's job at the Owner grade. Leave `playerId` off (or use `me`) to make yourself the owner. Needed once per new dealership since nobody has the job yet after `/newdealership` |
| `/admindealership` | `Config.AdminPermission` ace (`st_dealership.admin` by default) | Opens an admin console listing every dealership (config and runtime-created) with balance, source, and actions: Manage (opens that dealership's own Settings screen), set balance directly, assign an owner, and delete (runtime-created dealerships only) |
| `/returntestdrive` | Anyone on an active test drive | Ends it early and deletes the loaner vehicle |

Once a dealership has an owner, they (or anyone with the Management-tier `hire`/`fire` permission) can hire and fire staff themselves from the **Staff** tab under Dealership Ops in the NUI - no more admin commands needed for day-to-day hiring. That tab only lists/targets **online** players (hire by server ID); firing an offline player isn't currently supported.

## Key exports
Client: `GetDealership`, `GetVehicleByVin`, `GetMarketPrice`
Server: `AcquireVehicle`, `SellVehicle`, `GetDealershipInventory`,
`GetVehicleByVin`, `AdjustVehiclePrice`, `GetMarketPrice`,
`TransferInventory`, `OpenAuction`, `CompleteRepo`, `MakeLoanPayment`

## Vehicle spawning

Every vehicle this resource puts in the world goes through `ST.SpawnVehicle`
in `client/main.lua`. It lives there rather than in its own file because six
other client files call it — a separate file is one more thing that has to be
present and listed in `fxmanifest.lua`, and a stale manifest took every
caller down with it. `main.lua` is loaded by definition if the resource runs
at all.

It exists for one reason worth knowing about:

A freshly created vehicle is, as far as the engine is concerned, ambient
traffic. The population system will delete it whenever it decides there are
too many vehicles around — which is why an unclaimed spawn appears for a
second and then vanishes. `SetEntityAsMissionEntity` is what marks it as
scripted and off-limits to that cleanup.

The helper also sets `SetVehicleHasBeenOwnedByPlayer` (so the game doesn't
treat it as an abandoned car), clears the hotwire requirement, and on
networked spawns allows network-ID migration — without which the vehicle
belongs to the spawning client alone and disappears when they leave its
scope.

`ST.DeleteVehicle` is the counterpart: `DeleteEntity` is unreliable on
anything the engine still considers ambient, so the claim is reasserted
before deleting.
