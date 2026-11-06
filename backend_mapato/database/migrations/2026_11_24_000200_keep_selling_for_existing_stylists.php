<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Selling at the counter (and seeing the clients' feedback about oneself) now start switched OFF for a stylist, nail technician or
     * makeup artist: the owner gives them on the access-rights screen. Someone who is already working keeps what they could do until now:
     * their selling right is written down for them once, so nobody finds the till gone the day this is installed.
     */
    public function up(): void
    {
        foreach (DB::table('users')->whereIn('role', ['hair_stylist', 'nail_technician', 'lash_makeup_artist'])->get(['id', 'permissions', 'denied_permissions']) as $user) {
            $granted = json_decode((string) $user->permissions, true);
            $granted = is_array($granted) ? $granted : [];
            $denied = json_decode((string) $user->denied_permissions, true);
            if (in_array('inv_create_sales', $granted, true) || (is_array($denied) && in_array('inv_create_sales', $denied, true))) {
                continue;
            }
            $granted[] = 'inv_create_sales';
            DB::table('users')->where('id', $user->id)->update(['permissions' => json_encode(array_values(array_unique($granted)))]);
        }
    }

    public function down(): void
    {
        // The rights stay given.
    }
};
