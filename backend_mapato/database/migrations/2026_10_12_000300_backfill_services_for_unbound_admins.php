<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * The API now serves a service only to users who have been given it. An
     * admin created before that rule may have no user_services rows at all and
     * still be running a business on the strength of the app showing them the
     * picker -- enforcing the rule would lock them out overnight.
     *
     * So for admins with NO service rows today, give them the services their own
     * data proves they use:
     *   transport  drivers or vehicles they created
     *   rental     properties they own
     *   inventory  sales or products they created, or inventory-role staff
     *
     * Additive only: admins who already have any binding are untouched, and an
     * admin with no data at all stays unbound (a super admin assigns them).
     */
    public function up(): void
    {
        $unbound = DB::table('users')
            ->whereIn('role', ['admin', 'administrator'])
            ->whereNotExists(function ($q) {
                $q->select(DB::raw(1))->from('user_services')->whereColumn('user_services.user_id', 'users.id');
            })
            ->pluck('id');

        foreach ($unbound as $adminId) {
            $services = [];

            $usesTransport = DB::table('users')->where('created_by', $adminId)->where('role', 'driver')->exists()
                || (Schema::hasColumn('devices', 'created_by') && DB::table('devices')->where('created_by', $adminId)->exists());
            if ($usesTransport) {
                $services[] = 'transport';
            }

            if (Schema::hasTable('rental_properties') && DB::table('rental_properties')->where('owner_id', $adminId)->exists()) {
                $services[] = 'rental';
            }

            $usesInventory = DB::table('users')->where('created_by', $adminId)
                    ->whereIn('role', ['manager', 'operator', 'sales_officer'])->exists()
                || (Schema::hasTable('inventory_sales') && DB::table('inventory_sales')->where('created_by', $adminId)->exists())
                || (Schema::hasTable('inventory_products') && DB::table('inventory_products')->where('created_by', $adminId)->exists());
            if ($usesInventory) {
                $services[] = 'inventory';
            }

            foreach ($services as $service) {
                DB::table('user_services')->insert([
                    'user_id' => $adminId,
                    'service_type' => $service,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
        }
    }

    public function down(): void
    {
        // Not reversible: we cannot tell inferred rows from ones a super admin set.
    }
};
