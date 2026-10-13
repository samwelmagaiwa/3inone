<?php

namespace Tests\Support;

use App\Services\Sms\SmsGateway;

/**
 * Stands in for the SMS provider in tests: nothing leaves the process, and every message
 * is kept so a test can read what a person would have received (a code, a receipt).
 */
class FakeSmsGateway implements SmsGateway
{
    /** @var array<int, array{to: string, message: string, sensitive: bool}> */
    public array $sent = [];

    public bool $delivering = true;

    private ?\Throwable $failure = null;

    private bool $refuse = false;

    public function delivers(): bool
    {
        return $this->delivering;
    }

    public function send(string $to, string $message, bool $sensitive = false): bool
    {
        if ($this->failure !== null) {
            throw $this->failure;
        }
        if ($this->refuse) {
            return false;
        }

        $this->sent[] = ['to' => $to, 'message' => $message, 'sensitive' => $sensitive];

        return true;
    }

    /** Make every later send throw, like a provider that is down. */
    public function failWith(\Throwable $e): void
    {
        $this->failure = $e;
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
