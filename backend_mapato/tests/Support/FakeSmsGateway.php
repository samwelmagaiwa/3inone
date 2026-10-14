<?php

namespace Tests\Support;

use App\Services\Sms\SmsGateway;

/**
 * Stands in for the SMS provider in tests: nothing leaves the process, and every message
 * is kept so a test can read what a person would have received (a code, a receipt).
 */
class FakeSmsGateway implements SmsGateway
{
    /** @var array<int, array{to: string, message: string, sensitive: bool, sender: ?string, credentials: ?array}> */
    public array $sent = [];

    /** Every send attempt, accepted or not: [to, sender, accepted]. */
    public array $attempts = [];

    public bool $delivering = true;

    private ?\Throwable $failure = null;

    private bool $refuse = false;

    private bool $lastRefused = false;

    private bool $silent = false;

    /** @var array<int, string> sender names the "provider" does not know (compared without regard to case) */
    private array $unknownSenders = [];

    /** @var array<int, string> API keys the "provider" rejects */
    private array $badKeys = [];

    public function delivers(): bool
    {
        return $this->delivering;
    }

    public function send(string $to, string $message, bool $sensitive = false, ?string $senderId = null, ?array $credentials = null): bool
    {
        $this->lastRefused = false;

        if ($this->failure !== null) {
            $this->attempts[] = ['to' => $to, 'sender' => $senderId, 'credentials' => $credentials, 'accepted' => false];
            throw $this->failure;
        }
        if ($this->silent) {
            // A timeout, like the real gateway reports it: false, and NOT a refusal (the message may still arrive).
            $this->attempts[] = ['to' => $to, 'sender' => $senderId, 'credentials' => $credentials, 'accepted' => false];

            return false;
        }
        $badKey = $credentials !== null && in_array((string) ($credentials['api_key'] ?? ''), $this->badKeys, true);
        if ($this->refuse || $badKey || ($senderId !== null && in_array(strtolower($senderId), $this->unknownSenders, true))) {
            $this->lastRefused = true;
            $this->attempts[] = ['to' => $to, 'sender' => $senderId, 'credentials' => $credentials, 'accepted' => false];

            return false;
        }

        $this->sent[] = ['to' => $to, 'message' => $message, 'sensitive' => $sensitive, 'sender' => $senderId, 'credentials' => $credentials];
        $this->attempts[] = ['to' => $to, 'sender' => $senderId, 'credentials' => $credentials, 'accepted' => true];

        return true;
    }

    public function lastSendWasRefused(): bool
    {
        return $this->lastRefused;
    }

    /** Make the provider reject these API keys (a wrong key, or an account with no credit left). */
    public function rejectKeys(string ...$keys): void
    {
        $this->badKeys = $keys;
    }

    /** Make the provider refuse these sender names (it was never told about them), like an unregistered name. */
    public function refuseSenders(string ...$names): void
    {
        $this->unknownSenders = array_map('strtolower', $names);
    }

    /** Make every later send throw, like a provider that is down. */
    public function failWith(\Throwable $e): void
    {
        $this->failure = $e;
    }

    /** Make every later send get no answer at all (a timeout): "not sent", but not a refusal. */
    public function noAnswer(): void
    {
        $this->silent = true;
    }

    /** Make every later send answer "not sent". */
    public function refuseAll(): void
    {
        $this->refuse = true;
    }

    /** Messages that went to this number (any way of writing it). */
    public function to(string $phone): array
    {
        $last9 = fn (string $n): string => substr(preg_replace('/\D/', '', $n) ?? '', -9);

        return array_values(array_filter($this->sent, fn (array $m) => $last9($m['to']) === $last9($phone)));
    }

    /** The 6-digit code in the latest message to this number, or null. */
    public function lastCodeFor(string $phone): ?string
    {
        $messages = $this->to($phone);
        for ($i = count($messages) - 1; $i >= 0; $i--) {
            if (preg_match('/\b(\d{6})\b/', $messages[$i]['message'], $m) === 1) {
                return $m[1];
            }
        }

        return null;
    }
}
