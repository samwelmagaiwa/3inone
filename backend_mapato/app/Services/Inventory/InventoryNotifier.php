<?php

namespace App\Services\Inventory;

use App\Models\User;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;

/**
 * The other half of an approval flow that request/decide controllers were
 * missing entirely: submitting a write-off or return left the approver with
 * no signal a request existed, and approving/rejecting it left the submitter
 * with no signal it had been decided -- both sides only found out by opening
 * the screen and checking. This fan-outs one row per recipient into
 * inventory_notifications so the app can show a real inbox instead.
 */
class InventoryNotifier
{
    /**
     * Notify every user who holds ANY of the given inventory permissions
     * (matching the OR semantics of the inv_perm middleware), e.g. everyone
     * who could act on a newly-submitted approval request.
     */
    public function notifyByPermission(
        array $permissions,
        string $type,
        string $title,
        string $body,
        array $data = [],
        ?string $excludeUserId = null,
    ): void {
        // `users` is shared by every business: only people in the business that is
        // acting are told. (With nobody signed in, e.g. a queued job, nothing narrows it.)
        $members = TenantContext::viewer()?->accountMemberIds();

        $recipientIds = User::query()
            ->where('is_active', true)
            ->when($members !== null, fn ($q) => $q->whereIn('id', $members))
            ->get(['id', 'role', 'full_access', 'permissions'])
            ->filter(fn (User $u) => $excludeUserId === null || $u->id !== $excludeUserId)
            ->filter(fn (User $u) => collect($permissions)
                ->contains(fn (string $perm) => $u->hasInventoryPermission($perm)))
            ->pluck('id');

        $this->insertFor($recipientIds, $type, $title, $body, $data);
    }

    /** Notify one specific user directly, e.g. the original submitter. */
    public function notifyUser(
        ?string $userId,
        string $type,
        string $title,
        string $body,
        array $data = [],
    ): void {
        if ($userId === null || $userId === '') {
            return;
        }
        $this->insertFor(collect([$userId]), $type, $title, $body, $data);
    }

    private function insertFor(
        \Illuminate\Support\Collection $userIds,
        string $type,
        string $title,
        string $body,
        array $data,
    ): void {
        $userIds = $userIds->filter()->unique()->values();
        if ($userIds->isEmpty()) {
            return;
        }

        $now = now();
        $rows = $userIds->map(fn (string $id) => [
            'user_id' => $id,
            'type' => $type,
            'title' => $title,
            'body' => $body,
            'data' => $data === [] ? null : json_encode($data),
            'created_at' => $now,
            'updated_at' => $now,
        ])->all();

        DB::table('inventory_notifications')->insert($rows);
    }
}
