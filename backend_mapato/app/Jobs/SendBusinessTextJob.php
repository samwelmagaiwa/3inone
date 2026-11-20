<?php

namespace App\Jobs;

use App\Models\User;
use App\Support\Inventory\ShopTexts;
use App\Support\Salon\SalonFeedback;
use App\Support\Tenancy\TenantContext;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;

/**
 * A text a business sends because of something done at the till (the receipt, the thank-you for a debt paid, the salon's "how was your
 * visit?"), sent by the queue worker instead of inside the request.
 *
 * Sending waits for the SMS provider (up to its timeout). Done inside the request it held one of the server's few PHP workers for that
 * long, so a slow provider on a busy morning could stall the whole app for everyone. Now the sale answers at once and the text follows a
 * moment later. Nothing about the text changes: it runs as the same person, in the same service, through the same code.
 *
 * Tried once only: the provider may already have taken a text when something fails after it, and a customer must never get it twice.
 */
class SendBusinessTextJob implements ShouldQueue
{
    use Queueable;

    public int $tries = 1;

    public const RECEIPT = 'receipt';

    public const DEBT_THANKS = 'debt_thanks';

    public const SALON_FEEDBACK = 'salon_feedback';

    /** @param  array<int, int|float|string>  $args */
    public function __construct(
        public string $kind,
        public string $actorId,
        public ?string $service,
        public array $args,
    ) {
    }

    /**
     * Queue a text for the business of the person acting now. Never throws: a text must never break the sale or the payment.
     *
     * @param  array<int, int|float|string>  $args
     */
    public static function later(string $kind, array $args): void
    {
        try {
            $actor = TenantContext::viewer();
            if ($actor === null) {
                return;
            }
            self::dispatch($kind, (string) $actor->id, TenantContext::service(), $args);
        } catch (\Throwable $e) {
            Log::warning("A business text could not be queued ({$kind}): " . $e->getMessage());
        }
    }

    public function handle(): void
    {
        $actor = User::query()->withoutGlobalScopes()->find($this->actorId);
        if ($actor === null) {
            return;
        }

        $send = function (): void {
            match ($this->kind) {
                self::RECEIPT => ShopTexts::afterSale((int) $this->args[0]),
                self::DEBT_THANKS => ShopTexts::afterDebtPayment((int) $this->args[0], (float) $this->args[1]),
                self::SALON_FEEDBACK => SalonFeedback::afterPaid((int) $this->args[0]),
                default => Log::warning("Unknown business text: {$this->kind}"),
            };
        };

        TenantContext::runAs($actor, fn () => $this->service !== null ? TenantContext::runInService($this->service, $send) : $send());
    }
}
