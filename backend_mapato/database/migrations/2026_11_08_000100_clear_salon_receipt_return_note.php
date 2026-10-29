<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * A shop's receipt says "goods sold cannot be returned without a receipt". The salon was given the same line when its settings were
 * seeded, and it does not belong on a salon's receipt (services are not returned). Where a salon still has exactly that line it is
 * cleared; a note the owner wrote is left alone.
 */
return new class extends Migration {
    private const NOTE = 'Bidhaa zilizouzwa haziruhusiwi kurudishwa bila risiti.';

    public function up(): void
    {
        if (!Schema::hasTable('inventory_settings') || !Schema::hasColumn('inventory_settings', 'service')) {
            return;
        }

        DB::table('inventory_settings')
            ->where('service', 'salon')
            ->where('key', 'receipt_footer_note')
            ->where('value', self::NOTE)
            ->update(['value' => '', 'updated_at' => now()]);
    }

    public function down(): void
    {
        // The line is not put back: it never belonged on a salon's receipt.
    }
};
