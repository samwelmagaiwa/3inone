# MONGOLANDEGE ECONOMIC GROUP (MEG)
## Mobile Application – Full Functional Blueprint, Architecture & Process Flows
**Document type:** Business Requirements & Functional Architecture  
**Version:** 1.0  
**Prepared for:** Mongolandege Economic Group (MEG)  
**Platform scope:** Mobile application only (Android and iOS)  
**Status:** Requirements baseline for validation and implementation planning

---

## Document Purpose

This document consolidates the MEG requirements into a complete mobile-application blueprint. It defines the business modules, user roles, permissions, information structure, workflows, business rules, reporting requirements, operational controls, and end-to-end processes.

This is a functional and business architecture document. It intentionally excludes source code, programming languages, frameworks, infrastructure products, and technology-stack decisions.

## 1. Executive Summary

Mongolandege Economic Group (MEG) intends to replace paper-based member files and manual financial records with one secure mobile application. The application will manage the complete member lifecycle and the group's core operations: membership registration, referral history, joining fees, project shares, savings, contributions, loans, repayments, welfare benefits, dividends, financial transactions, chair rentals, group assets, meetings, announcements, reminders, and management reports.

The application will be used by members and authorized group officials through role-specific mobile interfaces. A person who has not yet joined MEG may access limited public information inside the mobile application, submit a membership application, and request chair rental services. Sensitive member and financial information will remain accessible only to authenticated and authorized users.

The application must distinguish money by its business purpose. Joining fees, project shares, member savings, monthly/community contributions, welfare contributions, loan principal, loan interest, rental income, dividends, and operating expenses must not be mixed into one undifferentiated balance.

The current operating figures supplied for this blueprint are:
- Current membership: 22 members.
- Joining fee: TZS 80,000.
- Fixed initial project shares: TZS 200,000.
- Loan eligibility ceiling: up to three times eligible savings, subject to all other rules and approval.
- Dividend proposal: 2% based on each member's eligible savings, credited to that member's savings account, subject to the approved dividend policy and available distributable profit.
- Chair rental charge: TZS 300 per chair per day.
- Chair rental approval: the member responsible for keeping the chairs confirms availability/fulfilment; the Treasurer verifies payment.

These values must be configurable and effective-dated. The application must not hard-code them into workflows.

## 2. Product Scope and Boundaries

### 2.1 In scope

1. One MEG mobile application for Android and iOS.
2. Role-specific dashboards and navigation within the same application.
3. Public/guest access to approved group information and selected services.
4. Member registration and approval.
5. Member digital profiles, dependants, guarantors, and referral genealogy.
6. Joining-fee, project-share, savings, and contribution management.
7. Financial transaction recording, verification, receipts, and statements.
8. Loan eligibility, applications, guarantor confirmation, approvals, disbursement, repayment, interest, and arrears.
9. Welfare/benefit applications and payments.
10. Dividend calculation and crediting.
11. Group asset register and chair rental lifecycle.
12. Meetings, announcements, bulk SMS, push notifications, and reminders.
13. Dashboards, reports, audit history, and controlled exports.
14. Administrative configuration and access management through the mobile application.

### 2.2 Out of scope for the initial release

- A separate web administration portal.
- Direct API integration with banks or mobile-money institutions.
- Automated movement of money between financial institutions.
- A public website.
- Automated credit scoring based on external credit bureaus.
- Automated commission or multi-level marketing payments for referrals.
- Unapproved online voting or legally binding electronic signatures unless separately adopted by MEG.
- Accounting, tax, or regulatory integrations not explicitly approved by MEG.

### 2.3 Payment initiation boundary

The application may display payment methods and instructions such as mobile-money wallet, bank transfer, or cash. It may allow a member to enter a transaction reference or upload proof of payment. It does not directly connect to the bank or mobile-money provider in this scope.

A selected payment method is not proof that money has been received. A payment remains pending until the authorized Treasurer verifies it against available evidence and records the verified transaction.

## 3. Product Principles

- **Single source of truth:** each member, payment, loan, asset, and benefit has one authoritative record.
- **Separation of funds:** every financial category has its own ledger classification.
- **Traceability:** every important action records who performed it, when, and what changed.
- **Segregation of duties:** sensitive financial actions should not be initiated, approved, and verified by one person.
- **Member privacy:** members see their own private financial information; officials see only what their role permits.
- **Configurable rules:** rates, fees, contribution schedules, benefit amounts, penalties, and approval routes are configurable and effective-dated.
- **No silent edits:** posted financial transactions are corrected through controlled reversals or adjustment entries, not deletion.
- **Mobile-first usability:** workflows must be practical on a phone, including small screens and intermittent connectivity.
- **Auditability:** historical records remain available according to MEG's retention policy.

## 4. User Roles and Access Model

The application uses role-based access with permissions assigned to each role. A user may hold more than one role only where MEG explicitly authorizes it. High-risk permissions should be separated.

### 4.1 Roles

| Role | Primary responsibilities |
|---|---|
| Super Administrator | Configure the application, roles, permissions, financial categories, workflow rules, and system settings. |
| Chairperson (Mwenyekiti) | Overall group oversight; member administration; review and approve benefits and other matters assigned by MEG policy. |
| Deputy Chairperson | Support the Chairperson and perform delegated duties. |
| Secretary (Katibu) | Membership records, meeting records, announcements, document checks, and administrative follow-up. |
| Treasurer (Mhazini) | Verify payments, maintain financial records, manage receipts, review balances, loan disbursement records, and financial reports. |
| Assets Custodian / Chair Keeper | Maintain asset inventory, confirm chair availability, issue/receive chairs, inspect returned assets, and report damage or loss. |
| Loan Committee | Review loan applications, assess eligibility and repayment capacity, and submit recommendations. |
| Member | View own profile and financial records; make payments; submit loan and benefit applications; confirm guarantees; make promises; invite prospective members; request chair rental. |
| Guest / Prospective Member | View approved public information, start membership registration, and submit a chair-rental enquiry/request subject to configured access rules. |

### 4.2 Permission principles

Permissions should be granular, not inferred solely from role names. Examples:
- View own savings is different from view all members' savings.
- Record a payment is different from verify a payment.
- Recommend a loan is different from approve a loan.
- Approve chair availability is different from verify rental payment.
- View public asset information is different from view internal asset valuation or custody details.
- View a member's NIDA details requires a specific sensitive-data permission.

