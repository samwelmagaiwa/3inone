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
1. Dashboard & overview  [~] revenue today/week/month/year, expenses and profit, clients served, revenue per staff,
   top services, today's and coming bookings, debts/unpaid, cash vs mobile money vs bank
2. Service management  [~] add/edit/delete, price, duration, staff commission %, price options (short/medium/long),
   who can do it (done, tested); packages and promotional offers [ ]; category presets [ ]
3. Customers (CRM)  [~] name/phone, service history, payment history, notes (done); style/colour/nail preferences,
   photos with consent, new vs returning, birthday offers, loyalty points, feedback [ ]
4. Appointments & booking  [~] diary per day, no double booking, confirm/reschedule/cancel/no-show, SMS reminder
   (done, tested); calendar per staff, walk-in queue, deposits and cancellation policy, WhatsApp [ ]
5. Service orders & POS  [~] services + goods, stylist per line, partial payment, receipt (engine); discount reason,
   refunds with approval, status pending/paid/partial/cancelled [ ] verify
6. Revenue & income  [~] per staff/service/period; per payment method (M-Pesa, Mixx by Yas, Airtel Money, HaloPesa,
   bank, cash), advances and balances, discounts/refunds/voids, reconciliation [ ]
7. Expenses  [ ] rent, salaries, products, utilities, transport, repairs, marketing, licences; supplier, date,
   amount, category, notes, receipt photo, approval, reports by category/date/entered-by
8. Staff management  [~] accounts and roles exist; specialization, photo, services each may do, work schedule and
   days off, attendance/hours, active flag, history and ranking [ ]
9. Inventory & stock  [x] goods on the inventory engine (stock in/out/adjust, suppliers, alerts, expiry, valuation);
   use of products during a service, damaged/lost/used-not-sold [ ]

## B. Staff revenue & commission
10. Individual staff revenue  [~] per stylist totals; tap a name to see every transaction (client, service, value,
    discount, net, payment received, method, date/time, commission) [ ]
11. Commission & salary  [~] % per service and the amount fixed per sale line (done); fixed amount per service,
    per-staff overrides, monthly salary, salary advances, commission earned/paid/owed, payroll summary, report for a
    period [ ]
12. Staff cash accountability  [ ] own transactions only, cash collected vs handed over, expected balance,
    difference, shift open/close, owner alerts, audit trail for refunds/cancellations

## C. Financial control & reports
13. Profit & loss  [ ] service revenue + product sales, cost of products, expenses, commissions + salaries, gross and
    net profit, daily/weekly/monthly/annual
14. Cashbook & reconciliation  [~] daily cash exists in the engine; cash in/out, opening/closing balance, mobile
    money/bank records, owner deposits/withdrawals, reconciliation, daily summary [ ]
15. Reports & analytics  [~] revenue by staff/service/method, expenses by category, trends, best staff, popular
    services, retention, outstanding, stock valuation, export PDF/Excel [ ]
16. Notifications & alerts  [~] booking reminders (SMS); new booking, payment confirmation, low stock, expense
    approval, daily revenue summary to owner, cash discrepancy, pending payments, commission updates [ ]

## D. Administration, security, operations
17 Authentication [x]  18 Role-based access: owner, manager, receptionist, cashier, hair stylist, nail technician,
lash & makeup artist, accountant, stock manager [~]  19 Audit trail [~]  20 Business settings (name, logo, address,
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
