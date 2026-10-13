<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Selling in more than one unit, sizes/colours as separate stock, goods by weight or volume, and an
     * optional VAT rate per product. Additive only: every new column is nullable or has a default that
     * reproduces how things worked before, so existing rows and the depot behave exactly as they did.
     *
     * Stock stays a WHOLE number of the smallest unit. Weighed goods are stocked in grams / millilitres
     * and sold in grams, kilograms, millilitres or litres: a customer who wants 2.5 kg buys 2,500 g, so
     * no quantity anywhere is ever a fraction.
     *
     *   inventory_products
     *     tax_percent    this product's VAT rate; NULL = use the business's default (0 unless set)
     *     family_id      products that are sizes/colours of one thing share the id of the first one
     *     variant_label  "M / Red", "Size 42": what tells the variants apart
     *     measure        count | weight | volume (what the base unit counts)
     *
     *   inventory_sale_items   (`quantity` stays the number of BASE units: stock, cost and every report
     *                           keep working; these say how it was sold)
     *     unit_id / unit_name / unit_factor / unit_qty   the unit it was sold in, how many base units one
     *                           of it is, and how many were sold (NULL on old rows = sold in base units)
     *     tax_percent / tax_amount   the VAT on this line
     *
     *   inventory_sale_return_lines    the same unit snapshot, so a return of "1 kg" refunds 1 kg
     */
    public function up(): void
    {
        Schema::table('inventory_products', function (Blueprint $t) {
            $t->decimal('tax_percent', 5, 2)->nullable();
            $t->unsignedBigInteger('family_id')->nullable()->index();
            $t->string('variant_label', 100)->nullable();
            $t->string('measure', 10)->default('count');
        });

        Schema::table('inventory_sale_items', function (Blueprint $t) {
            $t->unsignedBigInteger('unit_id')->nullable();
            $t->string('unit_name', 32)->nullable();
            $t->unsignedInteger('unit_factor')->default(1);
            $t->unsignedInteger('unit_qty')->nullable();
            $t->decimal('tax_percent', 5, 2)->nullable();
            $t->decimal('tax_amount', 12, 2)->default(0);
        });

        Schema::table('inventory_sale_return_lines', function (Blueprint $t) {
            $t->unsignedBigInteger('unit_id')->nullable();
            $t->string('unit_name', 32)->nullable();
            $t->unsignedInteger('unit_qty')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('inventory_sale_return_lines', function (Blueprint $t) {
            $t->dropColumn(['unit_id', 'unit_name', 'unit_qty']);
        });

        Schema::table('inventory_sale_items', function (Blueprint $t) {
            $t->dropColumn(['unit_id', 'unit_name', 'unit_factor', 'unit_qty', 'tax_percent', 'tax_amount']);
        });

        Schema::table('inventory_products', function (Blueprint $t) {
            $t->dropIndex(['family_id']);
            $t->dropColumn(['tax_percent', 'family_id', 'variant_label', 'measure']);
        });
    }
};