### 4.3 Segregation of duties

The application should prevent or flag:
- A user verifying their own payment where independent verification is required.
- A Treasurer approving their own benefit payment.
- A user approving a loan they personally applied for.
- An asset custodian verifying payment if that duty belongs to the Treasurer.
- Deleting or editing posted financial transactions without a controlled reversal and audit record.

MEG may define emergency or small-group exceptions, but any exception must be explicit, recorded, and reportable.

## 5. Application Navigation and Mobile Experience

### 5.1 Shared application structure

The same mobile application presents different dashboards based on the signed-in user's permissions.

Suggested primary navigation:
- Home / Dashboard
- Services
- Transactions
- Notifications
- Profile / More

The exact labels may be adjusted during UI design. Role-specific shortcuts should appear on the home screen.

### 5.2 Member navigation

Member-facing shortcuts:
- My Profile
- My Savings
- My Contributions
- My Shares
- My Loans
- My Debts / Statements
- My Benefits
- My Dividends
- Make a Payment
- Loan Application
- Benefit Application
- Rent Chairs
- Invite a Member
- My Referral Tree
- Promises
- Announcements and Meetings
- Help / Contact MEG

### 5.3 Official dashboards

Officials see additional functions based on their permissions:
- Membership applications and member directory.
- Payment verification queue.
- Contribution and arrears dashboard.
- Loan review and approval queue.
- Benefits approval queue.
- Asset inventory and rental queue.
- Bulk messaging.
- Financial reports.
- Meeting administration.
- Configuration and audit history, where authorized.

### 5.4 Mobile usability requirements

- Clear status labels and next-action guidance.
- Search and filters for long lists.
- Pagination or progressive loading for large histories.
- Confirmation before high-impact actions.
- Accessible text sizes and clear currency formatting.
- Date and time display in the MEG operating locale.
- Downloadable statements and receipts.
- Secure local storage for session credentials.
- Optional biometric re-authentication for sensitive actions.
- Offline viewing only for selected previously synchronized information; no offline approval or posting of financial transactions.
- Clear synchronization status and duplicate-submission protection.

## 6. Module 1 – Membership Management

### 6.1 Member registration channels

A prospective member may be registered by:
1. The Chairperson or an authorized official.
2. Self-registration from the MEG mobile application's guest entry point.
3. A member invitation/referral link or invitation code.

All channels must create the same membership application record and follow the same eligibility, payment, and approval controls.

### 6.2 Membership application information

Capture:
- Full legal name.
- Member photograph.
- NIDA number and, where required, supporting identity evidence.
- Primary phone number and optional alternative phone number.
- Email address, if available.
- Date of birth, where required.
- Gender, where required by MEG records.
- Residential address.
- Occupation or other approved profile details.
- Dependants.
- Guarantor, where applicable.
- Referring member / inviter.
- Date application was submitted.
- Consent and declaration that information is accurate.
- Required documents and verification notes.

Sensitive identity data must be masked in ordinary list views and accessible only to authorized roles.

### 6.3 Dependants

A member may record eligible dependants:
- Parents.
- Spouse.
- Children.
- Parents-in-law.
- Other categories expressly accepted by MEG.

For each dependant, record name, relationship, contact details where relevant, and supporting evidence where required. MEG must define which dependant categories qualify for each welfare benefit.

### 6.4 Guarantor management

A guarantor must be an eligible MEG member if that remains the group's policy. The system must:
- Select the guarantor from the member register rather than accept an unverified free-text name.
- Check the guarantor's membership status.
- Send the guarantor a request to accept or decline.
- Record the decision, date, and any conditions.
- Retain a history of guarantees.
- Allow the loan committee to review the guarantor's existing guarantee commitments.
- Avoid implying that a guarantee is accepted merely because the applicant entered the member's name.

### 6.5 Membership application and approval workflow

1. Applicant completes the registration form.
2. System validates mandatory fields and duplicate identity/member records.
3. Applicant submits the application.
4. System creates a pending application and unique application reference.
5. Applicant pays the joining fee of TZS 80,000.
6. Applicant pays the initial project shares of TZS 200,000 if joining the project and if that is a condition of membership or loan eligibility.
7. Applicant enters payment reference or submits proof.
8. Treasurer verifies the payment records.
9. Secretary or authorized reviewer checks profile details and supporting documents.
10. Chairperson or designated membership authority approves or rejects the application.
11. On approval, the system assigns a permanent Member Number and activates the membership.
12. Applicant receives the decision and a digital membership confirmation.

The system must support policy configuration if MEG later decides that the project-share payment is not a prerequisite for basic membership but is a prerequisite for project participation or borrowing.

### 6.6 Membership statuses

- Draft
- Submitted
- Awaiting Payment
- Payment Under Verification
- Awaiting Documents
- Under Review
- Awaiting Approval
- Approved / Active
- Rejected
- Suspended
- Resigned / Exited
- Deceased, where applicable

A rejected or exited member's historical transactions must remain available under retention and privacy rules.

### 6.7 Member digital file

Each member profile must consolidate:
- Identity and contact details.
- Photograph and identity documents.
- Dependants.
- Guarantor history.
- Referral source and referral descendants.
- Joining fee and project shares.
- Savings balances and transaction history.
- Contributions and arrears.
- Promises and reminder history.
- Loans, interest, repayments, and outstanding balances.
- Benefits applied for and received.
- Dividends credited.
- Chair rentals, if applicable.
- Receipts, statements, notices, and membership status history.

## 7. Module 2 – Member Referral & Membership Genealogy Tree

### 7.1 Purpose

The referral tree is a permanent historical record of who introduced whom to MEG. It visualizes the group's growth as a hierarchy of member-to-member referrals. It is a membership-history and accountability feature, not a commission or multi-level marketing scheme.

### 7.2 Referral process

1. An active member selects “Invite a Member”.
2. The application generates a unique invitation code or shareable invitation link.
3. The prospective member opens the invitation and begins registration.
4. The referral source is pre-associated with the invitation.
5. The applicant confirms who invited them.
6. The application records the referring member, invited person, invitation date, registration date, and relationship if MEG requires it.
7. The applicant completes required joining payments.
8. The Treasurer verifies payments.
9. The membership authority approves the application.
10. Only after approval does the person appear as an active member in the approved membership tree. Pending applicants may appear in a separate pending-invitations view.

