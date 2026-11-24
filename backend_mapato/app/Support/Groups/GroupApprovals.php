<?php

namespace App\Support\Groups;

use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * A new member's request goes to the management (the chairperson, the vice chairperson, the secretary and the assistant secretary): each of
 * them is told, in the app, that a request waits. Whoever of them decides first decides for all (one approval is enough, the rest of the
 * process goes on as usual), and the notice of everyone else changes to say who decided: "Already approved by ...".
 */
final class GroupApprovals
{
    /** The leaders who see a membership request and may approve it. */
    public const MANAGEMENT = ['mwenyekiti', 'makamu_mwenyekiti', 'katibu', 'katibu_msaidizi'];

    /** Tell the management that a request waits. [exceptMemberId] is whoever registered it, when they are one of the management themselves. */
    public static function requested(int $memberId, string $name, string $by, ?int $exceptMemberId = null): void
    {
        $ids = DB::table('group_members')->where('status', GroupMembers::ACTIVE)->whereIn('office', self::MANAGEMENT)
            ->when($exceptMemberId !== null, fn ($q) => $q->where('id', '!=', $exceptMemberId))->pluck('id');
        $rows = [];
        foreach ($ids as $id) {
            $rows[] = [
                'member_id' => (int) $id, 'kind' => 'member_request',
                'title' => mb_substr("Ombi jipya la uanachama: {$name}", 0, 150), 'title_en' => mb_substr("New membership request: {$name}", 0, 150),
                'body' => mb_substr("Amesajiliwa na {$by}. Linasubiri idhini ya uongozi: mmoja akiidhinisha inatosha.", 0, 255),
                'body_en' => mb_substr("Registered by {$by}. Waiting for the management: one approval is enough.", 0, 255),
                'link_type' => 'member', 'link_id' => $memberId, 'created_at' => now(),
            ];
        }
        if ($rows !== []) {
            DB::table('group_notifications')->insert($rows);
        }
    }

    /** One of the management decided: every notice of that request now says who did, whatever the others had seen. */
    public static function decided(int $memberId, string $name, bool $approved, string $byName): void
    {
        $titleSw = $approved ? "{$name}: tayari imeidhinishwa na {$byName}" : "{$name}: ombi limekataliwa na {$byName}";
        $titleEn = $approved ? "{$name}: already approved by {$byName}" : "{$name}: request turned down by {$byName}";
        $bodySw = $approved ? 'Hakuna haja ya kuidhinisha tena. Hatua zinazofuata zinaendelea kama kawaida.' : 'Hakuna haja ya kuamua tena.';
        $bodyEn = $approved ? 'Nothing more to approve. The next steps go on as usual.' : 'Nothing more to decide.';
        DB::table('group_notifications')->where('link_type', 'member')->where('link_id', $memberId)->where('kind', 'member_request')->update([
            'kind' => $approved ? 'member_approved' : 'member_declined',
            'title' => mb_substr($titleSw, 0, 150), 'title_en' => mb_substr($titleEn, 0, 150), 'body' => $bodySw, 'body_en' => $bodyEn,
        ]);
    }

    /** The name of the person who stands for this user in the group: their member name, or the account's name. */
    public static function nameOf(User $user): string
    {
        $member = GroupAccess::member($user);

        return $member !== null ? (string) $member['full_name'] : (string) $user->name;
    }

    /** Who approved this member (a user id is kept on the file). */
    public static function approverName(object $row): ?string
    {
        if (empty($row->approved_by)) {
            return null;
        }
        $member = DB::table('group_members')->where('user_id', (string) $row->approved_by)->value('full_name');
        if ($member !== null) {
            return (string) $member;
        }
        $user = User::query()->withoutGlobalScopes()->find((string) $row->approved_by);

        return $user?->name;
    }
}
