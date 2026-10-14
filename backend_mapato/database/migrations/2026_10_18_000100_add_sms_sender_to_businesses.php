<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Each business can send its customers' text messages under its own registered sender name.
     *
     *   sms_sender_id          the name a customer's phone shows (up to 11 letters/digits, registered with the SMS provider)
     *   sms_sender_status      none | pending | approved | rejected -- only `approved` is ever used to send
     *   sms_display_name       the (shorter) business name written inside the text; empty = the business name
     *   sms_sender_note        why it was rejected, or a note for the super admin
     *   sms_sender_requested_at / sms_sender_approved_at
     *   sms_api_key / sms_api_secret   the business's OWN account with the SMS provider, when it has one (stored
     *                          encrypted, never sent back to any app); empty = the platform's account
     *   sms_fallback_platform  if the business's own name/account is refused, may the text go out through the
     *                          platform's account instead? (it uses the platform's SMS credit)
     *
     * and what was sent under it, so a super admin can see a name that stopped working:
     *
     *   sms_sent_count         business texts the provider accepted (under any sender)
     *   sms_own_count          ... of which under the business's own sender name
     *   sms_fallback_count     ... of which the provider refused the sender name and the text went out under the platform name
     *   sms_last_sent_at, sms_last_error
     *
     * The sender name is unique across businesses (a name belongs to one business). MySQL/MariaDB compare it
     * without regard to case; the application checks that too, for every database.
     *
     * Re-runnable: MySQL has no transactional DDL, so a half-applied run must not break the next one.
     */
    public function up(): void
    {
        Schema::table('businesses', function (Blueprint $table) {
            if (!Schema::hasColumn('businesses', 'sms_sender_id')) {
                $table->string('sms_sender_id', 11)->nullable();
            }
            if (!Schema::hasColumn('businesses', 'sms_sender_status')) {
                $table->string('sms_sender_status', 12)->default('none');
            }
            if (!Schema::hasColumn('businesses', 'sms_display_name')) {
                $table->string('sms_display_name', 40)->nullable();
            }
            if (!Schema::hasColumn('businesses', 'sms_sender_note')) {
                $table->string('sms_sender_note', 255)->nullable();
            }
            if (!Schema::hasColumn('businesses', 'sms_sender_requested_at')) {
                $table->dateTime('sms_sender_requested_at')->nullable();
            }
            if (!Schema::hasColumn('businesses', 'sms_sender_approved_at')) {
                $table->dateTime('sms_sender_approved_at')->nullable();
            }
            if (!Schema::hasColumn('businesses', 'sms_api_key')) {
                $table->text('sms_api_key')->nullable();
            }
            if (!Schema::hasColumn('businesses', 'sms_api_secret')) {
                $table->text('sms_api_secret')->nullable();
            }
            if (!Schema::hasColumn('businesses', 'sms_fallback_platform')) {
                $table->boolean('sms_fallback_platform')->default(true);
            }
            if (!Schema::hasColumn('businesses', 'sms_sent_count')) {
                $table->unsignedInteger('sms_sent_count')->default(0);
            }
            if (!Schema::hasColumn('businesses', 'sms_own_count')) {
                $table->unsignedInteger('sms_own_count')->default(0);
            }
            if (!Schema::hasColumn('businesses', 'sms_fallback_count')) {
                $table->unsignedInteger('sms_fallback_count')->default(0);
            }
            if (!Schema::hasColumn('businesses', 'sms_last_sent_at')) {
                $table->dateTime('sms_last_sent_at')->nullable();
            }
            if (!Schema::hasColumn('businesses', 'sms_last_error')) {
                $table->string('sms_last_error', 500)->nullable();
            }
        });

        if (!$this->hasIndex('businesses_sms_sender_id_unique')) {
            Schema::table('businesses', function (Blueprint $table) {
                $table->unique('sms_sender_id', 'businesses_sms_sender_id_unique');
            });
        }
    }

    public function down(): void
    {
        if ($this->hasIndex('businesses_sms_sender_id_unique')) {
            Schema::table('businesses', function (Blueprint $table) {
                $table->dropUnique('businesses_sms_sender_id_unique');
            });
        }

        $columns = array_values(array_filter([
            'sms_sender_id', 'sms_sender_status', 'sms_display_name', 'sms_sender_note', 'sms_sender_requested_at',
            'sms_sender_approved_at', 'sms_api_key', 'sms_api_secret', 'sms_fallback_platform', 'sms_sent_count', 'sms_own_count', 'sms_fallback_count', 'sms_last_sent_at', 'sms_last_error',
        ], fn (string $c) => Schema::hasColumn('businesses', $c)));

        if ($columns !== []) {
            Schema::table('businesses', function (Blueprint $table) use ($columns) {
                $table->dropColumn($columns);
            });
        }
    }

    private function hasIndex(string $name): bool
    {
        foreach (Schema::getIndexes('businesses') as $index) {
            if (($index['name'] ?? null) === $name) {
                return true;
            }
        }

        return false;
    }
};