### 7.3 Tree capabilities

Authorized users can:
- View the full MEG referral tree.
- Expand and collapse branches.
- Search by member name or Member Number.
- View direct referrals and total descendants.
- Filter by active, pending, suspended, or exited status.
- Filter by joining date or referral generation.
- Open a member profile from a tree node.
- View the referral path from the founding/original member to a selected member.
- Export an authorized referral summary.
- View growth statistics by period.

Members should normally see their own referral branch and relevant personal referral history. Full-tree access is restricted to designated officials.

### 7.4 Referral data and rules

Each approved member may have one original referring member, unless MEG explicitly records an exception such as “self-originated / founding member”. The referral parent must be an eligible existing member at the time of invitation. A member cannot refer themselves. A referral relationship cannot be silently changed after approval. Corrections require authorized approval, a reason, and an audit record.

Referral history must not be deleted when a member resigns, is suspended, or dies. Status changes affect how the member is displayed, not the historical relationship.

### 7.5 Referral metrics

- Total registered members.
- Active members.
- Pending applicants.
- Direct referrals per member.
- Total descendants per member.
- New members by month or year.
- Conversion from invitation to approved membership.
- Members with no recorded referral source.

No referral commission or financial reward is calculated unless MEG formally adopts a separate policy.

## 8. Module 3 – Joining Fees, Project Shares, Savings and Contributions

### 8.1 Separate financial categories

The application must maintain separate balances and transaction classifications for:
- Joining fee: current amount TZS 80,000, normally one-time.
- Project shares: current fixed initial amount TZS 200,000.
- Member savings.
- Monthly JAMII contributions.
- Udhuru contributions.
- Celebration contributions.
- Other approved contributions.
- Loan principal and repayments.
- Loan interest.
- Welfare collections and payments.
- Asset rental income.
- Dividends.
- Other approved income and expenses.

The joining fee, shares, savings, and contributions must never be treated as interchangeable. MEG must document whether project shares are refundable, transferable, withdrawable, or locked.

### 8.2 Project shares

The member's project participation status must be clearly shown:
- Not joined.
- Payment pending.
- Payment under verification.
- Joined / eligible.
- Suspended or otherwise restricted, if policy permits.

The system records share amount, date, receipt, payment reference, verification, and any approved adjustment. The current TZS 200,000 threshold is configurable.

### 8.3 Savings

Each member has a savings ledger showing:
- Opening balance.
- Deposits.
- Approved withdrawals, if permitted.
- Adjustments and corrections.
- Dividend credits.
- Closing balance.
- Available/eligible savings for loan calculations.

The application must distinguish the actual savings balance from the eligible savings balance used for loan eligibility. Any restriction, pledge, or outstanding obligation affecting eligibility must be visible and explainable.

### 8.4 Contribution setup

Authorized officials configure each contribution:
- Name and description.
- Amount or calculation basis.
- Frequency: monthly, one-time, event-based, or other.
- Due date and payment window.
- Members or member categories covered.
- Mandatory or voluntary status.
- Applicable exemption/udhuru rules.
- Penalty or late fee, if approved.
- Approval authority.
- Effective start and end dates.

### 8.5 Contribution collection and arrears

For each contribution cycle, the system generates expected member obligations. It compares expected amounts with verified payments and calculates:
- Amount due.
- Amount paid.
- Remaining balance.
- Due date.
- Days overdue.
- Approved exemption.
- Promise to pay.
- Arrears status.

A contribution should not become paid solely because a member uploaded a payment screenshot. It becomes paid after Treasurer verification.

### 8.6 Member-facing contribution view

A member can view:
- All contribution categories.
- Monthly history.
- Amount due and paid.
- Outstanding arrears.
- Exemptions and their reasons.
- Promises and due dates.
- Receipts and downloadable statements.

### 8.7 Official contribution dashboard

The Chairperson and Treasurer can view total expected collections, verified collections, outstanding amounts, overdue members, collection trends, and category breakdowns. Access to individual member balances is permission-controlled.

## 9. Module 4 – Financial Transactions and Cash Management

### 9.1 Transaction lifecycle

Every financial transaction must have:
- Unique transaction reference.
- Member or counterparty, where applicable.
- Financial category.
- Amount and currency.
- Transaction date.
- Payment method.
- External reference or evidence.
- Initiator.
- Verifier/approver.
- Verification date.
- Status.
- Linked receipt.
- Audit history.

### 9.2 Payment methods

The member may select:
- Mobile-money wallet (provider selection may be shown).
- Bank transfer.
- Cash.
- Other approved method.

The application displays MEG's configured payment instructions. No direct bank or wallet integration is included in this scope.

### 9.3 Payment verification workflow

1. Member selects the amount and payment category.
2. Application displays payment instructions and available methods.
3. Member pays outside the application.
4. Member submits transaction reference and/or proof.
5. Transaction enters “Pending Verification”.
6. Treasurer checks the reference, amount, date, and available evidence.
7. Treasurer verifies or rejects the submission with a reason.
8. A verified transaction is posted to the appropriate ledger.
9. A receipt is generated.
10. Member receives an in-app notification and, where configured, SMS.

The system must prevent duplicate posting of the same transaction reference where possible and flag suspected duplicates for review.

### 9.4 Receipts

Receipts should include:
- MEG name and approved logo.
- Receipt number.
- Member number and name.
- Payment category.
- Amount.
- Date and time.
- Payment method.
- External transaction reference, if provided.
- Verification status.
- Verifying official.
- Receipt verification reference or QR code.

Receipts can be viewed and downloaded from the member's transaction history.

### 9.5 Expenditure and disbursement

Expenses and benefit/loan disbursements must record:
- Payee.
- Purpose and category.
- Amount.
- Supporting document.
- Requesting official.
- Approval authority.
- Payment confirmation.
- Payment date and method.
- Ledger classification.

The system should distinguish an approved payment request from a payment that has actually been paid.

### 9.6 Corrections and reversals

Posted financial transactions cannot be deleted. An authorized correction creates a reversal or adjustment linked to the original transaction, with a reason, approval, and full audit history.

### 9.7 Financial position

The application should show cash/bank balances only to the extent that MEG maintains and reconciles those balances in the system. Since external institutions are not integrated, the system must not claim that a bank or wallet balance is live unless an authorized official has reconciled and updated it.

