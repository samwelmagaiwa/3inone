<?php

namespace App\Support\Ai;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * The one door to Gemini. It holds a CHAIN of models and moves down it by itself, so when a model's quota (tokens or requests) runs out,
 * is overloaded or has been retired, the person still gets an answer from the next one instead of an error.
 *
 * Order: GEMINI_MODEL first, then each of GEMINI_MODELS (comma separated). A model that fails is remembered as "down" for a while
 * (quota: 10 minutes, overload: 1 minute, gone: 1 hour) so the following questions do not wait on it again. Only failures that are the
 * model's or the service's fault move on (429, 5xx, 404, no connection); a 400/401/403 would fail on every model and stops at once.
 */
final class GeminiClient
{
    /** Models tried in order after the primary one; cheapest-to-run last. Override with GEMINI_MODELS. */
    public const DEFAULT_CHAIN = ['gemini-2.5-flash', 'gemini-2.5-flash-lite', 'gemini-2.0-flash', 'gemini-2.0-flash-lite', 'gemini-2.5-pro'];

    /** @return array<int, string> */
    public static function chain(): array
    {
        $primary = trim((string) config('services.gemini.model', ''));
        $more = config('services.gemini.models');
        $more = is_array($more) ? $more : (is_string($more) && trim($more) !== '' ? explode(',', $more) : self::DEFAULT_CHAIN);

        return array_values(array_unique(array_filter(array_map('trim', array_merge([$primary], $more)))));
    }

    public static function available(): bool
    {
        return trim((string) config('services.gemini.key', '')) !== '';
    }

    /**
     * Ask Gemini, falling down the chain as needed.
     *
     * @param  array<string, mixed>  $body a generateContent body; the generation settings that only some models accept are adjusted per model
     * @return array<string, mixed>
     */
    public static function generate(array $body): array
    {
        $models = self::chain();
        // Models marked down are skipped, unless that would leave none: then everything is tried again.
        $live = array_values(array_filter($models, fn (string $m) => !Cache::has(self::downKey($m))));
        $order = $live === [] ? $models : $live;

        $last = 'no model configured';
        foreach ($order as $model) {
            try {
                $res = Http::withHeaders(['x-goog-api-key' => trim((string) config('services.gemini.key'))]) // a header, never the URL
                    ->connectTimeout(8)->timeout(35)->acceptJson()
                    ->post('https://generativelanguage.googleapis.com/v1beta/models/' . rawurlencode($model) . ':generateContent', self::forModel($body, $model));
            } catch (ConnectionException $e) {
                self::down($model, 60, 'no connection');
                $last = 'no connection';

                continue;
            }

            if ($res->successful()) {
                return (array) $res->json();
            }

            $status = $res->status();
            $last = 'AI answered ' . $status;
            if ($status === 429) {
                self::down($model, 600, 'quota used up');
            } elseif ($status === 404) {
                self::down($model, 3600, 'model not available');
            } elseif ($status >= 500) {
                self::down($model, 60, 'overloaded');
            } else {
                // 400/401/403: our request or the key is wrong, so every model would refuse it the same way.
                throw new \RuntimeException($last);
            }
        }

        throw new \RuntimeException($last);
    }

    /** Settings only some models take: switching thinking off works on 2.5 Flash models, and the 2.0 ones reject the field outright. */
    private static function forModel(array $body, string $model): array
    {
        $thinkingOff = str_contains($model, '2.5') && str_contains($model, 'flash');
        if ($thinkingOff) {
            $body['generationConfig']['thinkingConfig'] = ['thinkingBudget' => 0];
        } else {
            unset($body['generationConfig']['thinkingConfig']);
        }

        return $body;
    }

    private static function down(string $model, int $seconds, string $why): void
    {
        Cache::put(self::downKey($model), $why, now()->addSeconds($seconds));
        Log::warning('gemini model switched away from', ['model' => $model, 'why' => $why]);
    }

    private static function downKey(string $model): string
    {
        return 'gemini_down:' . $model;
    }
}
