<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * What makes a client come back: loyalty points, vouchers and prepaid packages, and deposits on bookings. Each step
     * checks first (MySQL has no transactional DDL); the new tables carry their own `service` column.
     */
    public function up(): void
    {
        if (Schema::hasTable('inventory_products')) {
            Schema::table('inventory_products', function (Blueprint $table) {
                // A package is a service that, when sold, gives the client N visits of another service.
                if (!Schema::hasColumn('inventory_products', 'package_sessions')) {
                    $table->unsignedSmallInteger('package_sessions')->nullable();
                }
                if (!Schema::hasColumn('inventory_products', 'package_service_id')) {
                    $table->unsignedBigInteger('package_service_id')->nullable();
                }
                if (!Schema::hasColumn('inventory_products', 'package_valid_days')) {
                    $table->unsignedSmallInteger('package_valid_days')->nullable();
                }
            });
        }

        if (Schema::hasTable('inventory_sales')) {
            Schema::table('inventory_sales', function (Blueprint $table) {
                if (!Schema::hasColumn('inventory_sales', 'voucher_code')) {
                    $table->string('voucher_code', 40)->nullable();
                }
                if (!Schema::hasColumn('inventory_sales', 'points_earned')) {
                    $table->unsignedInteger('points_earned')->default(0);
                }
                if (!Schema::hasColumn('inventory_sales', 'points_redeemed')) {
                    $table->unsignedInteger('points_redeemed')->default(0);
                }
            });
        }

        if (Schema::hasTable('inventory_sale_items') && !Schema::hasColumn('inventory_sale_items', 'package_id')) {
            Schema::table('inventory_sale_items', function (Blueprint $table) {
                // A line that used up a session of a client's package (it is free: the package was paid for).
                $table->unsignedBigInteger('package_id')->nullable()->index();
            });
        }

        if (Schema::hasTable('inventory_appointments')) {
            Schema::table('inventory_appointments', function (Blueprint $table) {
                if (!Schema::hasColumn('inventory_appointments', 'deposit_amount')) {
                    $table->decimal('deposit_amount', 14, 2)->default(0);
                }
                if (!Schema::hasColumn('inventory_appointments', 'deposit_method')) {
                    $table->string('deposit_method', 30)->nullable();
                }
                if (!Schema::hasColumn('inventory_appointments', 'deposit_status')) {
                    // none | held | applied (put into the sale) | forfeited (kept by the salon) | refunded (given back)
                    $table->string('deposit_status', 12)->default('none');
                }
                if (!Schema::hasColumn('inventory_appointments', 'deposit_resolved_at')) {
                    $table->timestamp('deposit_resolved_at')->nullable();
                }
            });
        }

        if (!Schema::hasTable('inventory_loyalty_ledger')) {
            Schema::create('inventory_loyalty_ledger', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('customer_id')->index();
                // Positive = earned, negative = spent or taken back.
                $table->integer('points');
                // earn | redeem | reverse | referral | adjust
                $table->string('kind', 12);
                $table->unsignedBigInteger('sale_id')->nullable()->index();
                $table->string('note', 160)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('inventory_vouchers')) {
            Schema::create('inventory_vouchers', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->string('code', 40);
                // percent | amount
                $table->string('kind', 8);
                $table->decimal('value', 14, 2);
                $table->date('expires_on')->nullable();
                $table->unsignedInteger('max_uses')->nullable();
                $table->unsignedInteger('used_count')->default(0);
                $table->boolean('active')->default(true);
                $table->string('note', 160)->nullable();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'service', 'code'], 'one_voucher_code_per_business');
            });
        }

        if (!Schema::hasTable('inventory_client_packages')) {
            Schema::create('inventory_client_packages', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->nullable()->index();
                $table->string('service', 20)->default('salon')->index();
                $table->unsignedBigInteger('customer_id')->index();
                // The package that was sold and the service its visits are for.
                $table->unsignedBigInteger('product_id');
                $table->unsignedBigInteger('service_product_id');
                $table->string('name', 160);
                $table->unsignedSmallInteger('sessions_total');
                $table->unsignedSmallInteger('sessions_left');
                $table->date('expires_on')->nullable();
                // active | used | cancelled
                $table->string('status', 10)->default('active')->index();
                $table->unsignedBigInteger('sale_id')->nullable()->index();
                $table->uuid('created_by')->nullable();
                $table->timestamps();
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_client_packages');
        Schema::dropIfExists('inventory_vouchers');
        Schema::dropIfExists('inventory_loyalty_ledger');

        $drop = function (string $table, array $columns, ?string $index = null): void {
            if (!Schema::hasTable($table)) {
                return;
            }
            foreach ($columns as $column) {
                if (Schema::hasColumn($table, $column)) {
                    if ($index !== null && $column === 'package_id') {
                        Schema::table($table, fn (Blueprint $t) => $t->dropIndex([$column]));
                    }
                    Schema::table($table, fn (Blueprint $t) => $t->dropColumn($column));
                }
            }
        };
        $drop('inventory_appointments', ['deposit_amount', 'deposit_method', 'deposit_status', 'deposit_resolved_at']);
        $drop('inventory_sale_items', ['package_id'], 'package_id');
        $drop('inventory_sales', ['voucher_code', 'points_earned', 'points_redeemed']);
        $drop('inventory_products', ['package_sessions', 'package_service_id', 'package_valid_days']);
    }
};