## 10. Module 5 – Loan Management

### 10.1 Loan eligibility policy

Current stated rule:
- A member must have paid the fixed project shares of TZS 200,000 to qualify for borrowing.
- Maximum loan ceiling is three times the member's eligible savings.
- Example: eligible savings of TZS 1,000,000 gives a maximum ceiling of TZS 3,000,000.

Indicative calculation:
**Maximum loan ceiling = Eligible savings × 3**

The actual approved amount may be lower after considering existing loan balances, repayment capacity, guarantor requirements, overdue obligations, available loan funds, and other MEG rules.

The application must display the calculation and reasons for any restriction. It must not promise that the full calculated ceiling will be approved.

### 10.2 Loan application

The member submits:
- Requested amount.
- Purpose.
- Proposed repayment period.
- Repayment frequency.
- Guarantor selection.
- Supporting documents, if required.
- Declaration and acceptance of loan terms.

The application displays eligible savings, project-share status, indicative maximum loan ceiling, existing outstanding debt, and any eligibility warning.

### 10.3 Loan review and approval

Recommended configurable workflow:
1. Member submits application.
2. System performs automatic eligibility checks.
3. Guarantor receives and responds to guarantee request.
4. Loan Committee reviews the application and supporting information.
5. Committee records recommendation and any revised amount/terms.
6. Chairperson or designated authority approves or rejects.
7. Treasurer confirms funds are available and records disbursement.
8. Member receives the approved loan terms and repayment schedule.
9. Loan becomes active after disbursement is recorded.

MEG must formally confirm the approval authority and whether every loan requires both committee recommendation and Chairperson approval.

### 10.4 Interest and repayment configuration

The system must support configurable:
- Interest rate.
- Interest method: flat or reducing balance.
- Calculation period.
- Loan term.
- Repayment frequency.
- Installment schedule.
- Grace period, if any.
- Late-payment penalty, if approved.
- Early repayment rules.
- Rescheduling and restructuring rules.

The interest rate and method have not been supplied and must be confirmed by MEG before implementation. No default rate should be assumed.

### 10.5 Loan repayment schedule

For each disbursed loan, generate a schedule with:
- Installment number.
- Due date.
- Principal due.
- Interest due.
- Total installment.
- Amount paid.
- Remaining installment balance.
- Status.

### 10.6 Repayment posting

1. Member selects the loan and submits a repayment.
2. Member selects a payment method and follows the displayed instructions.
3. Member submits transaction evidence.
4. Treasurer verifies the payment.
5. Verified amount is allocated according to MEG's approved allocation policy.
6. Loan balance and schedule update.
7. Member receives receipt and updated statement.

### 10.7 Loan statuses

- Draft
- Submitted
- Eligibility Check
- Awaiting Guarantor
- Under Committee Review
- Recommended
- Awaiting Approval
- Approved
- Rejected
- Awaiting Disbursement
- Active
- Partially Repaid
- Overdue
- Restructured
- Fully Repaid
- Closed
- Written Off, only under formal approval and policy

### 10.8 Debt and loan statements

Members can download:
- Individual loan statement.
- Repayment schedule.
- Consolidated outstanding debt statement.
- Payment receipts.
- Loan agreement and approval history, where available.

Statements must show principal, interest, amount paid, outstanding principal, outstanding interest, arrears, next due date, and total outstanding amount.

### 10.9 Loan portfolio dashboard

Authorized officials can see:
- Total principal disbursed.
- Principal outstanding.
- Interest accrued and interest collected, separately.
- Total repayments.
- Active loans.
- Overdue loans.
- Fully repaid loans.
- Loans by status.
- Arrears ageing.
- Portfolio-at-risk indicators, based on a MEG-approved definition.
- Available loan fund, based on reconciled records.

## 11. Module 6 – Welfare and Member Benefits

### 11.1 Benefit categories

Configurable categories may include:
- Death/bereavement (msiba).
- Illness.
- Celebration.
- Other approved social or welfare assistance.

Each benefit category has rules for eligible member/dependant, required documents, amount or calculation basis, frequency limits, contribution conditions, and approval route.

### 11.2 Benefit application

The member submits:
- Benefit type.
- Applicant and affected member.
- Beneficiary name.
- Relationship to member.
- Event date.
- Description.
- Requested amount, where applicable.
- Supporting documents.
- Contact information for follow-up.

### 11.3 Benefit approval and payment flow

1. Member submits an application.
2. System checks membership and basic eligibility.
3. Secretary or designated reviewer checks documents.
4. Chairperson reviews and approves or rejects the benefit.
5. If approved, a payment instruction is sent to the Treasurer.
6. Treasurer verifies the payee and payment details.
7. Treasurer records the actual payment.
8. The benefit is marked paid only after payment is recorded.
9. Member receives a notification and transaction reference.

The Chairperson approves the entitlement; the Treasurer verifies and records the payment. The application must preserve this separation.

### 11.4 Benefit history and transparency

Authorized officials can view beneficiaries by benefit category, period, and status. Members can view their own benefit history. Any group-wide publication must follow MEG privacy rules and must not disclose sensitive medical details or private family information.

### 11.5 Benefit statuses

- Draft
- Submitted
- Under Verification
- Awaiting Chairperson Approval
- Approved
- Rejected
- Awaiting Payment
- Paid
- Cancelled
- Closed

## 12. Module 7 – Dividend Management

### 12.1 Proposed dividend rule

MEG has proposed a 2% dividend based on each member's savings, credited to that member's savings balance, using profit generated from loans and projects.

This proposal requires a precise policy before implementation. The phrase “2% based on savings” must be clarified as to whether it means:
- 2% of the member's eligible savings balance at a defined cut-off date; or
- 2% annual return on a time-weighted or average savings balance; or
- another formula approved by MEG.

The system must not calculate dividends from gross revenue. Only distributable profit after approved expenses, provisions, losses, and any required reserves may be allocated, if that is MEG's adopted policy.

### 12.2 Dividend process

1. Treasurer closes the relevant financial period.
2. Financial reports are prepared and reconciled.
3. Authorized officials confirm the distributable profit.
4. MEG approves the dividend pool and allocation policy.
5. System calculates each eligible member's allocation using the approved formula and cut-off date.
6. Authorized approver reviews the calculation report.
7. Dividend credits are posted to member savings ledgers.
8. Members receive dividend notifications.
9. The system retains the period, formula version, calculation inputs, approval, and posted entries.

