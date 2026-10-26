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

- Set `ANTHROPIC_API_KEY` (and optionally `ANTHROPIC_MODEL`, default `claude-sonnet-5-5`) in the server `.env`. **The owner of the server sets it; nothing in the repo does.** Without a key everything works with rule-based advice.
- What is sent: the month's figures, the month before, expense changes, stock/debt/capital position, the profit target, best products, best **customers by name**, **customers who owe by name** with amount and days, sleeping stock, and who the business owes by name. **Phone numbers are never sent** (a test checks this). Customer names are personal data of the owner's customers: tell owners the advice feature shares their figures and names with the AI provider.
- One answer is kept per business, month, language and day; the owner may ask for a fresh one `REFRESHES_PER_DAY` (5) times. If the AI fails or answers badly, the rule-based advice is shown and the page says the AI could not be reached.

## Month-end job

`php artisan inventory:month-close` (scheduled 04:30 UTC daily): remembers each shop's position, and once a month has ended tells the owner **in the app** (notification) that the report is ready and whether the profit target was reached or missed. Each is told once (`month_report_told` setting, `inventory_targets.judged_at`); a changed target is judged again. No SMS is sent (it would cost the business credit); add one if wanted.

## Rights

Debts: `inv_view_credit` or `inv_manage_products`. Report and advice: `inv_view_reports`. Setting a target: `inv_manage_settings`.

## Not covered

The salon has its own reports and is not offered these screens. Transport and Rental are unchanged.
