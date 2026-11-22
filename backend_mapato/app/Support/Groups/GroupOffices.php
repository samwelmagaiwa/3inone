<?php

namespace App\Support\Groups;

/**
 * The offices of a group and what each may do, in one place. The server enforces these rights (the `group_right:` route middleware and the
 * controllers); the app only shows what the server says the person holds.
 *
 * Offices as the group named them (2026-11-22):
 *   mwenyekiti          Chairperson            approves and calls meetings
 *   makamu_mwenyekiti   Deputy Chairperson     stands in for the Chairperson
 *   mweka_hazina        Treasurer              approves money matters, keeps all the financial records
 *   mweka_hazina_msaidizi Assistant Treasurer  helps the Treasurer
 *   katibu              Secretary              coordinates the group's affairs (members, records)
 *   katibu_msaidizi     Assistant Secretary    helps the Secretary
 *   mwenyekiti_miradi   Projects Chairperson   oversees all the group's loans and projects
 *   kamati_miradi       Projects Committee     works with the Projects Chairperson on loans and projects
 * A member with no office is an ordinary member: they see and do only their own things.
 *
 * Deputies and assistants hold the same rights as the officer they help (they act when that officer is away). The business owner (the
 * account head who runs the group in the app) holds every right.
 */
final class GroupOffices
{
    public const OFFICES = [
        'mwenyekiti',
        'makamu_mwenyekiti',
        'mweka_hazina',
        'mweka_hazina_msaidizi',
        'katibu',
        'katibu_msaidizi',
        'mwenyekiti_miradi',
        'kamati_miradi',
    ];

    /** Offices only one member may hold at a time. Committee places can be held by several. */
    public const SINGLE_HOLDER = [
        'mwenyekiti', 'makamu_mwenyekiti', 'mweka_hazina', 'mweka_hazina_msaidizi', 'katibu', 'katibu_msaidizi', 'mwenyekiti_miradi',
    ];

    /**
     * Every right, and what it allows.
     *   view_members      the member register (names, numbers, status, office, phone)
     *   manage_members    register and edit members and their dependants, give a sign-in
     *   approve_members   approve or reject an application, suspend, reinstate, record an exit
     *   view_sensitive    see a member's NIDA number in full
     *   view_finance      every member's money: balances, the transactions list, the group's totals
     *   record_payments   record a payment on a member's behalf (it still waits for verification)
     *   verify_payments   verify or reject a submitted payment (never one's own)
     *   reverse_payments  put a verified payment right with a reversal
     *   manage_contributions  set up contributions and raise a call (a month's JAMII, an event)
     *   grant_exemptions  excuse a member from a contribution (udhuru), with the reason
     *   record_payouts    record money going OUT: a savings withdrawal, a group expense (someone else verifies it)
     *   view_loans        every loan and its decisions
     *   recommend_loans   the projects committee's recommendation on a loan (amount, note)
     *   approve_loans     approve or turn down a loan (never one's own)
     *   view_benefits     every welfare request
     *   approve_benefits  approve or turn down a welfare request, and the amount (never one's own)
     *   manage_assets     the asset register, and every hire (approve, issue, take back) -- the keeper of an asset may do the hires
     *                     of THAT asset whatever their office
     *   decide_hire_charges  the charge for hired things that came back damaged or did not come back
     *   prepare_dividends prepare a dividend run (its period, formula and the approved profit), never post it
     *   approve_dividends approve and post a dividend run someone else prepared
     *   call_meetings     call (and cancel) a meeting
     *   record_meetings   attendance, minutes, resolutions and actions of a meeting; follow the actions up
     *   approve_minutes   approve the secretary's minutes (never one's own), or reopen approved ones
     *   post_announcements  notices to members
     *   send_texts        a text to many members at once (uses the group's SMS)
     *   manage_offices    give or take an office
     *   manage_settings   the group's fees and rules
     *   view_audit        the group's activity log
     *   view_projects     every project, including proposals and the committee's reviews
     *   manage_projects   run the projects: edit one, name its manager, log progress, close it (the Projects Chairperson)
     *   recommend_projects  the projects committee's yes or no on a proposed project, with the reason
     *   approve_projects  approve or turn down a proposed project (never one's own)
     *   request_expenses  ask for money to be spent (a purpose, a payee, an amount, optionally a project)
     *   view_expenses     every expense request and what became of it (a requester always sees their own)
     *   approve_expenses  approve or turn down an expense request (never one's own); paying it is the payout right, verifying it is someone else's
     */
    public const RIGHTS = [
        'view_members', 'manage_members', 'approve_members', 'view_sensitive', 'view_finance',
        'record_payments', 'verify_payments', 'reverse_payments', 'manage_offices', 'manage_settings', 'view_audit',
        'manage_contributions', 'grant_exemptions', 'record_payouts',
        'view_loans', 'recommend_loans', 'approve_loans', 'view_benefits', 'approve_benefits',
        'manage_assets', 'decide_hire_charges',
        'prepare_dividends', 'approve_dividends', 'call_meetings', 'record_meetings', 'post_announcements', 'send_texts',
        'view_projects', 'manage_projects', 'recommend_projects', 'approve_projects',
        'request_expenses', 'view_expenses', 'approve_expenses', 'approve_minutes',
    ];

