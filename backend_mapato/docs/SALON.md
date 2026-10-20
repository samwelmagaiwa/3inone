# Salon service

A fourth service next to Transport, Rental and Inventory. It runs on the **same sales engine as Inventory**
(customers, sales, payments, cash, expenses, receipts, reports), so a salon gets all of that without a second copy.

## What a salon is

- A business with the service `salon` (given by a super admin, or chosen when registering). It starts as a **retail**
  business without crates (`ServiceAssignment::prepareServices`). A business that also holds Inventory keeps the kind it chose.
- `CheckInventoryPermission` opens the inventory routes to a business that has `salon` **or** `inventory`. Staff
  permissions are the same `inv_*` keys; an owner with `salon` may hand them out.
- Plans: Basic = 1 service, Standard = 2, Premium = **up to 3 of the 4** (the owner chooses which). No plan covers all four.

## Services are not stock

`inventory_products.is_service` (+ `duration_minutes`, `rebook_after_weeks`). A service has no quantity, no minimum, no
cost; it can never run out, never raises a low-stock alert, and selling, cancelling or returning it never touches stock.
A line remembers `is_service`, `staff_id` and `staff_name` (the name as it was). An item that has been sold cannot change
between product and service.

## Who served the client

Each sale line may carry `staff_id` (someone of the same business: `UserInAccount`). `GET /inventory/salon/staff` lists them.
`GET /inventory/salon/stylists?from=&to=` gives, per stylist, services, revenue, visits and clients (this month by default).
The owner and managers see everyone; anyone else sees only their own line. Known limit: a refunded service line still
counts in the stylist's revenue (the return changes the sale total, not its lines).

## A client's page

`GET /inventory/salon/clients/{id}/history` (visits, total spent, last visit, favourite service, next visit);
`PUT|PATCH /inventory/salon/clients/{id}` changes only `notes` and `sms_opt_out`.

## "Come back" reminders

Off until the owner switches it on (`GET|PUT /inventory/salon/settings`: `rebook_enabled`, `rebook_weeks`, default 4).
`php artisan salon:remind-rebooking [--dry-run]` runs every morning (06:30 UTC = 09:30 Tanzania) and, for each salon:

1. takes each client's **last service visit** (a newer visit replaces an older one; goods, walk-ins and cancelled sales are not visits);
2. the wait is the **longest** `rebook_after_weeks` of the services of that visit (a service with none uses the salon's number);
3. texts on the day the wait ends, and for **14 more days** if the job missed it; after that the visit is left alone;
4. texts each visit **once** (`inventory_rebook_reminders`, claimed before sending, released if the text fails);
5. never texts a client with no phone or who opted out, nor a business whose plan has ended (`blocksAccess()`);
6. sends under the salon's own sender name, in Swahili and English, with the right grammar ("Imepita wiki moja" / "Zimepita wiki 4").

`GET /inventory/salon/rebook/due` shows the owner who is due and whether they were texted.

## Deploying it

`./deploy.sh release` runs the migration `2026_10_21_000100_add_salon_service` (backs up first). It turns
`user_services.service_type` into a plain string (the allowed names live in `config/tenancy.php`), adds the columns above and the
reminders table. It is safe to repeat. Rehearsed on MariaDB 10.11: fresh, rollback and migrate again.

## Salon data is kept apart from the shop's (2026-10-22)

A business with both a shop and a salon has two separate sets of books on the same inventory tables. Every
`inventory_*` table has a `service` column (`inventory` or `salon`; existing rows are `inventory`, so the shop is
unchanged). The app sends `X-Service: salon` from the salon's screens only (honoured only if the user may use the
salon); the query scope then limits every statement to that service and stamps new rows with it. Unique keys (SKU,
category name, settings key, ...) are per business AND service. Settings are seeded per service; the salon is always a
retail-type book. The rebooking reminder command works inside the salon service. A super admin in salon mode sees all
salons. The migration `2026_10_22_000100_separate_salon_from_shop_data` is re-runnable; its `down()` refuses while salon
rows exist.

## Service form and stylist commission (2026-10-23)

In a salon a new item opens as a SERVICE: name, notes, price, duration, come-back weeks and the stylist's commission
percent (`inventory_products.commission_percent`). No SKU, barcode, packs, sizes or VAT. When a service line is sold with
a stylist named, the commission AMOUNT is fixed on the line (`inventory_sale_items.commission_amount`), so changing the
rate later never rewrites earnings. `GET /inventory/salon/stylists` returns `commission` per stylist and in `totals`.
Migration `2026_10_23_000100_add_service_commission`; the code tolerates it not having run yet.

## Salon money (2026-10-26)

`docs/SALON_ROADMAP.md` is the checklist. What exists now, all salon-only (`service` column, `X-Service: salon`):

- **How a client paid**: `PaymentChannels` keeps the stored method one of cash / mobile_money / bank_transfer and the
  particular channel (mpesa, mixx, airtel_money, halopesa) in `inventory_sale_payments.method_extended`.
- **Discount with a reason** (`inventory_sales.discount_reason`, required in a salon when a discount is given).
- **Stylist revenue is net of the sale's discount** (each line carries its share); `GET /inventory/salon/stylists/{id}/transactions`
  lists the lines behind a total.
- **Commission**: a service's fixed amount per time, else its percent, else the person's own rate
  (`inventory_staff_profiles`); the amount is fixed on the sale line when sold.
- **Expenses** (the shared `inventory_expenses`): supplier, how paid, receipt photo (private `salon_receipts/`), and
  approval: what the owner or a manager records counts at once, anyone else's waits (`status`); only approved
  spending is counted anywhere.
- **Payroll** (`inventory_staff_payouts`): per month, salary + commission earned - paid - advances = owed.
- **Profit and loss** and the dashboard overview come from one class, `App\Support\Salon\SalonFinance`.
- Only the owner, managers and accountants see anyone's pay or the business's money (checked in `SalonMoneyController`
  and again in the app).