### 12.3 Dividend controls

- No dividend is posted without an approved profit pool and authorization.
- The same period must not be credited twice.
- Adjustments require an auditable reversal/correction.
- Members can view their own dividend history.
- Officials can view the total dividend pool and member-by-member allocation under appropriate permissions.

## 13. Module 8 – Promises, Arrears and Debt Reminders

### 13.1 Promise management

A member can record a promise to pay an outstanding contribution, loan installment, or other approved debt.

Capture:
- Member.
- Debt/contribution reference.
- Promised amount.
- Promised payment date.
- Reason or note.
- Date recorded.
- Status.

### 13.2 Promise statuses

- Submitted
- Accepted, if official acknowledgement is required
- Due Soon
- Fulfilled
- Partially Fulfilled
- Overdue
- Cancelled

A promise does not reduce the actual debt. Only a verified payment changes the financial balance.

### 13.3 Reminders

The application can send:
- Upcoming due-date reminders.
- Overdue notices.
- Promise due reminders.
- Missed-promise reminders.
- Loan installment reminders.
- Monthly contribution reminders.

Reminder frequency and message templates must be configurable to avoid excessive messaging.

## 14. Module 9 – Asset Management

### 14.1 Asset register

MEG assets must be recorded in a central inventory. Each asset record may include:
- Asset code.
- Asset name and category.
- Description.
- Photograph.
- Quantity.
- Condition.
- Acquisition date.
- Acquisition cost, if recorded.
- Current location.
- Custodian/member responsible.
- Availability status.
- Maintenance history.
- Loss/damage history.
- Public visibility setting.

### 14.2 Public asset information

Guest users and members may view selected approved asset information inside the mobile application, such as:
- Asset name/category.
- Photograph.
- General description.
- Rental availability.
- Rental charge.
- Booking instructions.

Internal details such as exact storage location, custodian's private contact details, asset valuation, and security-sensitive information must not be public by default.

### 14.3 Asset lifecycle

- Registered
- Available
- Reserved
- Issued / Rented
- Partially Returned
- Returned
- Under Inspection
- Under Maintenance
- Damaged
- Lost
- Retired

### 14.4 Asset custody

The application must record which member or official is responsible for holding or managing each asset. Custody transfer requires acknowledgement by the releasing and receiving parties and an audit record.

## 15. Module 10 – Chair Rental Management

### 15.1 Rental policy supplied by MEG

- Current rental charge: TZS 300 per chair per day.
- Chair availability/fulfilment is approved or confirmed by the member responsible for keeping the chairs.
- The Treasurer verifies payment.
- Rental may be requested online through the mobile application.
- Late return charge is calculated by the number of overdue days multiplied by the applicable daily charge, subject to the approved policy.

The daily amount and late-return treatment must be separately configurable. MEG must confirm whether TZS 300 per day applies per chair to the rental period, late period, or both.

### 15.2 Rental request

Applicant provides:
- Applicant name and contact.
- Member number, if a member.
- Event or intended use.
- Number of chairs requested.
- Collection date/time.
- Expected return date/time.
- Delivery/collection arrangement.
- Notes and any supporting details.

The application checks available inventory for the requested dates.

### 15.3 Rental approval workflow

1. Applicant submits a chair-rental request.
2. System checks the requested quantity and date range against available inventory.
3. Chair Keeper receives the request.
4. Chair Keeper confirms availability and approves, declines, or proposes an alternative.
5. Applicant receives the decision and payment instructions.
6. Applicant pays outside the application using the displayed method.
7. Applicant submits transaction reference or proof.
8. Treasurer verifies payment.
9. Booking becomes confirmed only when both availability approval and payment verification requirements are satisfied.
10. At collection, Chair Keeper records the quantity issued, condition, date/time, and recipient acknowledgement.
11. At return, Chair Keeper records quantity returned, return date/time, and condition.
12. System calculates any late charge or damage/loss assessment according to approved rules.
13. Treasurer verifies any additional payment.
14. Rental is closed after all assets are reconciled.

### 15.4 Approval responsibilities

- **Availability and operational approval:** the member responsible for keeping the chairs (Chair Keeper / Assets Custodian).
- **Payment verification:** Treasurer.
- **Policy exception, waiver, or disputed loss/damage charge:** Chairperson or another authority appointed by MEG.
- **Final closure:** Chair Keeper confirms returned quantity and condition; Treasurer confirms any outstanding payment has been settled.

This keeps asset custody and financial verification separate.

### 15.5 Rental fee calculation

Base rental calculation:
**Rental charge = Number of chairs × TZS 300 × Billable days**

The system must define whether the collection day and return day are both billable, and whether a partial day counts as a full day. This is an MEG policy decision.

Late-return calculation, based on the supplied rule:
**Late charge = Number of overdue chairs × Overdue days × Applicable daily late rate**

If the late rate is also TZS 300 per chair per day, that must be explicitly confirmed. The application must not assume this without approval.

### 15.6 Lost or damaged chairs

The system must record:
- Asset/chair quantity affected.
- Whether missing, broken, or otherwise damaged.
- Condition before issue and after return.
- Photographic evidence.
- Custodian's inspection report.
- Member/customer explanation.
- Assessment amount or replacement cost.
- Decision and approving authority.
- Payment status.
- Asset repair/replacement/retirement outcome.

MEG has not supplied a fixed penalty for a lost or broken chair. The application should therefore support configurable charges or case-by-case assessment. A charge must not be invented or automatically imposed without an approved policy and documented decision.

### 15.7 Rental dashboard

Officials can see:
- Total chairs.
- Available chairs.
- Reserved chairs.
- Chairs currently rented out.
- Overdue returns.
- Damaged or missing chairs.
- Rental income expected.
- Rental income verified.
- Upcoming bookings.
- Rental history by customer/member.

## 16. Module 11 – Meetings and Announcements

### 16.1 Meeting management

Authorized officials can create meeting records containing:
- Meeting title.
- Purpose/agenda.
- Date and time.
- Venue or meeting instructions.
- Target audience.
- Attendance requirement.
- Attachments.
- Created by.
- Meeting status.

Members receive notifications and reminders. The application may record attendance if MEG chooses to use that feature.