    private const BY_OFFICE = [
        'mwenyekiti' => ['view_members', 'manage_members', 'approve_members', 'view_sensitive', 'view_finance', 'manage_offices', 'manage_settings', 'view_audit', 'manage_contributions', 'grant_exemptions', 'view_loans', 'approve_loans', 'view_benefits', 'approve_benefits', 'manage_assets', 'decide_hire_charges', 'approve_dividends', 'call_meetings', 'record_meetings', 'post_announcements', 'send_texts', 'view_projects', 'approve_projects', 'request_expenses', 'view_expenses', 'approve_expenses', 'approve_minutes'],
        'makamu_mwenyekiti' => ['view_members', 'manage_members', 'approve_members', 'view_sensitive', 'view_finance', 'manage_offices', 'manage_settings', 'view_audit', 'manage_contributions', 'grant_exemptions', 'view_loans', 'approve_loans', 'view_benefits', 'approve_benefits', 'manage_assets', 'decide_hire_charges', 'approve_dividends', 'call_meetings', 'record_meetings', 'post_announcements', 'send_texts', 'view_projects', 'approve_projects', 'request_expenses', 'view_expenses', 'approve_expenses', 'approve_minutes'],
        'mweka_hazina' => ['view_members', 'view_sensitive', 'view_finance', 'record_payments', 'verify_payments', 'reverse_payments', 'view_audit', 'manage_contributions', 'record_payouts', 'view_loans', 'view_benefits', 'prepare_dividends', 'view_projects', 'request_expenses', 'view_expenses', 'approve_expenses'],
        'mweka_hazina_msaidizi' => ['view_members', 'view_finance', 'record_payments', 'verify_payments', 'view_loans', 'view_benefits', 'view_projects', 'request_expenses', 'view_expenses', 'approve_expenses'],
        'katibu' => ['view_members', 'manage_members', 'view_sensitive', 'record_payments', 'view_audit', 'view_benefits', 'manage_assets', 'record_meetings', 'post_announcements', 'send_texts', 'view_projects', 'request_expenses'],
        'katibu_msaidizi' => ['view_members', 'manage_members', 'record_payments', 'record_meetings', 'post_announcements', 'request_expenses'],
        'mwenyekiti_miradi' => ['view_members', 'view_finance', 'view_loans', 'recommend_loans', 'view_projects', 'manage_projects', 'recommend_projects', 'request_expenses', 'view_expenses'],
        'kamati_miradi' => ['view_members', 'view_loans', 'recommend_loans', 'view_projects', 'recommend_projects', 'request_expenses'],
    ];

    /** @return array<int, string> the rights an office holds (none for no office or an unknown one) */
    public static function rightsOf(?string $office): array
    {
        return self::BY_OFFICE[(string) $office] ?? [];
    }

    public static function isOffice(?string $office): bool
    {
        return in_array((string) $office, self::OFFICES, true);
    }

    public static function isRight(string $right): bool
    {
        return in_array($right, self::RIGHTS, true);
    }
}
