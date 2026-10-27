<?php

namespace App\Support\Salon;

use App\Http\Controllers\API\Inventory\SalonSetupController;
use App\Support\Tenancy\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * What a salon starts with: the ready-made categories (each named "Kiswahili / English", the apps show the half of the user's
 * language) and the brands of products salons commonly use. Put in ONCE per salon, the first time its categories or brands are
 * listed; after that the owner is free to rename, switch off or delete any of them and they do not come back.
 * A category is a KIND of service; a brand is only the make of a product a service uses, and is always optional.
 */
final class SalonCatalog
{
    private const FLAG = 'salon_catalog_seeded';

    /** @var array<int, array{0: string, 1: string}> */
    public const BRANDS = [
        ['Darling', 'Nywele za kusuka. / Braiding hair.'],
        ['X-pression', 'Nywele za kusuka (kanekalon). / Braiding hair (kanekalon).'],
        ['Janet Collection', 'Wigi na nywele za kuongeza. / Wigs and hair extensions.'],
        ['Freetress', 'Wigi na nywele za kuongeza. / Wigs and hair extensions.'],
        ['Sensationnel', 'Wigi na nywele za kuongeza. / Wigs and hair extensions.'],
        ['Outre', 'Wigi na nywele za kuongeza. / Wigs and hair extensions.'],
        ['Mielle Organics', 'Bidhaa za kutunza nywele. / Hair care products.'],
        ['Cantu', 'Bidhaa za kutunza nywele. / Hair care products.'],
    ];

    /** Adds the starting categories and brands to the salon in this request, once. Returns whether it added them now. */
    public static function ensureSeeded(?string $createdBy = null): bool
    {
        if (TenantContext::service() !== 'salon' || !Schema::hasTable('inventory_settings')) {
            return false;
        }
        if (DB::table('inventory_settings')->where('key', self::FLAG)->exists()) {
            return false;
        }

        $now = now();
        $haveCategories = DB::table('inventory_categories')->pluck('name')->map(fn ($n) => mb_strtolower((string) $n))->all();
        foreach (SalonSetupController::PRESETS as [$name, $about]) {
            if (!in_array(mb_strtolower($name), $haveCategories, true)) {
                DB::table('inventory_categories')->insert(['name' => $name, 'description' => $about, 'status' => 'active', 'created_by' => $createdBy, 'created_at' => $now, 'updated_at' => $now]);
            }
        }
        $haveBrands = DB::table('inventory_brands')->pluck('name')->map(fn ($n) => mb_strtolower((string) $n))->all();
        foreach (self::BRANDS as [$name, $about]) {
            if (!in_array(mb_strtolower($name), $haveBrands, true)) {
                DB::table('inventory_brands')->insert(['name' => $name, 'description' => $about, 'status' => 'active', 'created_by' => $createdBy, 'created_at' => $now, 'updated_at' => $now]);
            }
        }
        DB::table('inventory_settings')->updateOrInsert(['key' => self::FLAG], ['value' => '1', 'updated_at' => $now]);

        return true;
    }
}