### 16.2 Announcements

Announcement categories may include:
- General group notices.
- Meetings.
- Events and celebrations.
- Bereavement announcements.
- Contribution reminders.
- Loan notices.
- Asset/rental notices.
- Emergency notices.

An announcement contains title, message, category, target audience, attachments, publish time, expiry time, and author.

### 16.3 Bulk SMS and push messaging

Authorized users can:
- Select all active members or a defined group.
- Select members with overdue contributions, subject to permissions.
- Target members by status or approved category.
- Preview message content.
- Confirm recipient count and estimated SMS segments/cost where supported by the SMS provider.
- Submit for approval if MEG requires it.
- Send and review delivery reports.

The system should keep a message history with sender, recipient group, message, date/time, delivery status, and any failure response returned by the messaging service.

SMS should avoid exposing sensitive debt or medical information on shared phones. Detailed information should be available after secure login.

## 17. Module 12 – Notifications and Communication Centre

Channels:
- In-app notifications.
- Push notifications.
- SMS for critical or configured notices.

Events that may trigger notifications:
- Registration submitted.
- Payment awaiting verification.
- Payment verified or rejected.
- Membership approved or rejected.
- Referral invitation accepted.
- Guarantor confirmation requested.
- Loan submitted, reviewed, approved, rejected, or disbursed.
- Loan installment approaching or overdue.
- Benefit submitted, approved, rejected, or paid.
- Contribution due or overdue.
- Promise approaching or missed.
- Chair booking approved or declined.
- Payment verification completed.
- Chair collection or return due.
- Asset damage/loss recorded.
- Meeting or announcement published.
- Dividend credited.

Members should be able to view notification history. Delivery failures should be visible to authorized officials where operationally useful.

## 18. Module 13 – Dashboards and Reports

### 18.1 Chairperson dashboard

- Total members.
- Active, pending, suspended, and exited members.
- New members by period.
- Membership referral tree and growth.
- Total savings.
- Total contributions expected and collected.
- Outstanding member obligations.
- Loan portfolio summary.
- Welfare applications awaiting approval.
- Benefit payments.
- Asset and chair rental summary.
- Upcoming meetings and key announcements.

### 18.2 Treasurer dashboard

- Verified collections today/month/year.
- Pending payment verification.
- Savings balances.
- Project-share collections.
- Contribution arrears.
- Loan disbursements.
- Loan principal outstanding.
- Interest collected.
- Loan repayments due and overdue.
- Benefit payments awaiting processing.
- Chair rental receipts.
- Income and expenditure.
- Reconciliation exceptions.

### 18.3 Secretary dashboard

- Membership applications.
- Missing member documents.
- Pending membership approvals.
- Referral invitations and pending applicants.
- Meetings and attendance records.
- Announcements.
- Follow-up tasks.

### 18.4 Assets dashboard

- Total assets by category.
- Asset availability.
- Chair stock.
- Active rentals.
- Upcoming collections and returns.
- Overdue rentals.
- Damaged/lost assets.
- Maintenance and custody records.

### 18.5 Member dashboard

- Savings balance.
- Eligible savings for loan purposes.
- Project-share status.
- Contributions paid and outstanding.
- Current loans and outstanding debts.
- Next repayment.
- Benefits history.
- Dividend history.
- Promises.
- Referral summary.
- Chair rental history.
- Recent transactions and receipts.

### 18.6 Standard reports

- Member register.
- Membership status report.
- Referral genealogy and growth report.
- Joining-fee report.
- Project-share report.
- Savings statement and summary.
- Contributions by category and period.
- Arrears and overdue members.
- Promise fulfilment report.
- Loan applications and approval report.
- Loan portfolio and repayment report.
- Interest report.
- Welfare application and payment report.
- Dividend calculation and allocation report.
- Income and expenditure report.
- Transaction verification report.
- Asset register and condition report.
- Chair rental and overdue report.
- Damage/loss report.
- SMS and notification delivery report.
- User activity and audit report.

Reports should support filters by date range, member, category, status, and authorized unit/group. Exports should be permission-controlled and logged.

## 19. Module 14 – Administration and Configuration

Authorized administrators can manage:
- Member categories and statuses.
- Roles and permissions.
- Contribution types and schedules.
- Joining fee and share requirements.
- Loan eligibility rules and multipliers.
- Interest calculation method and rates.
- Repayment frequencies and penalty rules.
- Benefit categories and eligibility.
- Dividend policy and periods.
- Asset categories.
- Chair rental rates and billing rules.
- Late-return and damage/loss policies.
- Payment methods and instructions.
- Notification templates and schedules.
- Approval workflows.
- Document requirements.
- Numbering and reference formats.
- Application settings and operational periods.

Every configuration change must record who changed it, when it changed, the previous value, the new value, the reason, and the effective date. Changes should not silently rewrite historical transactions.

## 20. End-to-End Process Flows

### 20.1 New member joining

Prospective member → Invitation/referral or self-registration → Application submission → Identity/profile checks → Joining-fee payment → Project-share payment (where required) → Treasurer payment verification → Membership review → Authorized approval → Member Number assigned → Active member profile and referral tree updated → Welcome notification.

### 20.2 Monthly contribution

Contribution cycle configured → Member obligations generated → Member notified → Member pays externally → Payment evidence submitted → Treasurer verifies → Correct contribution ledger updated → Receipt issued → Dashboard and arrears updated.

### 20.3 Loan application and repayment

Member checks eligibility → Application submitted → System checks project shares and eligible savings → Guarantor confirms → Loan Committee reviews → Authorized approval → Treasurer confirms available funds and records disbursement → Repayment schedule created → Member repays → Treasurer verifies → Loan ledger updated → Loan closed when fully settled.

### 20.4 Welfare benefit

Member submits request → Eligibility and documents checked → Chairperson approves/rejects → Treasurer receives approved payment instruction → Payment is made and recorded → Member notified → Benefit history and financial reports updated.

### 20.5 Dividend

Financial period closed → Accounts reconciled → Distributable profit determined → Dividend policy and member eligibility confirmed → Calculation generated → Authorized review and approval → Credits posted to savings ledgers → Members notified → Dividend report archived.

### 20.6 Chair rental

