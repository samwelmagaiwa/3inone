<?php

namespace App\Support\Groups;

use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

/**
 * The member register's rules: statuses and the moves between them, member numbers, and how a member is shown.
 *
 * A person is SUBMITTED when their application is recorded. The approver makes them ACTIVE (they get their permanent member number then)
 * or REJECTED. An active member can be SUSPENDED and reinstated, and leaves as EXITED or DECEASED. Nothing is deleted: a member who left
 * keeps their history, their referral line and their money records.
 */
final class GroupMembers
{
    public const SUBMITTED = 'submitted';
    public const ACTIVE = 'active';
    public const REJECTED = 'rejected';
    public const SUSPENDED = 'suspended';
    public const EXITED = 'exited';
    public const DECEASED = 'deceased';

    public const STATUSES = [self::SUBMITTED, self::ACTIVE, self::REJECTED, self::SUSPENDED, self::EXITED, self::DECEASED];

    /** action => [statuses it may start from, status it leaves the member in] */
    public const MOVES = [
        'approve' => [[self::SUBMITTED], self::ACTIVE],
        'reject' => [[self::SUBMITTED], self::REJECTED],
        'suspend' => [[self::ACTIVE], self::SUSPENDED],
        'reinstate' => [[self::SUSPENDED], self::ACTIVE],
        'exit' => [[self::ACTIVE, self::SUSPENDED], self::EXITED],
        'deceased' => [[self::ACTIVE, self::SUSPENDED], self::DECEASED],
    ];

    public const RELATIONSHIPS = ['parent', 'spouse', 'child', 'parent_in_law', 'other'];

    /** A fresh application reference, unique in the group ("APP-7KQ2MX"). */
    public static function newApplicationRef(): string
    {
        do {
            $ref = 'APP-' . strtoupper(Str::random(6));
        } while (DB::table('group_members')->where('application_ref', $ref)->exists());

        return $ref;
    }

    /** The next member number with the group's prefix: MEG-0001, MEG-0002, ... */
    public static function nextNumber(): string
    {
        $prefix = GroupSettings::get('member_prefix');
        $highest = 0;
        foreach (DB::table('group_members')->where('member_number', 'like', $prefix . '-%')->pluck('member_number') as $number) {
            $tail = substr((string) $number, strlen($prefix) + 1);
            if (ctype_digit($tail)) {
                $highest = max($highest, (int) $tail);
            }
        }

        return $prefix . '-' . str_pad((string) ($highest + 1), 4, '0', STR_PAD_LEFT);
    }

    /**
     * Give [memberId] the next free member number. Two approvals at the same moment cannot take the same number: the unique index refuses
     * the second, which then takes the one after.
     */
    public static function assignNumber(int $memberId): string
    {
        for ($try = 0; $try < 5; $try++) {
            $number = self::nextNumber();
            try {
                DB::table('group_members')->where('id', $memberId)->update(['member_number' => $number, 'updated_at' => now()]);

                return $number;
            } catch (QueryException) {
                continue;
            }
        }
        throw new InvalidArgumentException('Could not give a member number; try again.');
    }

    /**
     * What still stands between an application and approval, as codes the app words: the joining fee and (when the group asks for them
     * before membership) the shares must be paid AND verified.
     *
     * @return array<int, string>
     */
    public static function approvalBlockers(int $memberId): array
    {
        $blockers = [];
        $paid = GroupLedger::balances($memberId);
        if (($paid['joining_fee'] ?? 0) + 0.001 < GroupSettings::money('joining_fee')) {
            $blockers[] = 'joining_fee_unpaid';
        }
        if (GroupSettings::get('shares_required_for') === 'membership' && ($paid['shares'] ?? 0) + 0.001 < GroupSettings::money('share_amount')) {
            $blockers[] = 'shares_unpaid';
        }

        return $blockers;
    }

    /** Record a change of status or office (never edited). */
    public static function event(int $memberId, string $kind, ?string $from, ?string $to, ?string $reason, ?string $by): void
    {
        DB::table('group_member_events')->insert([
            'member_id' => $memberId, 'kind' => $kind, 'from_value' => $from, 'to_value' => $to,
            'reason' => $reason, 'by_user' => $by, 'created_at' => now(),
        ]);
    }

    public static function encryptNida(?string $nida): ?string
    {
        $nida = $nida === null ? null : preg_replace('/\s+/', '', $nida);

        return $nida === null || $nida === '' ? null : Crypt::encryptString($nida);
    }

    /** A keyed fingerprint of a NIDA number, so the same number given twice is found without decrypting every member. */
    public static function nidaHash(?string $nida): ?string
    {
        $nida = $nida === null ? null : preg_replace('/[^0-9A-Za-z]/', '', $nida);

        return $nida === null || $nida === '' ? null : hash_hmac('sha256', strtoupper($nida), (string) config('app.key'));
    }

    public static function nida(?string $stored): ?string
    {
        if ($stored === null || $stored === '') {
            return null;
        }
        try {
            return Crypt::decryptString($stored);
        } catch (\Throwable) {
            return null;
        }
    }

    /** "19900101-12345-00001-25" -> "••••••••••••••••••01-25": enough to recognise, not enough to use. */
    public static function maskNida(?string $nida): ?string
    {
        if ($nida === null || $nida === '') {
            return null;
        }
        $keep = 5;

        return str_repeat('•', max(0, mb_strlen($nida) - $keep)) . mb_substr($nida, -$keep);
    }

    /**
     * A member as the app shows them. The NIDA number is shown whole only to whoever may see it ([sensitive]), masked to everyone else.
     *
     * @param  array<string, mixed>|object  $row
     * @return array<string, mixed>
     */
    public static function payload(array|object $row, bool $sensitive = false): array
    {
        $r = (array) $row;
        $nida = self::nida($r['nida'] ?? null);

        return [
            'id' => (int) $r['id'],
            'member_number' => $r['member_number'],
            'application_ref' => $r['application_ref'],
            'full_name' => $r['full_name'],
            'phone' => $r['phone'],
            'alt_phone' => $r['alt_phone'] ?? null,
            'email' => $r['email'] ?? null,
            'nida' => $sensitive ? $nida : self::maskNida($nida),
            'nida_masked' => !$sensitive && $nida !== null,
            'date_of_birth' => $r['date_of_birth'] ?? null,
            'gender' => $r['gender'] ?? null,
            'region' => $r['region'] ?? null,
            'district' => $r['district'] ?? null,
            'ward' => $r['ward'] ?? null,
            'street' => $r['street'] ?? null,
            'occupation' => $r['occupation'] ?? null,
            'office' => $r['office'] ?? null,
            'status' => $r['status'],
            'status_reason' => $r['status_reason'] ?? null,
            'referrer_id' => isset($r['referrer_id']) ? (int) $r['referrer_id'] : null,
            'referrer_name' => $r['referrer_name'] ?? null,
            'founding' => (bool) ($r['founding'] ?? false),
            'joined_on' => $r['joined_on'] ?? null,
            'has_sign_in' => !empty($r['user_id']),
            // The profile photo, as a signed link that expires (null when none): lists and Home show it beside the name.
            'photo_url' => \App\Support\PrivateFile::url($r['photo_path'] ?? null),
            'created_at' => isset($r['created_at']) ? (string) $r['created_at'] : null,
        ];
    }
}
