<?php

namespace App\Support;

use App\Models\Business;

/**
 * The rules for a business's SMS sender name (the name a customer's phone shows instead of a number).
 *
 * In Tanzania a sender name has to be registered with the SMS provider (and through it with the operators)
 * before it works, and it must not pass for somebody else. So a name is checked here before it is stored:
 *
 *   - 3 to 11 characters, letters and digits only, starting with a letter (so never just a number);
 *   - not a generic or look-alike name (INFO, NOTIFY, a bank, a mobile operator, the state ...) and not the
 *     platform's own name;
 *   - not used by another business (compared without regard to case).
 */
class SmsSenderName
{
    public const PATTERN = '/^[A-Za-z][A-Za-z0-9]{2,10}$/';

    /** Names nobody may take: generic words, operators, banks, mobile money, the state. Compared in upper case. */
    private const BLOCKED = [
        'INFO', 'INFOSMS', 'SMS', 'TEST', 'VERIFY', 'NOTIFY', 'ALERT', 'ALERTS', 'OTP', 'CODE', 'ADMIN', 'SUPPORT', 'HELP',
        'MESSAGE', 'NOTICE', 'SERVICE', 'BANK', 'MONEY', 'PAYMENT', 'PAY', 'LOAN', 'PROMO',
        'TRA', 'TCRA', 'NIDA', 'BRELA', 'POLICE', 'POLISI', 'SERIKALI', 'GOVT', 'GOVERNMENT', 'IKULU', 'BOT', 'TANESCO', 'DAWASA',
        'VODACOM', 'AIRTEL', 'TIGO', 'YAS', 'HALOTEL', 'TTCL', 'ZANTEL', 'MPESA', 'MYAS', 'TIGOPESA', 'AIRTELMONEY', 'HALOPESA', 'TPESA', 'AZAMPESA', 'SELCOM',
        'CRDB', 'NMB', 'NBC', 'EXIM', 'STANBIC', 'DTB', 'EQUITY', 'ABSA', 'AMANA', 'AZANIA', 'KCB', 'TPB',
        'WHATSAPP', 'FACEBOOK', 'GOOGLE', 'APPLE', 'MICROSOFT',
    ];

    /** Letters and digits only, in upper case, for comparing two names. */
    public static function key(string $name): string
    {
        return strtoupper((string) preg_replace('/[^A-Za-z0-9]/', '', $name));
    }

    /** Is the format right (3-11 letters/digits, starts with a letter)? */
    public static function validFormat(string $name): bool
    {
        return preg_match(self::PATTERN, $name) === 1;
    }

    /** A generic/look-alike name, or the platform's own. */
    public static function isReserved(string $name): bool
    {
        $key = self::key($name);

        if (in_array($key, self::BLOCKED, true)) {
            return true;
        }

        $platform = array_filter([
            self::key((string) config('sms.kilakona.sender_id', '')),
            self::key((string) config('app.name', '')),
            '3INONE', 'THREEINONE',
        ]);

        return in_array($key, $platform, true);
    }

    /** Does another business already hold this name? (Case does not matter.) */
    public static function takenByAnother(string $name, ?string $exceptBusinessId = null): bool
    {
        $query = Business::withoutAccountScope()->whereRaw('LOWER(sms_sender_id) = ?', [strtolower($name)]);

        if ($exceptBusinessId !== null) {
            $query->where('id', '!=', $exceptBusinessId);
        }

        return $query->exists();
    }

    /**
     * The first thing wrong with a name, as a message in both languages, or null when it can be used.
     */
    public static function problem(string $name, ?string $exceptBusinessId = null): ?string
    {
        if (!self::validFormat($name)) {
            return 'Jina la mtumaji lazima liwe na herufi 3 hadi 11 (herufi na tarakimu tu), likianza na herufi. / '
                . 'The sender name must be 3 to 11 letters or digits and start with a letter.';
        }
        if (self::isReserved($name)) {
            return 'Jina hili haliruhusiwi (ni la kawaida mno au linafanana na taasisi nyingine). Chagua jina la biashara yako. / '
                . 'This name is not allowed (too generic, or it looks like another organisation). Choose a name for your business.';
        }
        if (self::takenByAnother($name, $exceptBusinessId)) {
            return 'Jina hili tayari linatumiwa na biashara nyingine. / This sender name is already used by another business.';
        }

        return null;
    }
}
