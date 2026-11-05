<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * The salon's money pages used to open on the one "reports" right. They are now rights of their own (the Salon tab of Reports, profit,
     * payroll, the cashbook, export, the schedule), so someone an owner had given "reports" by hand keeps what it opened: they are given the
     * new rights once. The roles' own sets are not touched here (they are the roles' defaults) and nothing is taken from anyone.
     */
    public function up(): void
    {
        $opened = ['inv_salon_reports', 'inv_salon_profit', 'inv_salon_payroll', 'inv_salon_cashbook', 'inv_salon_export', 'inv_salon_schedule'];

        foreach (DB::table('users')->whereNotNull('permissions')->get(['id', 'permissions']) as $user) {
            $granted = json_decode((string) $user->permissions, true);
            if (!is_array($granted) || !in_array('inv_view_reports', $granted, true)) {
                continue;
            }
            $merged = array_values(array_unique(array_merge($granted, $opened)));
            if (count($merged) !== count($granted)) {
                DB::table('users')->where('id', $user->id)->update(['permissions' => json_encode($merged)]);
            }
        }
    }

    public function down(): void
    {
        // The rights stay given: taking them back could lock someone out of what they had.
    }
};
