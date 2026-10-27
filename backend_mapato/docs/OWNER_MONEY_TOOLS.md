# Owner money tools (shop / depot)

What a shop owner asked for, and where it lives. All of it is per business and per service (`owner_id` + `service`), like the rest of inventory.

| Request | What was built | Where |
|---|---|---|
| Enter every debt I am owed | Old debts (`kind=receivable`) tied to a real customer (found by phone in any spelling, then by name, else created). They join the customer's credit balance, the credit check, the statement (as its opening balance) and the debtors ageing. | `App\Support\Inventory\OpeningDebts`, `CreditController` |
| Enter every debt I owe | Old debts (`kind=payable`) to a supplier or a person. They join the monthly report's "I owe" and capital. | same |
| Business and non-business expenses | `inventory_expenses.is_personal`. The categories `family` and `drawings` are always personal; any other can be switched. Personal spending is listed and totalled (`personal_total`) but is never taken off the profit. | `ExpenseController`, expenses screen |
| A full report every month | `GET /api/inventory/monthly-report?month=YYYY-MM`: sales, cost of goods, gross profit, business expenses by category, write-offs, net profit; stock at cost, owed to me, I owe, capital and its change; best products and customers, sleeping stock, who owes most. | `MonthlyFigures`, `MonthlyReport` |
| Better or worse than last month, in % | `compare` + `overall` in the same response. A month in progress is compared with the **same days** of the month before (`previous.like_for_like`), so a young month is not "down". More spending is `good: false`. Up/down/same uses a 1% band. | `MonthlyFigures::compare` |
| Profit target | `PUT /api/inventory/monthly-target {month, profit_target}` (0 clears; not for past months). Status: `not_started`, `on_track`, `behind` (by pace through the month), `reached`, `missed`. | `inventory_targets` |
| Where to improve (AI) | `GET /api/inventory/advice?month=&lang=sw|en&refresh=1`. Rules always write advice from the numbers; when `ANTHROPIC_API_KEY` is set, Claude is given the full facts and rewrites it. | `BusinessAdvisor` |

## Definitions (so the numbers are the same everywhere)

- **Sales** = total billed on sales not cancelled (cash or credit). **Cost of goods** = `unit_cost_snapshot x quantity` of those lines.
- **Net profit** = sales - cost of goods - business expenses - approved write-offs. Sale returns are not subtracted (the existing expense summary does not either).
- **Capital** = stock at cost (`inventory_products.quantity x cost_price`, services excluded) + money owed to the business (credit sales + old debts) - money the business owes (open supplier invoices + old debts). Cash in hand is not tracked, so it is not in capital.
- Months are Tanzanian calendar months (Africa/Dar_es_Salaam); sale times are stored in UTC and converted.
- Stock, debts and capital of a **past** month cannot be recomputed from today's stock, so `inventory_month_snapshots` remembers them: written whenever the report is opened for the current month and by the daily job. A month the app never watched has `position: null`; the first capital change appears once the month before has been remembered.

## The AI

- Set `GEMINI_API_KEY` (optionally `GEMINI_MODEL`, default `gemini-2.5-flash`) or `ANTHROPIC_API_KEY` (optionally `ANTHROPIC_MODEL`, default `claude-sonnet-5-5`) in the server `.env`; Gemini wins when both are set. **The owner of the server sets it; nothing in the repo does.** Without a key everything works with rule-based advice.
- What is sent: the month's figures, the month before, expense changes, stock/debt/capital position, the profit target, best products, best **customers by name**, **customers who owe by name** with amount and days, sleeping stock, and who the business owes by name. **Phone numbers are never sent** (a test checks this). Customer names are personal data of the owner's customers: tell owners the advice feature shares their figures and names with the AI provider.
- One answer is kept per business, month, language and day; the owner may ask for a fresh one `REFRESHES_PER_DAY` (5) times. If the AI fails or answers badly, the rule-based advice is shown and the page says the AI could not be reached.

## Month-end job

`php artisan inventory:month-close` (scheduled 04:30 UTC daily): remembers each shop's position, and once a month has ended tells the owner **in the app** (notification) that the report is ready and whether the profit target was reached or missed. Each is told once (`month_report_told` setting, `inventory_targets.judged_at`); a changed target is judged again. No SMS is sent (it would cost the business credit); add one if wanted.

## Rights

