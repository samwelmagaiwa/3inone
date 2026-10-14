<?php

namespace App\Services\Sms;

/**
 * Something that can put a text message on a phone.
 */
interface SmsGateway
{
    /**
     * True when a message sent now really leaves the server: a real provider that is
     * switched on and has its credentials. A logging stand-in answers false.
     */
    public function delivers(): bool;

    /**
     * Send one message. Never throws; false means it was not sent.
     *
     * @param  bool  $sensitive  the message carries a secret (a one-time code): it must
     *                           not be written to the logs in production
     * @param  ?string  $senderId  the sender name the phone should show; null = the platform's own
     * @param  ?array{api_key: string, api_secret: ?string}  $credentials  a business's own account with the
     *                           provider; null = the platform's. A missing secret falls back to the platform's.
     */
    public function send(string $to, string $message, bool $sensitive = false, ?string $senderId = null, ?array $credentials = null): bool;

    /**
     * Was the LAST send answered by the provider but not accepted (a refused sender name, a rejected number)?
     * False when it was accepted, or when there was no answer at all (a timeout: the message may have gone, so
     * it must not be sent again).
     */
    public function lastSendWasRefused(): bool;
}