Request submitted → Availability checked → Chair Keeper approves availability → Payment instructions shown → Applicant pays externally → Treasurer verifies payment → Booking confirmed → Chairs issued and condition recorded → Chairs returned and inspected → Late/damage/loss assessment if applicable → Any additional payment verified → Rental closed and inventory updated.

### 20.7 Referral tree

Member invites prospective member → Invitation code/link created → Applicant registers through invitation → Referral source confirmed → Application and payments completed → Membership approved → Approved member linked under referring member → Tree and referral statistics updated.

## 21. Core Information Architecture

The following are the principal business records. They describe the information the application must manage; they are not a physical database implementation specification.

| Business record | Purpose |
|---|---|
| Member | Main identity and membership record |
| Membership Application | Registration submission and approval lifecycle |
| Member Document | Identity and supporting documents |
| Dependant | Member's declared eligible dependants |
| Guarantor Commitment | Guarantee requests and decisions |
| Referral Invitation | Invitation code/link and its status |
| Member Referral Relationship | Permanent “who introduced whom” relationship |
| Contribution Type | Configured contribution category and rules |
| Member Obligation | Amount a member is expected to pay |
| Financial Transaction | Payment, receipt, collection, or disbursement record |
| Ledger Entry | Classified financial posting |
| Savings Account | Member savings balance and history |
| Project Share Account | Member's project-share record |
| Loan Application | Loan request and review |
| Loan Account | Approved and disbursed loan |
| Repayment Schedule | Installments and due dates |
| Loan Repayment | Verified repayment transaction |
| Benefit Application | Welfare request and approval |
| Benefit Payment | Actual payment of approved benefit |
| Dividend Period | Financial period and dividend rules |
| Dividend Allocation | Member-level dividend calculation and credit |
| Asset | MEG asset register record |
| Asset Custody | Person responsible for an asset |
| Rental Request | Chair rental application |
| Rental Booking | Approved reservation and rental terms |
| Asset Issue/Return | Quantity and condition at handover/return |
| Damage/Loss Case | Inspection, assessment, decision, and settlement |
| Meeting | Meeting details and attendance |
| Announcement | Group communication record |
| Message Delivery | SMS/push dispatch and delivery result |
| Promise to Pay | Member's stated payment commitment |
| Notification | In-app and push notification record |
| Approval Record | Decision, approver, date, and reason |
| Audit Event | Historical record of sensitive actions |
| Configuration Version | Effective-dated business rule and settings |

## 22. Financial Control and Ledger Requirements

The application must maintain an auditable record of financial movements. A displayed balance should be traceable to its underlying posted transactions.

Minimum controls:
1. Separate ledger categories for joining fees, shares, savings, contributions, loan principal, interest, benefits, dividends, rental income, and expenses.
2. Every posted entry has a unique reference and source transaction.
3. Pending payment submissions do not change member balances.
4. Rejected payment evidence does not create a ledger posting.
5. Posted entries are not deleted.
6. Corrections use reversals/adjustments linked to original entries.
7. Approval and verification actions are attributable to individual users.
8. Financial reports distinguish cash received from amounts merely expected or promised.
9. Loan principal and interest are reported separately.
10. Dividend credits are distinguishable from ordinary savings deposits.
11. Reconciliation exceptions are visible to the Treasurer.
12. Historical calculations retain the rule version used at the time.

MEG should confirm whether the application must provide a full double-entry accounting ledger or a controlled member-finance sub-ledger for the first release. This decision affects the depth of financial reporting and reconciliation.

## 23. Security, Privacy and Governance

### 23.1 Authentication and account protection

- Unique user accounts.
- Strong password or approved authentication policy.
- Optional biometric re-authentication.
- Secure session management.
- Account lockout or rate limiting after repeated failed attempts.
- Recovery process with identity checks.
- Device/session management and ability to revoke sessions.

### 23.2 Authorization

- Role- and permission-based access.
- Member self-service restricted to the member's own records.
- Sensitive identity documents restricted to authorized officials.
- Financial reports restricted by role.
- Full referral tree restricted to designated officials.
- Public asset information separated from internal asset records.

### 23.3 Privacy

- Collect only information required by MEG's approved purpose.
- Obtain clear consent for collection and processing of member data.
- Explain why NIDA, photographs, dependant information, and supporting documents are collected.
- Mask sensitive values in ordinary screens and notifications.
- Do not send detailed medical or financial information in plain SMS.
- Define retention and lawful deletion rules for personal documents while preserving required financial/audit records.
- Record access to sensitive member records.

### 23.4 Audit trail

Audit events should cover:
- Login and security events.
- Member creation and profile changes.
- Referral relationship changes.
- Payment submissions, verification, rejection, and reversal.
- Loan application decisions and disbursements.
- Benefit decisions and payments.
- Dividend calculations and postings.
- Asset custody, issue, return, damage, and loss.
- Configuration and permission changes.
- Bulk messaging and report exports.

Each audit event should identify actor, action, affected record, timestamp, outcome, and reason where applicable.

## 24. Non-Functional Requirements

- **Availability:** the application should be reliable during normal group operations and provide clear handling of temporary service interruption.
- **Performance:** common member screens should load promptly under the expected member count and network conditions.
- **Scalability:** although MEG currently has 22 members, the information model should support substantial future growth without redesign.
- **Usability:** simple workflows suitable for members with different levels of digital literacy.
- **Accessibility:** readable text, sufficient contrast, clear labels, and understandable error messages.
- **Data integrity:** prevent duplicate submissions and inconsistent financial balances.
- **Recoverability:** regular backups and tested restoration procedures.
- **Maintainability:** configurable business rules and documented operational procedures.
- **Intermittent connectivity:** preserve safe draft input where possible; synchronize carefully; never assume an offline payment or approval has been completed.
- **Localization:** support clear Tanzanian Shilling (TZS) formatting and the language(s) selected by MEG.
- **Auditability:** retain financial and approval history according to MEG policy and applicable requirements.

## 25. Suggested Delivery Phases

### Phase 1 – Membership foundation
- Authentication and role permissions.
- Member registration and approval.
- Digital member files.
- Dependants and guarantors.
- Referral invitations and genealogy tree.
- Joining fees and project shares.

### Phase 2 – Member finance
- Savings.
- Contribution setup and collection.
- Payment evidence and Treasurer verification.
- Receipts and member statements.
- Arrears and promises.
- Financial dashboards.

