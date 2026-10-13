<?php

use App\Support\Tenancy\TenantTables;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Step 2 of 3. inventory_settings was keyed by the setting name alone, so a
     * second business could never have its own "tax_percent". Rebuild it with a
     * surrogate id and a (owner_id, key) unique index, copy the existing rows
     * across, and keep the old table as inventory_settings_legacy (nothing reads
     * it) so this can be rolled back. Drop the legacy table by hand once the
     * depot has been running on the new one for a while.
     *
     * The copied rows have no owner yet; step 3 assigns the depot's owner.
     */
    public function up(): void
    {
        Schema::create('inventory_settings_next', function (Blueprint $table) {
            $table->id();
            $table->uuid(TenantTables::OWNER_COLUMN)->nullable()->index();
            $table->string('key', 64);
            $table->text('value')->nullable();
            $table->timestamp('updated_at')->nullable();

            $table->unique([TenantTables::OWNER_COLUMN, 'key']);
        });

        foreach (DB::table('inventory_settings')->get() as $row) {
            DB::table('inventory_settings_next')->insert([
                'key' => $row->key,
                'value' => $row->value,
                'updated_at' => $row->updated_at,
            ]);
        }

        Schema::rename('inventory_settings', 'inventory_settings_legacy');
        Schema::rename('inventory_settings_next', 'inventory_settings');
    }

    public function down(): void
    {
        Schema::rename('inventory_settings', 'inventory_settings_next');
        Schema::rename('inventory_settings_legacy', 'inventory_settings');
        Schema::drop('inventory_settings_next');
    }
};
