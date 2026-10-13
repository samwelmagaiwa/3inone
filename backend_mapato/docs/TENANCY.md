# Multi-business tenancy

One database, many businesses. A business owner registers, the super admin assigns the
services (transport / rental / inventory), and from then on that business — and the staff it
creates — sees only its own data. This page is the contract every service follows, how to
keep it that way when adding code, and how to deploy it safely.

## The contract (same for all three services)

1. **A business = one head + everyone created under it.** The head is an `admin`,
   `administrator` or `landlord`; members are linked through `users.created_by`
   (`User::accountHeadId()`, `accountMemberIds()`). Only `super_admin` sees every business.
2. **Records belong to the business that created them**, whoever in the business typed them in.
   The business is taken from the signed-in user, never from the request body.
3. **Another business gets "not found"** (404), for reads and writes, by id or in a list.
4. **A business only gets the services the super admin assigned** — to the user *and* to the head
   above them. Refusal is HTTP 403 with `code: service_not_assigned`.
5. **Fail closed.** If who is acting cannot be told, the query returns nothing rather than everything.

`tests/Feature/TenancyContractTest.php` runs the same seven scenarios against Transport, Rental
and Inventory. If one service drifts from the others, its case fails.

## How each service enforces it

| | Mechanism | Where |
|---|---|---|
| Single source of "who is acting" | `TenantContext` (`viewer()`, `runAs()`, `withoutScope()`) | `app/Support/Tenancy/TenantContext.php` |
| Transport | Eloquent global scope via `ScopedToAccount` / `ScopedThroughDriver` | `app/Models/Scopes`, `app/Models/Concerns` |
| Rental | The same scope, with the per-role slices (owner/staff, caretaker, tenant, vendor) in `RentalAccess`; controllers also filter explicitly | `app/Support/Tenancy/RentalAccess.php` |
| Inventory | Query-level: the DB grammar adds `owner_id = <business>` to every statement on an inventory table, stamps `owner_id` on insert, refuses statements it cannot scope (upsert, insertUsing, truncate). `exists:`/`unique:` validation rules are scoped the same way | `app/Database/Tenant*`, `app/Support/Tenancy/TenantTables.php` |
| Service gating | Middleware alias `service:<name>` and `User::canUseService()`; `inv_perm` checks it for Inventory | `app/Http/Middleware/EnsureServiceAccess.php` |

## Adding code — what you must do

- **New Eloquent model with business data (Transport / Rental):** `use ScopedToAccount` (or
  `ScopedThroughDriver`) and implement `constrainToAccount()`. `tests/Unit/TenancyGuardTest.php`
  fails if a model is neither scoped nor listed in its EXEMPT list with a reason.
- **New Inventory table:** add it to `TenantTables::INVENTORY`, give it a nullable indexed uuid
  `owner_id` in its migration, and make any unique column unique per business `(owner_id, col)`.
  `InventoryIsolationTest::test_every_inventory_table_is_registered_and_carries_an_owner_column`
  fails if the registry and the schema disagree. Shared system tables go in `UNSCOPED_INVENTORY`.