### Phase 3 – Loans and welfare
- Loan eligibility.
- Loan applications and guarantor workflow.
- Committee and Chairperson approvals.
- Disbursement and repayment schedules.
- Interest and loan statements.
- Welfare applications and payments.

### Phase 4 – Assets and services
- Asset register.
- Publicly viewable asset information within the app.
- Chair availability and rental requests.
- Issue, return, late charges, damage/loss workflow.
- Rental income reports.

### Phase 5 – Governance and advanced reporting
- Dividend period and allocation.
- Meetings and announcements.
- Bulk SMS and push notifications.
- Advanced dashboards and exports.
- Audit reports and configuration governance.

The phases can be adjusted after MEG validates priorities, operational readiness, and financial policies.

## 26. Acceptance Criteria

The initial product should not be accepted until the following can be demonstrated:

### Membership
- An authorized official can register a member.
- A prospective member can submit a self-registration application.
- Required joining payments can be recorded and verified.
- Membership cannot become active before required approvals.
- Each active member has a unique Member Number and digital file.
- Dependants and guarantors can be recorded with appropriate access controls.

### Referral tree
- A member can invite a prospective member.
- The applicant's referral source is captured and confirmed.
- Approved members appear under the correct referring member.
- The tree supports expansion, search, and member profile navigation.
- Referral history remains after membership status changes.
- Referral corrections are audited.

### Contributions and savings
- Officials can configure contribution categories and cycles.
- Expected, paid, and outstanding amounts are distinguishable.
- Members can view their own records.
- Unverified payment submissions do not update balances.
- Verified payments create receipts and ledger entries.

### Loans
- The system applies the configured project-share requirement.
- The three-times-savings ceiling is calculated transparently.
- The system distinguishes eligible savings from other balances.
- Guarantor and approval workflows are recorded.
- Interest and repayment schedules follow the approved policy.
- Member statements show accurate outstanding balances.

### Benefits
- Members can submit benefit applications.
- Chairperson approval is recorded.
- Treasurer payment verification is separate.
- Paid benefits appear in member history and financial reports.

### Dividends
- Dividend calculation uses an approved, versioned formula.
- Dividend credits require an approved distributable profit pool.
- Duplicate period credits are prevented.
- Each member can see their own dividend history.

### Chair rentals and assets
- Assets and chair quantities can be registered.
- Chair Keeper can confirm availability.
- Treasurer separately verifies payment.
- Issue and return quantities and conditions are recorded.
- Overdue calculations use the approved billing rule.
- Damage/loss cases are documented and approved.
- Public users cannot see restricted internal asset details.

### Communication and governance
- Authorized officials can publish announcements and send approved bulk messages.
- Members receive relevant reminders.
- Reports respect role permissions.
- Sensitive actions create audit events.
- The application does not expose one member's private financial data to another member.

## 27. Policy Decisions MEG Must Confirm Before Implementation

The following items were not fully defined in the supplied requirements. They should be resolved by MEG's leadership and documented as approved policies.

| No. | Decision required | Current understanding / question |
|---:|---|---|
| 1 | Membership fee | Is TZS 80,000 always non-refundable and payable once? |
| 2 | Project shares | Is TZS 200,000 compulsory for basic membership, project participation, or only loan eligibility? Are shares refundable or transferable? |
| 3 | Savings | Can members withdraw savings? If yes, who approves and what restrictions apply? |
| 4 | Contributions | What are the exact JAMII, udhuru, celebration, and other contribution amounts and due dates? |
| 5 | Exemptions | Who qualifies for udhuru, who approves it, and does it waive or defer the contribution? |
| 6 | Loan eligibility | Is the three-times multiplier applied to total savings or eligible/unencumbered savings? |
| 7 | Loan restrictions | Are there minimum membership periods, maximum loan terms, guarantor counts, or limits on concurrent loans? |
| 8 | Loan approval | Which roles approve, recommend, and verify each loan? |
| 9 | Interest | What rate, method (flat/reducing balance), period, and rounding rules apply? |
| 10 | Repayments | What frequencies, due dates, grace periods, and allocation order apply? |
| 11 | Penalties | Are there late-payment penalties? How are they calculated and approved? |
| 12 | Benefits | What amounts, dependant categories, qualifying events, evidence, and limits apply? |
| 13 | Dividend | Does 2% mean annual interest on average savings, 2% of closing savings, or another formula? |
| 14 | Dividend eligibility | Which members qualify, what is the cut-off date, and how are partial-year members treated? |
| 15 | Distributable profit | Which expenses, reserves, and loan-loss provisions are deducted before dividends? |
| 16 | Chair rental days | Are collection and return dates both billable? Does a partial day count as a full day? |
| 17 | Late chair return | Is the late rate TZS 300 per chair per day or is there a separate rate? |
| 18 | Chair damage/loss | Is there a fixed penalty, replacement cost, or case-by-case assessment? Who approves disputes and waivers? |
| 19 | Chair custody | Is there one custodian or several members responsible for different chair stocks? |
| 20 | Payment verification | What evidence is acceptable for cash, wallet, and bank-transfer payments? |
| 21 | Bulk SMS | Who may send bulk SMS, who approves sensitive announcements, and what is the messaging budget? |
| 22 | Public assets | Which asset fields and photographs may be shown to non-members? |
| 23 | Referral rules | Can founding members have no referrer? Can referral relationships be corrected, and who approves? |
| 24 | Data privacy | Who may view NIDA, dependant, medical, and guarantor information? What is the retention policy? |
| 25 | Accounting scope | Does MEG require full double-entry accounting or a member-finance sub-ledger initially? |

## 28. Final Product Definition

MEG is a single mobile application for the end-to-end management of Mongolandege Economic Group. It combines membership administration, referral genealogy, savings and contributions, loans, welfare, dividends, financial controls, asset custody, chair rentals, communications, and reporting in one controlled environment.

The application must preserve a clear distinction between:
- A person who has registered and an approved member.
- A payment submission and a verified receipt.
- Joining fees, project shares, savings, and contributions.
- Loan principal and interest.
- A benefit approval and an actual payment.
- A chair availability approval and a payment verification.
- A referral invitation and an approved member relationship.
- Revenue and distributable profit.

The most important implementation principle is that every financial balance and membership status must be explainable from its underlying history. MEG should approve the outstanding policy decisions in Section 27 before the corresponding business rules are finalized.
