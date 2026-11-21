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
     *   manage_offices    give or take an office
     *   manage_settings   the group's fees and rules
     *   view_audit        the group's activity log
     */
    public const RIGHTS = [
        'view_members', 'manage_members', 'approve_members', 'view_sensitive', 'view_finance',
        'record_payments', 'verify_payments', 'reverse_payments', 'manage_offices', 'manage_settings', 'view_audit',
    ];

    private const BY_OFFICE = [
        'mwenyekiti' => ['view_members', 'manage_members', 'approve_members', 'view_sensitive', 'view_finance', 'manage_offices', 'manage_settings', 'view_audit'],
        'makamu_mwenyekiti' => ['view_members', 'manage_members', 'approve_members', 'view_sensitive', 'view_finance', 'manage_offices', 'manage_settings', 'view_audit'],
        'mweka_hazina' => ['view_members', 'view_sensitive', 'view_finance', 'record_payments', 'verify_payments', 'reverse_payments', 'view_audit'],
        'mweka_hazina_msaidizi' => ['view_members', 'view_finance', 'record_payments', 'verify_payments'],
        'katibu' => ['view_members', 'manage_members', 'view_sensitive', 'record_payments', 'view_audit'],
        'katibu_msaidizi' => ['view_members', 'manage_members', 'record_payments'],
        'mwenyekiti_miradi' => ['view_members', 'view_finance'],
        'kamati_miradi' => ['view_members'],
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
