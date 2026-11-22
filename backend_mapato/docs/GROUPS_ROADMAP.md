# Groups (Vikundi) – the 5th service: analysis, design and roadmap

Status: **Phase 1 built (2026-11-22)**; phases 2–5 to come. No APK until the whole service is done (user's rule).

## Built so far

**Phase 1 – membership core (2026-11-22)**
- Server: `group_*` tables scoped per business by the tenant grammar (`TenantTables::GROUPS`, no service column);
  `App\Support\Groups\` GroupOffices (8 offices → rights), GroupAccess (owner = all rights, a member = their office's rights
  while active), GroupSettings (effective-dated values + history), GroupMembers (statuses, member numbers PREFIX-0001, NIDA
  encrypted + keyed hash for duplicates, masked without `view_sensitive`), GroupLedger (submit → verify/reject, reversal
  only, receipts RC-000001, duplicate reference refused, nobody verifies own submission or own payment), GroupAudit.
  Routes under `/api/groups` (`service:groups` + `group_right:`). Role `group_member` (not staff; billing applies).
  Members sign in with their phone (only group-member accounts, only when one account has that phone) and a one-time
  password; an owner who is also a member is tied to their own account. Exit/death/rejection switch the sign-in off.
- App: `lib/modules/groups` – GroupsHome (same frame as shop/salon: header ⋮ menu, teal page, pill footer), Home (my
  file, my money, Pay, "waiting for you"), Members (register, filters, search, paging), member file (approve/reject,
  suspend/reinstate/exit/deceased with reasons, office, sign-in, dependants, payments, history), Payments (queue, verify,
  turn down, reverse, totals), More (settings with history, officers, activity log). Yes/No card before every change;
  green/red/orange by what the action does; en/sw throughout. Sign-in field accepts email or phone.
- Tests: `tests/Feature/GroupsMembershipTest.php` (13), `test/groups_phase1_test.dart` (7).
- Deployed 2026-11-22 (migration `2026_12_03_000100_create_groups_tables` ran on the live MariaDB after a backup).

**Phase 2 – money core (2026-11-22)**
- Server: contribution types (monthly on a day / once / per event), raising a call creates one obligation per active member
  (idempotent, unique per member+type+period); what is paid is READ from verified payments that name the obligation (never
  stored); udhuru (exemption) with reason, never for oneself (`grant_exemptions`: chair, deputy); promises (state read: due /
  missed / kept, never change a balance); ledger categories `savings` (in; withdrawals out) , `contribution` (tied to an
  obligation, never more than owed incl. waiting payments), `expense` (out, payee, no member); money OUT needs
  `record_payouts` (treasurer) and someone else's verification; balance checks run again at verification; statements
  with running balance; summary: cash on record, month expected/collected, overdue, spent. `groups:daily` (09:00 TZ, one
  job per group): raises the month's monthly contributions, and -- only if the group switched `sms_reminders` on -- texts
  due-in-3-days / overdue (day 1 then weekly) / promise day, claimed in `group_reminders` so never twice, no amounts unless
  `sms_show_amounts` is on.
- App: Contributions section (types, call a month/event, owing/overdue/paid/excused/promises, record payment / promise /
  udhuru from a line), member Home (what I owe → pay it, promise, savings, statement), statement screen, payment form
  (contribution choice, savings, withdrawal only when savings are known), group expense form, fuller Payments summary,
  settings switches for reminder texts. Footer shows 4 sections by priority + menu.
- Tests: `tests/Feature/GroupsMoneyTest.php` (7), `test/groups_phase2_test.dart` (5).
- Deployed 2026-11-22 (migration `2026_12_04_000100_add_groups_money_core` ran on the live MariaDB after a backup).

**Phase 3 – loans and welfare (2026-11-22)**
- Loan terms are group settings with NO default for the rate (% per month) and method (flat / reducing): nobody can apply
  until both are set; each loan copies the terms it was applied under. Also `loan_max_months`, `loan_guarantors`.
- Flow: member applies (eligible = active, shares paid when required, terms set; ceiling = savings × multiplier − other
  running loans; one open application at a time) → guarantors accept/decline (borrower can add another) → projects
  committee (`recommend_loans`: Mwenyekiti wa Miradi, Kamati ya Miradi) recommends an amount ≤ asked and ≤ ceiling →
  chair/deputy (`approve_loans`) approve at that amount or less → treasurer (`record_payouts`) pays out (a
  `loan_disbursement` transaction, exactly the approved amount, once) → someone else verifies → loan ACTIVE, schedule made
  from that day (monthly instalments). Repayments (`loan_repayment`, never more than owed incl. waiting) are applied
  interest first then principal, instalment by instalment, read from verified rows (never stored). Reject with reason
  at any step before payout; borrower can withdraw. Nobody recommends/approves/rejects/pays out their own loan. A
  payout reversed before any repayment puts the loan back to approved; after repayments it cannot be reversed.
  Portfolio: disbursed, principal and interest outstanding apart, interest received, arrears, overdue count.
- Welfare: kinds of help with a usual amount (`manage_settings`); member asks (type, beneficiary, relationship, date,
  private description, amount); chair/deputy (`approve_benefits`) approve with amount or reject with reason; treasurer
  pays (`welfare` transaction = approved amount, once); paid only when verified by someone else; description shown only
  to the member, deciders and payers; never one's own request.
- App: Loans section (portfolio, waiting per step, by stage), loan file with each officer's step, My loans (eligibility
  sum, apply with guarantors, answer guarantees), Welfare section, My welfare (ask for help), kinds of help, loan terms
  in settings, Home card "My loans / Welfare" and waiting lines.
- Tests: `tests/Feature/GroupsLoansWelfareTest.php` (6), `test/groups_phase3_test.dart` (6).
- Deployed 2026-11-22 (migration `2026_12_05_000100_add_groups_loans_and_welfare`).

**Phase 4 – assets and hiring out (2026-11-22)**
- Asset register (`manage_assets`: chair, deputy, secretary): code, name, usable count, condition, value and storage place
  (private: only managers and the asset's keeper), keeper = any active member, shown to members or not, hire rate and late
  rate per unit per day (empty = not for hire / no late charge — never assumed). The count changes only through events
  (damage, loss, repair, recount up/down, retire, maintenance cost), each with its reason.
- Hire: member asks (or keeper/officer writes down a hire for a member or someone outside the group) → availability over
  the dates (approved + handed-over hires hold units; one still out holds them until today) → the KEEPER of that asset
  (any office) or a manager confirms or declines (never their own) → paid (`hire` payment, verified by someone else) →
  handed over only once paid → back: returned + missing = handed over, damaged ⊂ returned; late charge = overdue days ×
  late rate × units; damaged and missing leave the usable count (events) → damage/loss charge decided case by case by
  `decide_hire_charges` (chair, deputy), 0 allowed → closed when settled. Days: setting `hire_days_rule` both (collection
  and return day, default) or between.
- App: Assets section (hires by stage, register), asset file with history and changes, asset form, hire file with each
  step, member "Hire from the group" (price for the days and free count before asking), waiting lines, days rule in
  settings.
- Tests: `tests/Feature/GroupsHireTest.php` (5), `test/groups_phase4_test.dart` (4).
- Deployed 2026-11-22 (migration `2026_12_06_000100_add_groups_assets_and_hire`).

**Phase 5a – dividends, meetings, notices, texts (2026-11-22)**
- Dividends: the formula is chosen per run, never assumed — base `closing` (savings incl. dividends at the period end)
  or `average` (day-by-day average over the period); method `rate` (rate% of the base; refused if the total passes the
  approved profit) or `share` (the approved profit shared by base). Members active and joined by the period end. Prepared
  as a DRAFT with every line by `prepare_dividends` (treasurer), approved and POSTED by `approve_dividends` (chair, deputy)
  — never the person who prepared it. Posting writes verified `dividend` rows (own category, counted in the savings
  balance, so loans see them); a period overlapping a posted run is refused.
- Meetings: `call_meetings` (chair, deputy) calls (optional SMS to all active members) and cancels with a reason;
  `record_meetings` (secretary, assistant secretary, chair, deputy) records attendance + minutes once it has started
  (correctable, logged). Members see meetings and whether they attended.
- Notices: `post_announcements` (chair, deputy, secretaries), to all or officers only, optional expiry; taken down by
  expiring (logged). Texts: `send_texts` (chair, deputy, secretary) to all / officers / overdue / chosen; the estimate
  (people, SMS parts) is shown before sending; sent in the queue (`SendGroupMessageJob`, each recipient claimed once,
  group's own SMS switch and limit).
- App: "Meetings" section for everyone (meetings, notices, texts), meeting file with attendance/minutes, dividends (runs,
  prepare form, run with lines, post/discard), "My dividends", next meeting and notices on Home, sections load on first open.
- Tests: `tests/Feature/GroupsDividendsMeetingsTest.php` (5), `test/groups_phase5a_test.dart` (4).
- Deployed 2026-11-22 (migration `2026_12_07_000100_add_groups_dividends_meetings_messages`).

**Phase 5b – invitations, guests, tree, documents, reports (2026-11-22)**
- Invitation codes (8 letters/digits, unique across all groups so a code finds its group): every active member has an
  own code (made on first ask; an applicant using it gets that member as referrer); `manage_members` makes group codes
  (no referrer) and can stop any; a member can stop their own.
- Public, no sign-in, rate-limited (`/api/public/groups/{code}`): the group's name + inviter's first name + what is for
  hire (nothing else); apply to join (same duplicate checks, consent required → a normal application, source
  invitation/group_code); ask to hire (availability checked → a normal requested hire for the keeper). Written as the
  code's group (`TenantContext::runAs`). App: "Have a group code? Join a group" link on the sign-in page.
- Referral tree: officers get the whole tree (flat nodes the app nests, search with the path from the top, growth by
  month); a member gets their own branch. Applications appear only once approved.
- Photos and papers per member, private (`group_documents`, signed links); ID copies only uploaded/seen by
  `view_sensitive`; photo becomes the member's photo.
- Reports for a period (`view_finance`): members by status/joined, verified money in/out per kind, contributions,
  loans now, meetings held; CSV exports (members register: NIDA masked without `view_sensitive`; payments of a period),
  BOM for Excel, cells starting with = + - @ written as text, each export logged.
- Tests: `tests/Feature/GroupsInvitationsRecordsTest.php` (6), `test/groups_phase5b_test.dart` (4).
Source requirement: `GROUPS_MEG_BLUEPRINT.md` (Mongolandege Economic Group, MEG, 22 members). MEG is the first customer;
the service is built for **any** savings / economic group (VICOBA, VSLA, SACCOS-style groups, office and family groups).

## 1. Decision

Add a 5th service **`groups`** ("Vikundi" / "Groups"), next to transport, rental, inventory and salon.
Everything MEG listed as a number is a **per-group, effective-dated setting**, never code:

| MEG value | Becomes the group setting |
|---|---|
| Joining fee TZS 80,000 | `joining_fee` |
| Project shares TZS 200,000 | `share_amount`, `shares_required_for` (membership / loans / nothing) |
| Loan ceiling 3 × eligible savings | `loan_multiplier` |
| Dividend 2% on savings | `dividend_rate` + `dividend_formula` (closing balance / average) |
| Chair TZS 300 per chair per day | per-asset `daily_rate`, `late_rate`, `billing_rule` |

A setting change keeps its old value with the date it stopped (history), so old calculations stay explainable.

## 2. How it differs from the other 4 services (the new work)

1. **The customers sign in.** In the other services only the owner and staff sign in. In a group, every member does, and
   sees only their own records. Needs: member accounts at scale, sign-in by phone or member number (many members have
   no email), the `member` role seeing "my" data only, and member numbers per group.
2. **A ledger that is never edited.** Other services use Trash / soft delete. Here a posted entry is never deleted or
   changed; a mistake is fixed by a linked reversal. Separate categories: joining fee, shares, savings, each
   contribution, loan principal, loan interest, welfare, rental income, dividends, expenses.
   Recommendation: a **member sub-ledger first** (not full double-entry accounting).
3. **Submitted vs verified.** A member's payment (with its reference, as already done for non-cash payments) is only
   *pending* until the Treasurer verifies it; only then does it touch a balance. Plus duplicate-reference checks.
4. **Maker-checker and many approvers.** Chairperson, Deputy, Secretary, Treasurer, Asset keeper (chairs), Loan
   committee, Member, Guest. Nobody verifies their own payment or approves their own loan/benefit.
5. **Loans with schedules.** Eligibility (shares paid, ceiling = eligible savings × multiplier, existing debt), guarantor
   accept/decline, committee recommendation, approval, disbursement, flat or reducing-balance interest, schedule,
   repayments, arrears, statements.
6. **Welfare, dividends, referral tree, meetings/announcements, chair hire** (see the phases).

### 2a. The group's roles (given by the user 2026-11-22 – these replace the blueprint's role list)

| Role (Kiswahili) | English | Responsibility |
|---|---|---|
| Mwenyekiti | Chairperson | Approves (anaidhinisha) and calls meetings (kuita vikao) |
| Makamu Mwenyekiti | Deputy Chairperson | Stands in for the Chairperson |
| Mweka Hazina | Treasurer | Approves money matters; keeps all the financial records |
| Mweka Hazina Msaidizi | Assistant Treasurer | Helps the Treasurer |
| Katibu | Secretary | Coordinates the group's affairs (anaratibu mambo ya chama) |
| Katibu Msaidizi | Assistant Secretary | Helps the Secretary |
| Mwenyekiti wa Miradi | Projects Chairperson | Oversees all the group's loans and projects |
| Kamati ya Miradi | Projects Committee | Works with the Projects Chairperson on loans and projects (the blueprint's "Loan Committee") |
| Mwanachama | Member | Own records, payments, applications |

Open: the deputies' and assistants' exact powers (assumed: same screens, act when the main officer is away), and whether the
blueprint's chair keeper / asset custodian is a separate role or a duty given to a member.

## 3. What is reused (already in the app)

| Need | Reuse |
|---|---|
| Multi-business separation | Tenancy (`TenantContext`, owner_id scoping) – the group is a business |
| Plans, billing, 402 page | PlanCatalog / billing (add `groups` to `config/billing.php` services) |
| Staff rights as switches | `App\Support\Access\Modules` catalog pattern (`grp_*` keys) + role defaults |
| SMS, sender names, SMS switch, counter/limit | SmsService::sendFor, SmsQuota, business SMS switch – unchanged |
| Reminders that run every night | `RunsPerBusiness` + `RunBusinessTaskJob` (contribution due, loan installment, promises) |
| Payment references | the non-cash reference rule (web + mobile) |
| Audit trail | `inventory_audit_log` / AuditTrail service |
| Receipts / statements / PDF | the existing receipt and report exports |
| Debts and "promise to pay" | ideas from debt reminders and old debts (owner money tools) |
| AI advice | the assistant tools (later: group health, arrears) |
| Backups, Remove this business | unchanged, they work per business |
| Locations (region/district/ward) | member address pickers |
| Language | every text through LocalizationService (en + sw) – the guard tests apply |

**Mobile only** (like Inventory): the blueprint itself says no web portal. The web app is not touched.

Not in the app today: push notifications (no FCM), biometric re-authentication, phone/member-number sign-in. In-app
notifications + SMS cover Phase 1–4; push and biometrics are later extras.

## 4. Things to be careful about

- **Law (Tanzania, Microfinance Act 2018):** community groups like VICOBA are Tier 4 and register with their local
  council; SACCOS are Tier 3. 3inone is only the software: the group itself must be registered. Say this on the group
  registration form; do not lend to the public.
- **SMS privacy:** the blueprint asks that SMS do not show debt or medical details on shared phones. Group SMS templates
  default to "you have a notice, open the app", amounts only if the group switches it on. (Shop debt reminders show the
  amount today – do not copy that default here.)
- **No money moves through the app.** Members pay by M-Pesa/bank/cash outside; the app records and verifies.
- **Members count toward cost.** Each member is a user: plan pricing for groups is probably per member band
  (e.g. up to 30 / 100 / 300 members), not only per service. To decide with the user.
- **Scale:** members sign in, so a 300-member group = 300 users. The per-request checks noted in the scaling work matter more here.

## 5. Phases (each ends deployed and tested, like the salon)

1. **Membership core** (DONE 2026-11-22) – group settings; offices and their rights; member register (NIDA masked,
   phone, address, dependants); applications → joining payments (the ledger, joining fee + shares) → verification →
   approval → member number; member sign-in by phone; member home "my records"; referrer recorded. Member photos and
   documents were left for a later phase (private uploads).
2. **Money core** – sub-ledger with categories; payment submission with reference/proof; Treasurer verification queue;
   receipts; savings; shares; contribution types and cycles → member obligations → arrears; promises; reversals;
   Treasurer and Chairperson dashboards; nightly due/overdue reminders.
3. **Loans and welfare** – eligibility, application, guarantor, committee, approval, disbursement, interest (flat /
   reducing), schedule, repayments, statements, portfolio; welfare categories, applications, approval, payment.
4. **Assets and chair hire** – asset register, custody, public asset view for guests, hire requests with date-range
   availability, keeper approval + Treasurer payment, issue/return, late and damage cases.
5. **Governance** – dividends (period close, approved pool, formula version, credit to savings, never twice), meetings
   and announcements, bulk SMS to member groups, referral tree view, invitation codes and guest self-registration,
   member photos/documents, reports and exports, audit report.

## 6. Questions for MEG before the rules are final (blueprint §27, short form)

Fee refundable? Shares compulsory for what, refundable? Savings withdrawals and who approves? Contribution amounts and
dates (JAMII, udhuru, celebration)? Who grants udhuru? Multiplier on total or unencumbered savings? Loan limits (term,
guarantors, concurrent loans)? Who recommends/approves? **Interest rate and method (not given – no default)**?
Repayment frequency, grace, penalties? Benefit amounts and dependants? Dividend formula, eligibility, cut-off,
profit deductions? Chair billing days, late rate, damage charge, one or several keepers? Accepted payment evidence?
Who may send bulk SMS? What asset details guests see? Founding members without referrer? Who sees NIDA? Sub-ledger or
full double entry?

Phase 1 needs only: fee, shares rule, roles, who approves members. Interest (Phase 3) must be answered before Phase 3.
