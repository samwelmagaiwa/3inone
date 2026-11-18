<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * "Sales by branch and by person" used to open on the shared reports right, so it could not be switched off on its own. It is now a right
     * of its own (inv_salon_branch_sales). Someone an owner had given the reports right BY HAND keeps what it opened: they are given the new
     * right, once. The roles' own starting sets are the roles' defaults (the accountant starts without it) and nothing is taken from anyone.
     */
    public function up(): void
    {
        foreach (DB::table('users')->whereNotNull('permissions')->get(['id', 'permissions']) as $user) {
            $granted = json_decode((string) $user->permissions, true);
            if (!is_array($granted) || !in_array('inv_view_reports', $granted, true) || in_array('inv_salon_branch_sales', $granted, true)) {
                continue;
            }
            $granted[] = 'inv_salon_branch_sales';
            DB::table('users')->where('id', $user->id)->update(['permissions' => json_encode(array_values($granted))]);
        }
    }

    public function down(): void
    {
        // The right stays given: taking it back could lock someone out of what they had.
    }
};
