<?php

use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    /**
     * Every business that already exists gets its business record.
     *
     * The head of each account (admin / administrator / landlord) becomes the owner of a
     * `businesses` row: named after the registration form when they registered themselves
     * (otherwise after the owner), with the contact details they already gave. They are put on
     * the `free` plan with no expiry, so adding billing fields changes nobody's access.
     *
     * Adds rows only; accounts and data are not touched, and running it twice adds nothing.
     */
    public function up(): void
    {
        $have = DB::table('businesses')->pluck('owner_id')->flip();

        DB::table('users')
            ->leftJoin('business_registrations', 'business_registrations.user_id', '=', 'users.id')
            ->whereIn(DB::raw('LOWER(users.role)'), User::ACCOUNT_HEAD_ROLES)
            ->orderBy('users.id')
            ->select([
                'users.id', 'users.name', 'users.email', 'users.phone_number',
                'business_registrations.business_name', 'business_registrations.address',
                'business_registrations.district', 'business_registrations.region',
            ])
            ->chunk(200, function ($owners) use ($have) {
                $rows = [];
                foreach ($owners as $owner) {
                    if (isset($have[$owner->id])) {
                        continue;
                    }

                    $address = trim(implode(', ', array_filter([
                        $owner->address, $owner->district, $owner->region,
                    ], fn ($part) => $part !== null && trim((string) $part) !== '')));

                    $rows[] = [
                        'id' => (string) Str::uuid(),
                        'owner_id' => $owner->id,
                        'name' => trim((string) ($owner->business_name ?: $owner->name)) ?: 'Business',
                        'address' => $address !== '' ? mb_substr($address, 0, 500) : null,
                        'phone' => $owner->phone_number ? mb_substr((string) $owner->phone_number, 0, 30) : null,
                        'email' => $owner->email,
                        'plan' => config('billing.default_plan', 'free'),
                        'valid_until' => null,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ];
                }

                if ($rows !== []) {
                    DB::table('businesses')->insert($rows);
                }
            });
    }

    public function down(): void
    {
        // Nothing to undo: the table itself is dropped by the migration that created it, and
        // rows added here cannot be told apart from ones a super admin has since edited.
    }
};
