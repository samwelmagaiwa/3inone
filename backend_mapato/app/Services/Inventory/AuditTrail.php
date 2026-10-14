<?php

namespace App\Services\Inventory;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Area 13 — the permanent record.
 *
 * Every sale, price change, stock adjustment and payment lands here with the
 * user, the time and the before/after state. Rows are only ever inserted.
 */
class AuditTrail
{
    public function record(
        ?Request $request,
        string $entityType,
        ?int $entityId,
        string $action,
        ?array $before = null,
        ?array $after = null,
        ?string $summary = null,
    ): void {
        $user = $request?->user();

        DB::table('inventory_audit_log')->insert([
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'action' => $action,
            'before' => $before !== null ? json_encode($this->clean($before)) : null,
            'after' => $after !== null ? json_encode($this->clean($after)) : null,
            // The columns are 255 characters. SQLite lets a longer line in; MariaDB refuses it and the whole request
            // fails, so a line that grew (a long business name, a dozen changed prices) is cut here, once, for everybody.
            // Nothing is lost: the before/after columns carry the detail.
            'summary' => $summary === null ? null : Str::limit($summary, 250, '...'),
            'user_id' => $user?->id,
            'user_name' => $user?->name === null ? null : Str::limit((string) $user->name, 250, ''),
            'created_at' => now(),
        ]);
    }

    /** Keep secrets and noise out of the log. */
    private function clean(array $data): array
    {
        unset($data['password'], $data['token'], $data['_token']);

        return $data;
    }
}
