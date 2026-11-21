<?php

namespace App\Support\Groups;

use Illuminate\Support\Facades\DB;

/** The group's activity log: who did what, in plain words. Written by every action that changes the group's records; never edited. */
final class GroupAudit
{
    public static function record(?string $userId, string $action, string $summary, ?string $subjectType = null, ?int $subjectId = null): void
    {
        DB::table('group_audit_log')->insert([
            'user_id' => $userId,
            'action' => $action,
            'subject_type' => $subjectType,
            'subject_id' => $subjectId,
            'summary' => mb_substr($summary, 0, 500),
            'created_at' => now(),
        ]);
    }

    /** @return array<int, array<string, mixed>> newest first */
    public static function recent(int $limit = 100, ?string $before = null): array
    {
        $q = DB::table('group_audit_log as a')->leftJoin('users as u', 'u.id', '=', 'a.user_id')->orderByDesc('a.id')->limit($limit);
        if ($before !== null && ctype_digit($before)) {
            $q->where('a.id', '<', (int) $before);
        }

        return $q->get(['a.id', 'a.action', 'a.summary', 'a.subject_type', 'a.subject_id', 'a.created_at', 'u.name as by_name'])
            ->map(fn ($r) => (array) $r)->all();
    }
}