Debts: `inv_view_credit` or `inv_manage_products`. Report and advice: `inv_view_reports`. Setting a target: `inv_manage_settings`.

## Not covered

The salon has its own reports and is not offered these screens. Transport and Rental are unchanged.

## AI assistant (ask the business, learn the app)

`GET/POST /api/assistant`, for every service (shop/depot, salon, transport, rental). Needs `GEMINI_API_KEY`.

- **Data:** the model reads only through `App\Support\Ai\AssistantTools` (inventory/salon tools, `TransportTools`, `RentalTools`). Each tool names its service and what opens it: `inv_*` rights for shop/salon, the roles the routes admit or an explicit grant for transport/rental. A user's assistant is offered only the tools they hold (a refused tool answers "Not allowed"). Rows come through the tenant scopes, so a business only ever sees its own, a driver/tenant/caretaker only their slice, and sales are the user's own unless their role sees everyone's (`SalesVisibility`). The platform admin gets no business data.
- **Knowing the app:** `AppGuide` is a how-to guide cut to the person's services and rights and placed in the system prompt, so "how do I..." needs no lookup. Keep its menu names equal to the app's menus.
- **Speed:** one-tap suggestions (`topic` = suggestion id, offered by `GET /api/assistant`) are answered with ONE AI call: the server reads the data first. Flash models run with `thinkingBudget` 0 and a 1024-token cap.
- **Privacy/limits:** phone numbers never go to the AI (the app shows them from `cards`); off-topic questions are declined; 600-character question, 15 requests/minute, 60 questions/user/day.

## Customer story, branches for shops, written prices, receipt time

- **Customer report** `GET /api/inventory/credit/customers/{id}/report?from=&to=&group=day|week|month` (right: `inv_view_credit`). One customer for any period: purchases, sales, paid, profit and margin, what they owe now (sales plus debts from before the app), what they buy most, by day/week/month, and their whole history. Days are Tanzania days. Cost and profit are `null` unless the user holds `inv_view_reports`; a user who sees only their own sales sees this customer's sales made by themselves, but the debt is shown whole. Code: `App\Support\Inventory\CustomerReport`. The AI assistant reads it through the `customer_report` tool.
- **Branches for a shop or depot**: the salon's branch machinery now works for the `inventory` service too (`SalonBranch::available()`): `GET/POST/PUT/DELETE /api/inventory/branches` and `/api/inventory/branch-stock*` (the `/inventory/salon/...` addresses still work). The app sends `X-Branch: <id>` when a branch is chosen; a new sale is stamped with it and takes goods from that branch's shelf first; sales, expenses and the dashboard follow it. A business with no branches behaves exactly as before. The monthly report (figures, comparison, best products and customers, target status), the AI advice and the assistant's `business_report` / `expenses_summary` follow the chosen branch too (sales, cost of goods and expenses of that branch; with none chosen, the whole business). Stock, debts and capital (`position`) and write-offs stay whole-business: they are not recorded per branch. The detailed reports `daily_sales`, `sales_detail`, `product_profitability` and `collections` follow the branch; the stock reports do not (use "Goods by branch").
- **Staff by branch**: `GET /api/inventory/branch-team` lists each person with their home branch; `PUT /api/inventory/branch-team/{staffId}` `{branch_id|null}` places them (owner only, `SalonAccess::canConfigure`; the person must belong to the business, the branch must be active). It writes `inventory_staff_profiles.branch_id`, the same field the salon uses, and `SalonBranch::forNew` stamps it on that person's sales when no `X-Branch` is sent. A home branch does not confine a person: they may still choose another branch.
- **Sales by branch and by person**: `GET /api/inventory/branch-sales?from=&to=` (right `inv_view_reports`; Tanzania days, default this month): `by_branch` (each with its people), `by_staff` (each with their branches) and `total`, with sales count, sales, paid and profit; sales made with no branch are listed under a null branch. Code: `BranchTeamController`. Mobile: menu "Sales by branch and person" (second tab "People" places staff); web: "Sales by branch" and "Staff by branch" pages.
- **Written price**: `items[].unit_price` on a sale is the price charged; without it the list price is used. The mobile till and the web till let the cashier write it (it survives a price-level change; "use the usual price" takes the list price back). Profit follows the price really charged.
- **Receipt time**: the server stores UTC; both apps show times as Tanzania time (UTC+3): `parseServerTime` (mobile) and `eatDateTime` (web).
