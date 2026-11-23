<?php

namespace App\Support\Groups;

use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

/**
 * The values a group sets for itself. Nothing a group decides (fees, share amount, loan multiplier) is written into the code: each is a
 * setting, and each change is a new row with the day it starts, so the value that applied on any past day can still be read.
 */
final class GroupSettings
{
    /**
     * Each setting: its kind and its value until the group sets one.
     *   joining_fee           paid once to join (MEG: 80,000)
     *   share_amount          the project shares (MEG: 200,000)
     *   shares_required_for   none | loans | membership: what the shares must be paid for
     *   loan_multiplier       a member may borrow up to this times their eligible savings (MEG: 3)
     *   member_prefix         put before each member number ("MEG" gives MEG-0001)
     *   payment_instructions  how to pay: shown to members next to the payment form (M-Pesa number, bank account, ...)
     */
    public const KEYS = [
        'joining_fee' => ['type' => 'money', 'default' => '0'],
        'share_amount' => ['type' => 'money', 'default' => '0'],
        'shares_required_for' => ['type' => 'choice', 'choices' => ['none', 'loans', 'membership'], 'default' => 'loans'],
        'loan_multiplier' => ['type' => 'number', 'default' => '3'],
        'member_prefix' => ['type' => 'text', 'default' => 'M'],
        'payment_instructions' => ['type' => 'text', 'default' => ''],
        // Reminder texts to members (contribution due in 3 days, overdue, a promise's day). Off until the group switches them on: they use
        // the group's own SMS. Amounts are left out unless the group allows them (a shared phone should not show someone's debts).
        'sms_reminders' => ['type' => 'choice', 'choices' => ['off', 'on'], 'default' => 'off'],
        'sms_show_amounts' => ['type' => 'choice', 'choices' => ['off', 'on'], 'default' => 'off'],
        // Loan terms. The rate (percent PER MONTH) and the method have NO default: the group must decide them (nothing is assumed), and
        // nobody can apply for a loan until both are set. Each loan keeps the terms it was applied under.
        'loan_interest_rate' => ['type' => 'rate', 'default' => ''],
        'loan_interest_method' => ['type' => 'choice', 'choices' => ['', 'flat', 'reducing'], 'default' => ''],
        'loan_max_months' => ['type' => 'count', 'min' => 1, 'max' => 120, 'default' => '12'],
        'loan_guarantors' => ['type' => 'count', 'min' => 0, 'max' => 5, 'default' => '1'],
        // How often a loan is repaid: every day (from tomorrow), week, two weeks, month, two months, three months, six months, or every N days.
        // Each loan keeps the rhythm it was applied under.
        'loan_repayment' => ['type' => 'choice', 'choices' => ['daily', 'weekly', 'every_2_weeks', 'monthly', 'every_2_months', 'quarterly', 'every_6_months', 'custom'], 'default' => 'monthly'],
        'loan_repayment_days' => ['type' => 'count', 'min' => 1, 'max' => 365, 'default' => '30'],
        // Hiring out (chairs): are the collection day AND the return day both charged (both), or only the nights between (between)?
        'hire_days_rule' => ['type' => 'choice', 'choices' => ['both', 'between'], 'default' => 'both'],
    ];

    /** @return array<string, string> every setting as it stands on [day] (today when null) */
    public static function all(?string $day = null): array
    {
        $day ??= now()->toDateString();
        $rows = DB::table('group_settings')->where('effective_from', '<=', $day)
            ->orderBy('effective_from')->orderBy('id')->get(['key', 'value']);
        $values = [];
        foreach (self::KEYS as $key => $spec) {
            $values[$key] = $spec['default'];
        }
        foreach ($rows as $row) {
            if (array_key_exists($row->key, self::KEYS)) {
                $values[$row->key] = (string) $row->value;
            }
        }

        return $values;
    }

    public static function get(string $key, ?string $day = null): string
    {
        return self::all($day)[$key] ?? (string) (self::KEYS[$key]['default'] ?? '');
    }

    public static function money(string $key, ?string $day = null): float
    {
        return (float) self::get($key, $day);
    }

    /** Is [value] acceptable for [key]? Returns it cleaned, or throws with what is wrong. */
    public static function clean(string $key, mixed $value): string
    {
        $spec = self::KEYS[$key] ?? throw new InvalidArgumentException("Unknown setting {$key}.");
        $text = trim((string) $value);

        return match ($spec['type']) {
            'money' => is_numeric($text) && (float) $text >= 0 && (float) $text <= 1_000_000_000
                ? (string) round((float) $text, 2)
                : throw new InvalidArgumentException("{$key}: enter an amount of 0 or more."),
            'number' => is_numeric($text) && (float) $text > 0 && (float) $text <= 100
                ? (string) round((float) $text, 2)
                : throw new InvalidArgumentException("{$key}: enter a number above 0."),
            'choice' => in_array($text, $spec['choices'], true) ? $text : throw new InvalidArgumentException("{$key}: not one of the choices."),
            'rate' => $text === '' || (is_numeric($text) && (float) $text >= 0 && (float) $text <= 100)
                ? ($text === '' ? '' : (string) round((float) $text, 3))
                : throw new InvalidArgumentException("{$key}: a percentage from 0 to 100, or empty."),
            'count' => ctype_digit($text) && (int) $text >= $spec['min'] && (int) $text <= $spec['max']
                ? (string) (int) $text
                : throw new InvalidArgumentException("{$key}: a whole number from {$spec['min']} to {$spec['max']}."),
            'text' => $key === 'member_prefix'
                ? (preg_match('/^[A-Za-z0-9]{1,8}$/', $text) === 1 ? strtoupper($text) : throw new InvalidArgumentException('member_prefix: 1 to 8 letters or digits.'))
                : mb_substr($text, 0, 255),
        };
    }

    /**
     * Record new values from [day] on (today when null). Only values that differ from what applies on that day are written.
     *
     * @param  array<string, mixed>  $values
     * @return array<string, array{from: string, to: string}> what changed
     */
    public static function change(array $values, string $userId, ?string $reason, ?string $day = null): array
    {
        $day ??= now()->toDateString();
        $current = self::all($day);
        $changed = [];
        foreach ($values as $key => $value) {
            $clean = self::clean((string) $key, $value);
            if ($clean === $current[$key]) {
                continue;
            }
            DB::table('group_settings')->insert([
                'key' => $key, 'value' => $clean, 'effective_from' => $day,
                'changed_by' => $userId, 'reason' => $reason, 'created_at' => now(),
            ]);
            $changed[$key] = ['from' => $current[$key], 'to' => $clean];
        }

        return $changed;
    }

    /** @return array<int, array<string, mixed>> every change made, newest first */
    public static function history(int $limit = 100): array
    {
        return DB::table('group_settings as s')
            ->leftJoin('users as u', 'u.id', '=', 's.changed_by')
            ->orderByDesc('s.id')->limit($limit)
            ->get(['s.id', 's.key', 's.value', 's.effective_from', 's.reason', 's.created_at', 'u.name as changed_by_name'])
            ->map(fn ($r) => (array) $r)->all();
    }
}
