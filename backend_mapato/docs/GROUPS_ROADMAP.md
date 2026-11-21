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
