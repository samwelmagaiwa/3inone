<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Groups (Vikundi): the payment methods the group authorises (bank, M-Pesa, Mixx by Yas, HaloPesa, Airtel Money, cash), each with the number or
 * account members pay to. Until the Mwenyekiti has chosen at least one, every method is accepted as before; once chosen, only those are.
 * Additive only; the table carries owner_id and is in TenantTables::GROUPS.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('group_payment_methods')) {
            Schema::create('group_payment_methods', function (Blueprint $table) {
                $table->id();
                $table->uuid('owner_id')->index();
                $table->string('method', 16); // bank_transfer | mpesa | mixx | halopesa | airtel_money | cash
                $table->string('number', 40)->nullable(); // the phone or lipa number, or the bank account number
                $table->string('account_name', 100)->nullable(); // who the money goes to, as it shows when paying
                $table->string('bank_name', 80)->nullable(); // bank only
                $table->unsignedTinyInteger('sort')->default(0);
                $table->uuid('updated_by')->nullable();
                $table->timestamps();
                $table->unique(['owner_id', 'method']);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('group_payment_methods');
    }
};