- **New route group for a service:** put `service:<name>` on it.
- **Validating a foreign id:** never plain `exists:`. Use `App\Rules\InAccount`,
  `UserInAccount` or `BlockOnProperty` (Inventory's `exists:` is scoped automatically).
- **Background jobs / commands** have no signed-in user: wrap the work in
  `TenantContext::runAs($owner, fn () => …)`, or `withoutScope()` when it genuinely spans businesses.

## Deploying to the live depot

The production database holds real data and CI runs `migrate --force` on push to `master`
(see `INCIDENT_DB_WIPE.md`). The migrations are **additive** — nullable columns, no drops — so the
previous code keeps working against the new schema, and rolling the code back is safe.

**Before pushing**

1. **Take a database backup** and check that it restores.
2. List owners holding the inventory service. Exactly one should hold it (the live depot):
   ```sql
   SELECT u.email, u.role, u.is_active FROM users u
   JOIN user_services s ON s.user_id = u.id AND s.service_type = 'inventory'
   WHERE u.role IN ('admin','administrator','landlord');
   ```
   If several, the migration gives the depot to the one whose accounts created the most sales and
   products, and logs a **warning naming all of them** — check it afterwards.
3. Admins with no services at all (a migration backfills these from their own data, but look):
   ```sql
   SELECT u.email FROM users u LEFT JOIN user_services s ON s.user_id = u.id
   WHERE u.role IN ('admin','administrator') AND s.id IS NULL;
   ```

**What the deploy does** (migrations `2026_10_12_*` and `2026_10_13_*`)

- adds `devices.created_by`, the `business_registrations` table, and backfills services for admins with none;
- adds `owner_id` to every inventory table and per-business unique indexes;
- makes settings per business (the old table is kept as `inventory_settings_legacy`);
- gives every existing inventory row to the depot owner, and moves inventory staff who belong to no
  business under that owner (each move is recorded in `tenancy_reparent_log` with the old value).

There is a **short window** — seconds — between the new code starting and `migrate` finishing in
which Inventory endpoints can error, because the code is already looking for `owner_id`.

**After deploying**

```bash
php artisan inventory:ownership-report
```

It must exit successfully (no inventory row without an owner). Then sign in as the depot owner and as
one of their staff and confirm the depot is there.

**Accounts that still use a retired default password.** Tenants, drivers, fundis and caretakers created
before this release all got the same fixed password (`tenant123`, `password123`, `caretaker123`,
`12345678`). New ones get a one-time generated password instead, shown once to whoever created them. For the
existing ones, preview and then flag them so each person must choose their own at next sign-in:

```bash
php artisan users:flag-default-passwords --dry-run
php artisan users:flag-default-passwords
```

It does not change anyone's password, so nobody is locked out, and it is safe to run twice.

**If the wrong business got the depot**

```bash
php artisan inventory:assign-owner right.owner@example.com --from=wrong.owner@example.com --dry-run
php artisan inventory:assign-owner right.owner@example.com --from=wrong.owner@example.com
```

It refuses (and says why) when the target business already has its own products or sales — two real
depots are never merged. The move is one transaction.

**If rows were left without an owner** (nobody held the inventory service at deploy time):

```bash
php artisan inventory:assign-owner owner@example.com --dry-run
php artisan inventory:assign-owner owner@example.com
```

Both commands only fill in rows with no owner / move what they say, and are safe to run twice.

**Clean-up later (by hand, after a few weeks):** `DROP TABLE inventory_settings_legacy;`

## Behaviour to know about

- Inventory settings and default crate types are now **per business**; a business gets its own defaults the
  moment it is given the inventory service.
- The inventory service can be given to more than one business (the earlier single-depot safety rail is gone,
  because the data is isolated now).
- A super admin creating inventory staff directly leaves them with no business; the data migration adopts
  existing ones, but new ones should be created by the owning admin.
- Accounts created for someone else (tenant, driver, fundi, caretaker) get a random one-time password, returned
  once as `temporary_password` in the create response (null if the creator chose one or the person already had
  an account) and flagged `must_change_password`. The app shows it in a dialog. It is deliberately not sent by SMS:
  `SmsService` only logs, and passwords must not end up in log files.
- A caretaker's properties are `rental_properties.caretaker_id`; `POST /rental/caretakers/{id}/assign` replaces
  the set (an empty list releases all) and only accepts properties of the caretaker's own business.
- The tenant's payment SMS is sent once, by `RentalService::recordPayment`, after the payment is committed.
- `SERVICE_ENFORCEMENT=false` switches service gating off in an emergency. It does not affect data isolation.

## Text messages (SMS), password reset and the phone check

`App\Services\SmsService` sends everything; what really happens is decided by the gateway bound in
`config/sms.php` (Kilakona, or just the log). Settings come from the environment, never from git:

| Variable | Meaning |
|---|---|
| `SMS_DRIVER` | `kilakona` sends for real; anything else only logs |
| `SMS_ENABLED` | `true` to actually send |
| `SMS_API_URL`, `SMS_API_KEY`, `SMS_SECRET_KEY`, `SMS_SENDER_ID` | the provider account |
| `SMS_COUNTRY_CODE` | prefix for numbers written the local way (`255`) |
| `SUPER_ADMIN_NOTIFY_PHONES` | extra numbers (comma separated) texted about new registrations |

**Registration texts** (all bilingual, Swahili then English): when a business applies, the applicant is told it
arrived and is texted the 6-digit phone code; every active `super_admin` who has a `phone_number` (plus
`SUPER_ADMIN_NOTIFY_PHONES`) is texted "new registration: business, owner, phone, services" once per number, capped
at 20 texts an hour (`sms.admin_texts_per_hour`) so fake applications cannot run up the bill; approval and
rejection text the applicant (approval names the email to sign in with). The register response carries
`code_status` (`sent` / `throttled` / `unavailable` / null): `unavailable` means text messages are off, no code
exists, and the app does not ask for one. A super admin therefore needs a phone number saved on their account to
be texted.

`docker-compose.prod.yml` passes these through, so put the real values in the `.env` next to the compose
file **on the server** (and copy the updated compose file there). Without them the app still runs, but
anything that needs a code to reach a phone is refused in production instead of pretending.

- **Password reset:** `POST /auth/forgot-password` (email + the phone on the account) texts a 6-digit code;
  nothing that proves identity is in the response, and the answer is the same whether or not the details
  matched. `POST /auth/reset-password` takes the email, the code and the new password. A code lasts 10
  minutes, allows 5 tries, is replaced by a newer one, and a new one can be requested once a minute. Only a
  keyed hash is stored (`sms_codes`). A successful reset signs every device out.
- **Registration:** the applicant is texted a code at registration and confirms it with
  `POST /auth/register/verify-phone` (`/auth/register/resend-code` sends another). The super admin sees
  `phone_verified` and approval is refused for an unconfirmed phone unless the request says
  `allow_unverified: true` on purpose (the app asks "approve anyway?").
- **Re-applying / "already pending":** only someone who knows the registration's password gets the
  "pending" or "rejected" answer or can update it; anyone else just sees "already registered".
- **Logs:** a message carrying a code is never written to a production log, and numbers are masked.

## A suspended business

Deactivating a business **owner** (`users.is_active = false`) shuts the whole business: the Sanctum hook in
`AppServiceProvider` rejects every token of their staff, drivers and tenants, login says
`business_suspended`, and password reset does not work for them. Nothing is deleted; re-activating the owner
opens it all again. **Before deploying, check nobody is working under an inactive owner today**, because
they will be locked out:

```sql
SELECT s.email AS staff, o.email AS inactive_owner
FROM users s JOIN users o ON o.id = s.created_by
WHERE o.is_active = 0 AND s.is_active = 1 AND o.role IN ('admin','administrator','landlord');
```

## Signed in on several devices

One account can be signed in on **any number of devices at the same time**, each with its own token, and
none of them is signed out because another one signed in. Rules (`config/sanctum.php`,
`App\Support\SessionPolicy`):

| Setting | Default | Meaning |
|---|---|---|
| `SANCTUM_MAX_SESSIONS` | `0` | no cap on devices (a number caps it and drops the OLDEST) |
| `SANCTUM_TOKEN_EXPIRATION_MINUTES` | unset | no fixed lifetime: a device is not timed out by age |
| `SANCTUM_IDLE_DAYS` | `365` | a device nobody used for this long is dropped; use resets the clock; `0` = never |
| `SANCTUM_REFRESH_GRACE_MINUTES` | `10080` (7 days) | how long the OLD token keeps working after the app renews it, so a phone that missed the answer is not signed out |
| `SANCTUM_REVOKE_OTHERS_ON_PASSWORD_CHANGE` | `true` | changing the password signs out the other devices, never the one it was changed on |

**Check the server's own `.env` / compose file does not set the old values** (`SANCTUM_MAX_SESSIONS=5`,
`SANCTUM_TOKEN_EXPIRATION_MINUTES=43200`), which would override these defaults and bring the limits back.

