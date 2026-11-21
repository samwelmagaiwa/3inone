<?php

namespace App\Support\Groups;

use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Who the signed-in person is in their group and what they may do.
 *
 *   - the business owner (the account head the group runs under) holds every right;
 *   - a member who signs in holds the rights of the office they hold, and only while their membership is active;
 *   - anyone else holds none.
 *
 * Every group_* query is already limited to the signed-in person's business by the query grammar; this decides what they may do inside it.
 */
final class GroupAccess
{
    /** @var array<string, array<string, mixed>|null> user id => their member row (memoised per request) */
    private static array $members = [];

    public static function isOwner(?User $user): bool
    {
        return $user !== null
            && (string) $user->accountHeadId() === (string) $user->id
            && strtolower((string) $user->role) !== User::GROUP_MEMBER_ROLE
            && $user->canUseService('groups');
    }

    /** The member row of the signed-in person (any status), or null when they are not a member of their group. */
    public static function member(?User $user): ?array
    {
        if ($user === null) {
            return null;
        }
        $key = (string) $user->id;
        if (!array_key_exists($key, self::$members)) {
            $row = DB::table('group_members')->where('user_id', $key)->first();
            self::$members[$key] = $row === null ? null : (array) $row;
        }

        return self::$members[$key];
    }

    /** @return array<int, string> */
    public static function rights(?User $user): array
    {
        if ($user === null) {
            return [];
        }
        if (self::isOwner($user)) {
            return GroupOffices::RIGHTS;
        }
        $member = self::member($user);
        if ($member === null || $member['status'] !== GroupMembers::ACTIVE) {
            return [];
        }

        return GroupOffices::rightsOf($member['office'] ?? null);
    }

    public static function can(?User $user, string $right): bool
    {
        return in_array($right, self::rights($user), true);
    }

    /** Forget what was looked up (a test, or after the person's member row changed in this request). */
    public static function forget(): void
    {
        self::$members = [];
    }
}
