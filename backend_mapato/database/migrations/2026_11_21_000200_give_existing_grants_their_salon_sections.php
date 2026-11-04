<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * The salon's sections used to open on shared rights (reports, selling, settings). Each is now a right of its own, so someone an owner
     * had given one of those shared rights by hand keeps what it opened: they are given the matching sections, once. Roles' own starting
     * sets are not touched here (they are the roles' defaults), and nothing is taken from anyone.
     */
    public function up(): void
    {
        $opens = [
            'inv_view_reports' => ['inv_salon_money', 'inv_salon_insights', 'inv_salon_team', 'inv_salon_stylists', 'inv_salon_equipment', 'inv_salon_branch_stock', 'inv_salon_feedback'],
            'inv_manage_settings' => ['inv_salon_equipment', 'inv_salon_branch_stock'],
            'inv_create_sales' => ['inv_salon_appointments', 'inv_salon_walkins', 'inv_salon_rebook', 'inv_salon_stylists', 'inv_salon_team', 'inv_salon_feedback'],
        ];

        foreach (DB::table('users')->whereNotNull('permissions')->get(['id', 'permissions']) as $user) {
            $granted = json_decode((string) $user->permissions, true);
            if (!is_array($granted) || $granted === []) {
                continue;
            }
            $add = [];
            foreach ($opens as $shared => $sections) {
                if (in_array($shared, $granted, true)) {
                    $add = array_merge($add, $sections);
                }
            }
            $merged = array_values(array_unique(array_merge($granted, $add)));
            if (count($merged) !== count($granted)) {
                DB::table('users')->where('id', $user->id)->update(['permissions' => json_encode($merged)]);
            }
        }
    }

    public function down(): void
    {
        // The sections stay given: taking them back could lock someone out of what they had.
    }
};