Sessions that still end, on purpose: the person signs out (that device only); an administrator deactivates or
deletes the account, or the business is suspended; a forgotten-password reset (all devices); and a password
change (the OTHER devices). Logins remain rate-limited (10 a minute per account and address) against password
guessing, which is separate from any limit on devices.

## Backup and restore (super admin only)

`POST /auth/admin/backup` writes **every** table (except sessions, caches, queues and login tokens) to
`storage/app/private/backups/` on the server; `GET /auth/admin/backup` lists them. Restore is
`POST /auth/admin/restore` with `{"filename": "...", "confirm": "RESTORE"}` (or an uploaded `backup_file`).
It first writes a `pre_restore_` snapshot of what is there now, then adds and overwrites rows matching on
`id` in one transaction; **it never deletes rows**. `full_access` staff may not use any of it.

Backups live on the same server as the data, so they do not protect against losing the server: copy them
off it. There is no automatic schedule yet.

## The business record, plans and what is unique where

**The business is a real record** (`businesses`, model `Business`). Its `owner_id` is the account head's user
id — the same value `TenantContext` calls "the business" and inventory stores in its own `owner_id` — so
nothing about how data is scoped changed: this table adds identity and billing, it does not scope anything.
One row per owner, created with the owner (`UserObserver`: any admin / administrator / landlord), filled from
the registration form, and backfilled for every existing owner by migration `…000300_backfill_businesses`
(registration name when there was one, else the owner's name; plan `free`, no end date, so nobody is put on
a clock by the upgrade). Staff, drivers, tenants and super admins have none.

