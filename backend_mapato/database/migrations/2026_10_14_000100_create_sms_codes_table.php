<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * One-time codes sent by SMS (password reset, phone check at registration).
     * Only a keyed hash of the code is stored, never the code itself. A new table: nothing
     * existing is changed or removed.
     */
    public function up(): void
    {
        if (Schema::hasTable('sms_codes')) {
            return;
        }

        Schema::create('sms_codes', function (Blueprint $table) {
            $table->id();
            $table->uuid('user_id');
            $table->string('purpose', 32);
            $table->string('code_hash', 64);
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->timestamp('expires_at');
            $table->timestamp('consumed_at')->nullable();
            $table->timestamps();

            $table->index(['user_id', 'purpose']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sms_codes');
    }
};
