<?php

namespace App\Support;

use App\Models\Business;
use App\Models\User;
use App\Support\Tenancy\TenantContext;
use App\Support\Tenancy\TenantTables;
use Illuminate\Support\Facades\DB;

/**
 * Reference data every depot starts with. The original inventory migration seeds
 * these rows; they live here too so the settings endpoints can fall back to them
 * (and re-create a missing key) instead of failing on an empty table.
 */
final class InventoryDefaults
{
    /** Crate types every depot starts with: name => deposit value. */
    public const CRATE_TYPES = [
        'Crate' => 2000,
        'Empty bottle' => 100,
    ];

    /**
     * Give a business the reference data a depot needs from its first sale: the
     * settings and the default crate types (without a crate type a sale cannot
     * record crates owed). Only adds what is missing, so calling it again -- or for
     * the existing depot -- changes nothing.
     */
    public static function seedFor(User $owner, string $service = 'inventory'): void
    {
        TenantContext::runAs($owner, fn () => TenantContext::runInService($service, fn () => self::seedHere($service, $owner)));
    }

    /** [seedFor] for the service the context is already working in. */
    private static function seedHere(string $service, User $owner): void
    {
        // A new depot's receipts say who it really is, not the platform's placeholder.
        $defaults = self::defaultsFor($owner);

        (function () use ($defaults, $service) {
            foreach ($defaults as $key => $value) {
                if (!DB::table('inventory_settings')->where('key', $key)->exists()) {
                    DB::table('inventory_settings')->insert([
                        'key' => $key,
                        'value' => $value,
                        'updated_at' => now(),
                    ]);
                }
            }

            // A salon has no returnable crates.
            foreach ($service === 'salon' ? [] : self::CRATE_TYPES as $name => $deposit) {
                if (!DB::table('inventory_crate_types')->where('name', $name)->exists()) {
                    DB::table('inventory_crate_types')->insert([
                        'name' => $name,
                        'deposit_value' => $deposit,
                        'status' => 'active',
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            }
        })();
    }

    /**
     * The settings a business starts with: the platform defaults, with the business's own name,
     * contact, address and TIN where it has them. Without a business (a super admin) it is just
     * the platform defaults.
     *
     * @return array<string, string>
     */
    public static function defaultsFor(?User $user): array
    {
        $business = Business::forUser($user);
        if ($business === null) {
            // No business of its own (a super admin): the plain retail setup, not a depot's crates.
            return array_merge(self::SETTINGS, self::presetFor('retail'));
        }

        // The salon's books are a retail business's, whatever kind the shop beside them is.
        $fromBusiness = self::presetFor(TenantContext::service() === 'salon' ? 'retail' : $business->inventory_type);
        foreach (self::BUSINESS_FIELDS as $key => $field) {
            $value = trim((string) $business->{$field});
            if ($value !== '') {
                $fromBusiness[$key] = $value;
            }
        }

        return array_merge(self::SETTINGS, $fromBusiness);
    }

    /**
     * The settings a kind of inventory business starts with, beyond the platform defaults (which are the
     * depot's). An unknown or empty kind is a depot: that is what inventory was before kinds existed.
     *
     * @return array<string, string>
     */
    public static function presetFor(?string $type): array
    {
        return (array) config('inventory_types.presets.' . ($type ?: 'depot'), []);
    }

    /**
     * The owner changed what kind of business this is. Move the settings that still hold the OLD kind's
     * starting value to the NEW kind's, and leave anything the owner set themselves alone -- the same
     * rule as syncFromBusiness(). Nothing but settings changes; stock, prices and sales are untouched.
     */
    public static function applyType(Business $business, ?string $oldType): void
    {
        $owner = User::query()->find($business->owner_id);
        if ($owner === null || ($oldType ?: 'depot') === ($business->inventory_type ?: 'depot')) {
            return;
        }

        $old = array_merge(self::SETTINGS, self::presetFor($oldType));
        $new = array_merge(self::SETTINGS, self::presetFor($business->inventory_type));

        TenantContext::runAs($owner, function () use ($old, $new) {
            foreach (array_keys(self::presetKeys()) as $key) {
                $current = DB::table('inventory_settings')->where('key', $key)->value('value');
                if ($current === null || $current !== (string) $old[$key] || $old[$key] === $new[$key]) {
                    continue; // not a depot of ours, customised by the owner, or nothing to change
                }

                DB::table('inventory_settings')->where('key', $key)->update(['value' => $new[$key], 'updated_at' => now()]);
            }
        });
    }

    /** Every setting a kind of business can preset (the keys of config/inventory_types.php presets). */
    private static function presetKeys(): array
    {
        $keys = [];
        foreach ((array) config('inventory_types.presets', []) as $preset) {
            $keys += array_fill_keys(array_keys((array) $preset), true);
        }

        return $keys;
    }
    /**
     * The owner changed the business's details: carry them onto the depot's receipt settings, but
     * only where the depot is still saying what the business used to say (or the platform
     * default, or nothing). A value the owner typed into the depot settings on purpose is theirs
     * and is never overwritten, and a cleared field never blanks a name that is already printed.
     *
     * @param  array<string, mixed>  $before  the business's profile fields before the change
     */
    public static function syncFromBusiness(Business $business, array $before): void
    {
        $owner = User::query()->find($business->owner_id);
        if ($owner === null) {
            return;
        }

        foreach (TenantTables::SERVICES as $service) {
        TenantContext::runAs($owner, fn () => TenantContext::runInService($service, function () use ($business, $before) {
            foreach (self::BUSINESS_FIELDS as $key => $field) {
                $current = DB::table('inventory_settings')->where('key', $key)->value('value');
                if ($current === null) {
                    continue; // this business has no depot settings (it does not use inventory)
                }

                $new = trim((string) $business->{$field});
                $old = trim((string) ($before[$field] ?? ''));
                $untouched = $current === '' || $current === $old || $current === (self::SETTINGS[$key] ?? '');

                if ($new !== '' && $untouched && $current !== $new) {
                    DB::table('inventory_settings')->where('key', $key)->update(['value' => $new, 'updated_at' => now()]);
                }
            }
        }));
        }
    }

    /**
     * Settings that came after the 2026_10_08 restore migration. They are never seeded by a migration: a
     * business that has no row reads the default here, and seedFor() writes them for a new business.
     */
    public const READ_TIME_DEFAULTS = ['use_crates', 'sale_tier', 'prices_include_vat', 'hidden_reports'];

    /** Depot setting => the business field it mirrors. */
    private const BUSINESS_FIELDS = [
        'depot_name' => 'name',
        'depot_phone' => 'phone',
        'depot_address' => 'address',
        'receipt_tin' => 'tin',
        'receipt_email' => 'email',
    ];

    /** Depot settings: key => default value (stored as strings). */
    public const SETTINGS = [
        // Returnable packaging (crates and empties) and which price the till uses. The defaults are the
        // depot's, so a business that predates them behaves exactly as before; see config/inventory_types.php.
        'use_crates' => '1',
        'sale_tier' => 'product',
        // Do the prices already include VAT? (Only matters for products that carry a VAT rate.)
        'prices_include_vat' => '1',
        // Reports this business does not want in its Reports list (comma-separated report keys, e.g. "stock_valuation,purchases").
        'hidden_reports' => '',
        // No made-up name: a business shows its own (BUSINESS_FIELDS fills it from the business record).
        'depot_name' => '',
        'depot_phone' => '',
        'depot_address' => '',
        'invoice_prefix' => 'INV',
        'invoice_next_number' => '1',
        'tax_percent' => '0',
        'max_discount_percent' => '10',
        'low_stock_threshold' => '5',
        'expiry_alert_days' => '30',
        'overdue_alert_days' => '7',
        'large_discount_percent' => '15',
        'receipt_tagline' => '',
        'receipt_tin' => '',
        'receipt_email' => '',
        'receipt_website' => '',
        'receipt_footer_note' => 'Bidhaa zilizouzwa haziruhusiwi kurudishwa bila risiti.',
        'receipt_show_barcode' => '1',
        'receipt_show_tin' => '1',
        'receipt_copies' => '1',
    ];
}
