<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * A vehicle used to be owned only through the driver it was assigned to,
     * so an unassigned vehicle belonged to nobody and every admin could see
     * (and edit) it. created_by gives it an owner from the moment it is made.
     *
     * Additive and nullable: nothing is dropped and no existing row is made
     * invisible to the admin who really owns it.
     *
     * Backfill:
     *  1. Assigned vehicles take the creator of their driver's login.
     *  2. Unassigned legacy vehicles are claimed only when every driver in the
     *     system was created by one and the same user -- i.e. there is exactly
     *     one possible owner. With several owners it is unknowable, so they
     *     stay NULL and only super_admin sees them until one is assigned.
     */
    public function up(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            $table->uuid('created_by')->nullable()->after('driver_id')->index();
        });

        DB::table('devices')
            ->whereNotNull('driver_id')
            ->orderBy('id')
            ->each(function ($device) {
                $creator = DB::table('drivers')
                    ->join('users', 'users.id', '=', 'drivers.user_id')
                    ->where('drivers.id', $device->driver_id)
                    ->value('users.created_by');

                if ($creator) {
                    DB::table('devices')->where('id', $device->id)->update(['created_by' => $creator]);
                }
            });

        $creators = DB::table('drivers')
            ->join('users', 'users.id', '=', 'drivers.user_id')
            ->whereNotNull('users.created_by')
            ->distinct()
            ->pluck('users.created_by');

        $driversWithoutCreator = DB::table('drivers')
            ->join('users', 'users.id', '=', 'drivers.user_id')
            ->whereNull('users.created_by')
            ->exists();

        if ($creators->count() === 1 && !$driversWithoutCreator) {
            DB::table('devices')
                ->whereNull('created_by')
                ->update(['created_by' => $creators->first()]);
        }
    }

    public function down(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            $table->dropIndex(['created_by']);
            $table->dropColumn('created_by');
        });
    }
};