| What | Where |
|---|---|
| Name, address, TIN (9 digits, stored `123-456-789`), phone, email, logo | `GET /business` (anyone in the business), `PUT /business`, `POST/DELETE /business/logo` (owner only) |
| Plan, `valid_until`, days left | in the same `GET /business` (`billing`); changed ONLY by a super admin: `PUT /admin/businesses/{id}`, and at approval (`plan`, `valid_until`) |
| Every business with owner, services, staff count; filters `status=expired\|expiring\|no_expiry`, `plan`, `q` | `GET /admin/businesses` (super admin) |

Logos are public files (`business_logos/`, random names; they are printed on receipts), at most 2 MB, jpg / png /
webp only (no SVG). Sign-in and `GET /auth/user` carry the business (`user.business`) so the app can show whose
it is without another call.

**Where the business shows up.** Transport receipts (`receipt_data.company_*`) and rental receipts
(`details.business_*`) carry the business of the driver / landlord, whoever is signed in — they used to say
"Boda Mapato". Rental texts are written as `Mama Rent: …` and end with the business's phone
(`SmsService`; the sender id is still the platform's single one, so the name is in the text). A new depot's
receipt settings start from the business (name, phone, address, TIN, email) and follow later edits of the
profile — except where the owner typed their own heading in the depot settings, which is never overwritten.

**Plans.** `config/billing.php`: plans `trial, free, basic, standard, premium`; approval starts a self-registered
business on a `trial` of `BILLING_TRIAL_DAYS` (30) unless the super admin picks otherwise. `valid_until` empty
means it never expires, and the business works through the end of that day. **Nothing is locked until
`BILLING_ENFORCE=true`.** With it on, a business is held back once `valid_until` + `BILLING_GRACE_DAYS` (7) has
passed: sign-in answers HTTP 402 `subscription_expired`, and a device that is already signed in gets the same 402
on everything except sign-out, its own profile and `/business` — **never 401, so nobody is logged out**; renewing
(a new `valid_until`) opens everything again at once on the same devices. Drivers, tenants and fundis (the
business's customers) and super admins are never held back. Turn it on only after deciding how you charge.

**What is unique where.** One rule: a value that identifies a thing *inside* a business is unique inside that
business only; a value that identifies a *person who signs in* is unique on the platform.

| Value | Unique | How |
|---|---|---|
| user **email** | across the platform | it is the sign-in name (and how a password is reset); two businesses cannot share one |
| user **phone** | inside one business | `UniquePhoneInBusiness` (compares the last nine digits, so `0743…` = `+255743…`); not a database index, because `users` has no business column |
| vehicle **plate**, driver **licence** | inside one business | `owner_id` on `devices` / `drivers` + a composite unique index `(owner_id, value)` |
| transport **receipt numbers** (`payment_receipts`, `receipts`) | inside one business | same `owner_id` + `(owner_id, receipt_number)`. Each business numbers its own receipts from 0001; with one global index the second business's first receipt of the day failed with a 500 |
| inventory names / SKUs / numbers | inside one business | `(owner_id, value)` since the inventory migration |

`owner_id` on devices, drivers and receipts is stamped when the row is created (`HasBusinessOwner`) and filled
in for existing rows from the creator chain by migration `…000200_make_numbers_unique_per_business`. It is
**not** used to decide who can see a row (the `ScopedToAccount` rules still do), and a row whose owner could not
be worked out keeps `NULL`, which the unique index treats as distinct. People are found by phone only inside
the business (a tenant by email across landlords, as before): a registration is identified by its email alone,
and a fundi is never matched to a driver who happens to share a number.

## Kinds of inventory business, selling units, sizes and colours, VAT, goods by weight

**The kind of business.** `businesses.inventory_type` is `retail`, `wholesale`, `mixed` or `depot`
(`config/inventory_types.php`; the same column on `business_registrations`). The owner picks it on the
registration form — required whenever `inventory` is among the requested services, empty otherwise — the
super admin sees it at approval and may correct it (`POST /admin/registrations/{id}/approve` with
`inventory_type`), and the owner can change it later (`PUT /business`, or the business profile screen).
`GET /inventory/settings` returns the computed `inventory_type` so the app never has to guess.

**What the kind changes — almost nothing is hard-wired.** It only decides what a business's inventory
settings *start with*, written once into that business's own `inventory_settings`
(`App\Support\InventoryDefaults`):

| Setting | Meaning | depot (the platform default) | retail | wholesale | mixed |
|---|---|---|---|---|---|
| `use_crates` | returnable packaging: the crates tab and deposits, the "empties" step at checkout | `1` | `0` | `0` | `0` |
| `sale_tier` | which price the till uses: `product` (the product's own price), `retail`, `wholesale` | `product` | `retail` | `wholesale` | `retail` |
| `prices_include_vat` | do shelf prices already contain VAT? | `1` | `1` | `1` | `1` |
| `tax_percent` | the VAT rate of a product that has none of its own | `0` | `0` | `0` | `0` |

Changing the kind later moves only the settings that are *still at the old kind's starting values*
(`InventoryDefaults::applyType`): a business that changed a setting by hand keeps it. No product, price,
stock or sale is touched. A business with no kind (older businesses, or inventory granted by hand) works as a
**depot** — the platform defaults *are* the depot — and migration `2026_10_16_000100` marks every business that
holds the inventory service as `depot`, so the upgrade changes nothing about how the live depot works.

**Selling in more than one unit.** A product has a base unit (a bottle, a piece, a gram) and any number of
selling units holding a whole number of it (a crate = 24, a kg = 1,000), each with a retail, a wholesale and,
per customer, a special price (`inventory_product_units`, `inventory_product_prices`, every price change in the
append-only `inventory_price_changes`). A sale line sent with a `unit_id` is rung up in that unit: the line's
`quantity` stays the number of **base units** (so stock, cost of goods, profit and every report are unchanged),
`unit_qty` / `unit_name` / `unit_factor` say how it was sold, and `unit_price` is the price of one selling unit.
Returns refund in the unit it was sold in. Till price: the customer's special price, else the chosen level's,
else the other level's, else the base price × what the unit holds; a depot (`sale_tier=product`) uses the
product's own price for its base unit.

**Sizes and colours** are separate stock items (own SKU, barcode and count) sharing `family_id` (the id of the
first), `variant_label` ("M / Red") and the same selling units; the name is stored as `Shirt — M / Red`.
`POST /inventory/products` accepts `variants[]`; `POST /inventory/products/{id}/variants` adds more to an
existing product; `GET /inventory/products?family_id=` lists a family.

**Goods by weight or volume.** `inventory_products.measure` is `count`, `weight` or `volume`. Weighed goods are
**stocked in grams / millilitres** and sold in grams, kilograms (factor 1,000), millilitres or litres, with the
price quoted per kg / litre. **No quantity anywhere is ever a fraction**: stock, sale lines, returns and every
count are validated as integers on the server (2.5 kg is 2,500 g), and the app's quantity boxes take digits only.
Only prices have decimals, to two places.

**VAT is optional.** `inventory_products.tax_percent`: empty = the business's `tax_percent` setting (0 unless it
set one), `0` = exempt, a number = that rate. With `prices_include_vat=1` the VAT is the share inside the price
(`line × rate / (100 + rate)`); with `0` it is added on top. The server works the VAT out per line, stores it on
the line (`tax_percent`, `tax_amount`) and sets the sale's `tax` to the sum; a return refunds the VAT together with the goods.

Migration `2026_10_16_000200` only **adds** nullable columns or columns whose default reproduces the old
behaviour, so old rows read exactly as before (an old sale line has `unit_qty` empty = sold in base units). It was
rehearsed on MySQL 8: upgrade over data, `migrate:rollback --step=2`, upgrade again, all with the legacy rows
intact.

## Private uploads (lease documents, tenant and repair photos, reports)

These used to sit in public storage, readable at `/api/files/public/...` (and `/storage/...`) by anyone who
knew or guessed the address, with no sign-in. Now:

- **New uploads go to private storage** (`storage/app/private/`, never served by the web server): lease
  documents (`agreements/<lease id>/`), tenant photos (`tenant_photos/`), repair photos (`maintenance/`) and
  generated reports (`reports/`).
- **The API gives a short-lived signed link** (`/api/files/private/<path>?expires=...&signature=...`) wherever a
  response used to carry a file address: a repair request's `photo_url`, a tenant profile's `photo_url`, each
  lease document's `url`. Only people who can already see that record get one (the usual business scoping), the
  link needs no sign-in header so the app's images work unchanged, and it stops working after
  `UPLOAD_LINK_HOURS` (6). It cannot be edited or reused for another file.
- **`/api/files/public/...` refuses those four folders** (404). House and property photos and profile pictures
  stay public on purpose (public listings); new profile pictures get a random name.
- Old files are found by the signed link in either place, so nothing breaks while they are moved.

**On the server, after deploying:**

```bash
docker exec depot_backend php artisan files:secure-uploads --dry-run          # what would be copied
docker exec depot_backend php artisan files:secure-uploads                    # copy to private; nothing deleted
# open a few lease documents / repair photos in the app to check, take a backup, then:
docker exec depot_backend php artisan files:secure-uploads --remove-originals # remove each public original whose private copy is verified
```

Until `--remove-originals` is run, the OLD files can still be read at their old public addresses (the command
only copies by default). If the server's web server also exposes `/storage` directly, that is the same files:
removing the originals closes it; as an extra layer, deny those folders in the web server config
(`location ~ ^/storage/(agreements|tenant_photos|maintenance|reports)/ { return 404; }`).

## Background work

Jobs and commands have nobody signed in, and with nobody signed in nothing is scoped: inventory queries see
every business and inserts get no owner. `tests/Unit/BackgroundWorkGuardTest.php` fails if background code
touches inventory tables without `TenantContext::runAs()` / `withoutScope()`.

## Limits that remain (not fixed)

- User emails stay unique across the platform because they are the sign-in name: the same person cannot
  work for two businesses on one email (they need a second email), and a driver who moves to another
  business needs a new login. Letting one email belong to several businesses would need a "which business?"
  step at sign-in and at password reset; it has not been built.
- A business has exactly one owner: no deputy owner, ownership transfer, or export or deletion of a business.
- Plans exist as data and a switch (`BILLING_ENFORCE`), but there is no invoicing, no payment collection and
  no per-plan limits (staff count, services): a super admin records what was paid.
- The SMS sender id is one for the whole platform; a business's name appears in the text, not as the sender.
- The role `administrator` is treated as an owner role in the code, but MySQL's `users.role` enum has no such
  value, so no such account can exist on the real database (SQLite does not enforce enums, which is why tests
  can create one). Use `admin`; if `administrator` is ever wanted, widen the enum with a migration first.
- The two-factor switch in Security settings only stores a flag: sign-in never asks for a second factor, so
  turning it on protects nothing yet.
- Turning `use_crates` off hides crates in the app (the crates tab, the deposit card, the crates report and the
  "empties" step at checkout); the crate endpoints themselves still exist and still work for that business.
- A product has one VAT rate (no per-customer or per-sale VAT exemption), and VAT is only calculated by the
  inventory till; there is no VAT return or report yet.
- Sizes and colours cannot be turned back into a single product, and changing a business's kind does not
  convert products it already has (a retail shop that was a depot keeps its crate-priced products).
- Weighed goods are limited by the whole-number rule: the smallest sellable amount is one gram / millilitre.
- `php artisan inventory:purge-test-data` deletes by `LIKE '%test%'` across all businesses and has no
  preview; review it before ever running it on real data.
