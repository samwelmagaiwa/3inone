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
     */
    public function send(string $to, string $message, bool $sensitive = false): bool;
}
