<?php

namespace App\Jobs;

use App\Http\Controllers\API\BackupController;
use App\Models\Business;
use App\Models\User;
use App\Services\Inventory\AuditTrail;
use App\Support\BusinessRemoval;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;

/**
 * "Remove this business", done by the queue worker once the super admin has typed the code, their password and a reason (all checked in
 * BusinessRemovalController before this is queued). First a full snapshot of the database (named when it was asked for); if that cannot
 * be written, nothing is removed. Then the business, its people and its data go, in one transaction (all or nothing). The audit trail
 * and the server log keep who, what, why and the snapshot's name, and a failure is recorded the same way.
 */
class RemoveBusinessJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public int $timeout = 1800;

    /** @param  array<string, mixed>  $plan  what the warning listed (the business, its people) */
    public function __construct(
        public string $businessId,
        public string $adminId,
        public string $reason,
        public string $snapshot,
        public string $ip,
        public array $plan,
    ) {
    }

    public function handle(AuditTrail $audit): void
    {
        $admin = User::query()->withoutGlobalScopes()->find($this->adminId);
        $request = CreateBackupJob::requestFor($admin, $this->ip);
        $name = (string) ($this->plan['business']['name'] ?? $this->businessId);
        $who = $admin?->name ?? 'Super admin';

        $business = Business::withoutAccountScope()->with('owner')->find($this->businessId);
        if ($business === null) {
            return; // already gone
        }

        try {
            app(BackupController::class)->safetySnapshot('before_removing_business', $this->snapshot);
        } catch (\Throwable $e) {
            $this->recordFailure($audit, $request, "{$who} asked to remove \"{$name}\", but the safety backup could not be written, so NOTHING was removed: {$e->getMessage()}");

            return;
        }

        try {
            $result = BusinessRemoval::remove($business);
        } catch (\Throwable $e) {
            $this->recordFailure($audit, $request, "{$who} asked to remove \"{$name}\", but the removal failed and NOTHING was removed: {$e->getMessage()}");

            return;
        }

        $summary = "{$who} (super admin) REMOVED the business \"{$name}\" (owner " . ($this->plan['business']['owner'] ?? '-') . ', '
            . count($this->plan['users'] ?? []) . ' account(s), ' . array_sum($result['tables']) . " row(s)). Reason: {$this->reason}. Safety backup: {$this->snapshot}";
        $audit->record($request, 'business', null, 'business_removed', ($this->plan['business'] ?? []) + ['users' => $this->plan['users'] ?? []], null, $summary);
        Log::warning($summary);
    }

    private function recordFailure(AuditTrail $audit, $request, string $summary): void
    {
        Log::error($summary, ['business_id' => $this->businessId]);
        $audit->record($request, 'business', null, 'business_removal_failed', $this->plan['business'] ?? null, null, $summary);
    }
}
