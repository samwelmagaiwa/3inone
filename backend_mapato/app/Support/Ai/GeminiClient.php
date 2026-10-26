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
    /**
     * Models tried in order after the primary one: the fast Flash-Lite models first (they answer in 1-2 seconds), then the full Flash ones.
     * Google retires models for new keys without warning (the 2.x models already answer 404), so check this list against
     * GET /v1beta/models now and then. Override with GEMINI_MODELS.
     */
    public const DEFAULT_CHAIN = ['gemini-3.5-flash-lite', 'gemini-3.1-flash-lite', 'gemini-flash-lite-latest', 'gemini-3.5-flash', 'gemini-3.8-flash', 'gemini-flash-latest', 'gemini-3.7-flash', 'gemini-3.6-flash'];

    /** One model gets this long to answer; Gemini's speed varies from 2 to 40 seconds, and a slow one is not worth waiting for. */
    private const SECONDS_PER_MODEL = 14;

    /** All models together get this long, so a person gets an answer or a clear message BEFORE the web server's 60-second limit (a 504). */
    private const SECONDS_IN_ALL = 42;

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
        $started = microtime(true);
        foreach ($order as $model) {
            $left = self::SECONDS_IN_ALL - (microtime(true) - $started);
            if ($left < 4) {
                $last = 'AI is too slow now';
                break;
            }
            try {
                $res = Http::withHeaders(['x-goog-api-key' => trim((string) config('services.gemini.key'))]) // a header, never the URL
                    ->connectTimeout(5)->timeout((int) max(4, min(self::SECONDS_PER_MODEL, $left)))->acceptJson()
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
