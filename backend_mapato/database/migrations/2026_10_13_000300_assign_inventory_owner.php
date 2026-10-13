<?php

use App\Services\Inventory\InventoryOwnership;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Step 3 of 3 (data). Hand the existing, previously shared depot to the
     * business that runs it, so that the day isolation switches on that business
     * -- and its staff -- sees exactly what it saw yesterday.
     *
     *  - Only rows with no owner are touched, so running this again changes nothing.
     *  - Inventory staff who belong to no business (created by a super admin, say)
     *    are moved under the depot owner; each move is recorded in
     *    tenancy_reparent_log with the old value, so it can be undone by hand.
     *  - If the owner cannot be told (nobody, or nobody active, holds the inventory
     *    service) nothing is guessed: the rows stay unowned, which only a super
     *    admin can see, and the reason is logged. Fix it later with
     *    `php artisan inventory:assign-owner <email>`.
     */
    public function up(): void
    {
        Schema::create('tenancy_reparent_log', function (Blueprint $table) {
            $table->id();
            $table->uuid('user_id')->index();
            $table->uuid('old_created_by')->nullable();
            $table->uuid('new_created_by');
            $table->string('reason');
            $table->timestamp('created_at')->nullable();
        });

        $ownership = app(InventoryOwnership::class);
        $owner = $ownership->findDepotOwner();

        if ($owner === null) {
            if ($this->isFreshInstall()) {
                // No depot has ever traded here. The settings and crate types the first
                // migrations seeded belong to nobody and would be shared by whoever
                // looks; every business gets its own when it is given the inventory
                // service, so drop the shared ones.
                DB::table('inventory_settings')->whereNull('owner_id')->delete();
                DB::table('inventory_crate_types')->whereNull('owner_id')->delete();

                return;
            }

            Log::warning('Inventory isolation: no active owner holds the inventory service, so existing inventory rows were left without an owner. Run `php artisan inventory:assign-owner <email>` to assign them.');

            return;
        }

        $candidates = $ownership->candidates();
        if ($candidates->count() > 1) {
            // Several owners hold inventory, so the shared depot could belong to any of
            // them. The one whose accounts created the most sales and products got it;
            // the others will see an empty depot. Say so loudly so it is checked at once.
            Log::warning('Inventory isolation: SEVERAL owners hold the inventory service; the depot was given to the one that has been trading most. Check it is the right one.', [
                'chosen' => $owner->email,
                'others' => $candidates->where('id', '!=', $owner->id)->pluck('email')->all(),
                'fix_if_wrong' => 'php artisan inventory:assign-owner <right-owner-email> --from=<chosen-email> --dry-run   (then without --dry-run)',
            ]);
        }

        $result = $ownership->assign($owner);

        Log::info('Inventory isolation: existing depot assigned to its owner.', [
            'owner' => $owner->email,
            'staff_adopted' => $result['adopted'],
            'rows_assigned' => array_filter($result['rows']),
        ]);
    }

    /** True when no product, sale or customer exists: there is no depot to hand over. */
    private function isFreshInstall(): bool
    {
        foreach (['inventory_products', 'inventory_sales', 'inventory_customers'] as $table) {
            if (DB::table($table)->exists()) {
                return false;
            }
        }

        return true;
    }

    public function down(): void
    {
        // Ownership is data, not structure: nothing to undo here. The moved staff are
        // listed in tenancy_reparent_log, which is dropped only with this migration.
        Schema::dropIfExists('tenancy_reparent_log');
    }
};
