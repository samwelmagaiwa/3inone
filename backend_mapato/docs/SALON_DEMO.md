# The demo salon (for showing the app)

`php artisan salon:demo` makes **Glow Beauty Lounge**: a whole salon with months of believable work, so the screens read like a real business.
It is a business of its own and never mixes with a real one.

## What it makes

- An owner (Neema Mushi), an accountant (Rehema Kimaro) and six stylists with their own strengths: a rising star, one who slips, a newcomer
  finding their feet, a nail technician, a lash and makeup artist.
- 150 days of visits by default (about ten a day, busy Fridays and Saturdays, a payday rush at month end), clients who come back at their own
  pace, discounts with reasons, cash, M-Pesa, Mixx by Yas, Airtel Money, HaloPesa and bank transfer, a little credit.
- Spending (rent, LUKU, water, internet, supplies, marketing), salaries and commissions paid, a profit target, a monthly target per stylist,
  equipment with services due and overdue, next week's bookings, client reviews and a couple of complaints.

Everything goes **through the app's own endpoints with the clock set back to each day**, so every figure (stock, receipts, commissions, reports,
the stylists page) is what the app really works out. Nothing is typed into the database by hand. The same `--seed` makes the same salon.

## Safety

- It only adds rows that belong to the demo owner, and `--remove` deletes exactly those (and the demo people), nothing else.
- **No SMS can leave**: the SMS gateway is replaced by one that only writes to the log while it runs.
- On a live server (`APP_ENV=production`) it refuses to run without `--force`, because it then adds a business to the real database.
- Sign-in keys used to make the data are deleted when it finishes; the people sign in with the password it prints (shown once, kept nowhere).

## Commands

```bash
php artisan salon:demo                    # make it (150 days)
php artisan salon:demo --days=90 --seed=7 # a shorter, different one
php artisan salon:demo --fresh            # take the old one away and make it again
php artisan salon:demo --remove           # take it away
php artisan salon:demo --force            # needed on a live server
```

It takes a few minutes: every visit is a real request. Sign in as the owner (`demo.owner@glowbeauty.example`, phone `0700000101`) to show
everything; as the accountant (`demo.accountant@glowbeauty.example`, `0700000102`) to show what an accountant sees; or as a stylist
(`demo.asha@glowbeauty.example`, `0700000103`, and so on) to show a stylist's own view.

## What to show

Stylists page (ranking, medals, up or down against the month before, what a visit is worth, how many clients come back, targets and pace),
Money (profit and loss, cashbook), Team (payroll, attendance), Insights, Reports, the AI assistant ("who did best this month?"), the monthly
report, Customers and credit, Equipment, Appointments, and the audit trail.
