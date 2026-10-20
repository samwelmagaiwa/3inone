# Salon: the full module list (the owner's spec, 2026-10-23) and where each stands

The owner asked for ALL of this, for the Salon service only, without breaking Transport, Rental or Inventory.
This file is the source of truth: tick a box only when it is built, tested and committed. Update it in the same
commit as the work.

Rules for every item
- Salon only. New tables carry `owner_id` + `service` (see TENANCY.md / SALON.md); new routes sit behind the salon
  header (`X-Service: salon`); the shop and the other services must behave exactly as before. Every new column or
  table is guarded (`Schema::hasColumn`) so the code survives running before the migration.
- Backend test + Flutter test for each item; run the full backend and Flutter suites before a release; MariaDB
  rehearsal for each migration.
- Reuse the existing screens, colours and widgets (`InvSheetShell`, `InvStatTile`, glass cards...). Swahili and
  English both, through the translation rules (no hard-coded Swahili in lib/).
- Staff must not see other staff's income, salary or commission unless the owner gives permission.
- Three figures are always kept apart: staff REVENUE, staff COMMISSION, and CASH handed over.

Legend: [x] done  [~] partly  [ ] not started

## A. Core business
1. Dashboard & overview  [x] (owner/manager view, SalonOverviewCard) revenue today/week/month/year with profit, clients
   served, top stylists, top services, today's and coming bookings, debts, money received by channel
2. Service management  [~] add/edit/delete, price, duration, commission % or fixed amount per time, price options
   (short/medium/long), who can do it (done, tested); packages and promotional offers [ ]; category presets [ ]
3. Customers (CRM)  [~] name/phone, service history, payment history, notes (done); style/colour/nail preferences,
   photos with consent, new vs returning, birthday offers, loyalty points, feedback [ ]
4. Appointments & booking  [~] diary per day, no double booking, confirm/reschedule/cancel/no-show, SMS reminder
   (done, tested); calendar per staff, walk-in queue, deposits and cancellation policy, WhatsApp [ ]
5. Service orders & POS  [~] services + goods, stylist per line, partial payment, receipt (engine); discount with its
   reason, how paid (cash/M-Pesa/Mixx/Airtel/HaloPesa/bank) done; refunds with approval [ ] verify
6. Revenue & income  [~] per staff/service/period, money received per payment method, outstanding balances, discounts,
   cancelled sales (done, in Profit & loss and the dashboard); refunds and reconciliation against cash handed over [ ]
7. Expenses  [x] rent, salaries, products, utilities, transport, repairs, marketing, licences; supplier, date, amount,
   how paid, receipt photo, owner approval of other people's spending, totals by category (by entered-by [ ] small)
8. Staff management  [x] accounts and roles, specialization, services each may do, working days and hours, days off
   (bookings respect them), attendance with hours, active flag, ranking and history (Stylists page); photo = the account's avatar
9. Inventory & stock  [x] goods on the inventory engine (stock in/out/adjust, suppliers, alerts, expiry, valuation);
   use of products during a service, damaged/lost/used-not-sold [ ]

## B. Staff revenue & commission
10. Individual staff revenue  [x] per stylist totals net of discount; tap a name to see every transaction (client, service,
    value, discount and why, net, status, how paid, date/time, commission)
11. Commission & salary  [x] % or fixed amount per service, a person's own rate, fixed on each sale line, monthly salary,
    payments and advances, commission earned/paid/owed, payroll per month (Payroll tab)
12. Staff cash accountability  [x] own transactions only, cash collected vs handed over, expected balance, difference,
    shift open/close, owner alert on a difference; audit trail for refunds/cancellations (existing audit log) [~]

## C. Financial control & reports
13. Profit & loss  [x] service revenue + goods, cost of goods, expenses, commissions + salaries, gross and net profit,
    today/week/month/year
14. Cashbook & reconciliation  [~] daily cash exists in the engine; money received by channel (done); opening/closing
    balance, owner deposits/withdrawals, reconciliation [ ]
15. Reports & analytics  [~] revenue by staff/service/method, expenses by category, trends, best staff, popular
    services, retention, outstanding, stock valuation, export PDF/Excel [ ]
16. Notifications & alerts  [x] booking reminders (SMS to client), new booking (to the stylist), expense waiting approval,
    cash discrepancy, pay recorded (to the person), low stock (existing), daily summary SMS to the owner; pending
    payments = the existing reminders

## D. Administration, security, operations
17 Authentication [x]  18 Role-based access: owner, manager, receptionist, cashier, hair stylist, nail technician,
lash & makeup artist, accountant, stock manager [x]  19 Audit trail [~]  20 Business settings (name, logo, address,
phone, TSh, tax, receipt) [~]  21 Multi-branch [ ]  22 Backup & recovery [x]  23 Export & printing [ ]
24 Tax & accounting support [ ]  25 Feedback & complaints [ ]  26 Loyalty & promotions (points, vouchers, referrals,
packages) [ ]  27 Equipment management [ ]  28 Online customer booking [ ]  29 Marketing & retention [ ]
30 Subscription & licensing [x]

## E. Roles
Owner/Super Admin: everything. Salon Manager: bookings, staff, services, daily operations, approved reports.
Receptionist: customers, appointments, queue, service orders. Cashier: payments, receipts, cashbook, reconciliation.
Hair Stylist / Nail Technician / Lash & Makeup Artist: own services, appointments, own performance. Accountant:
expenses, financial reports, payroll, reconciliation. Stock Manager: inventory, suppliers, purchases, adjustments.
Ordinary staff never see other staff's income, salary or commission unless the owner allows it.

## F. Customer mobile app (optional, last)
Registration/login, see services/prices/photos, choose staff, book date/time, pay deposit, history, reminders,
cancel/change per policy, rate, loyalty points and offers, contact the salon. Same backend.

## G. How money flows
1 Staff serves a client: service, staff, price, client recorded. 2 Transaction opened, payment recorded (cash, mobile
money, bank, partial). 3 System updates staff revenue, cashbook, commission, stock. 4 Owner dashboard: revenue,
expenses, estimated profit, staff ranking, cash discrepancies.
Example the owner expects: per staff, per day: service, net revenue, commission 10%; tap a staff to see the
transactions behind the total; also expenses, estimated profit and cash not yet handed over.

## Build order (decided with the owner)
Phase 1 money core (items 5, 6, 7, 10, 11, 13, 14 part, dashboard additions, finish 2 and 4) ->
Phase 2 people and control (8, 12, 18 roles, 16 alerts) -> Phase 3 customers (3, 25, 26, packages, deposits) ->
Phase 4 later (27, 23 exports, 21 multi-branch, 28/F customer app, 29, 24).
