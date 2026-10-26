<?php

namespace Tests\Feature;

use App\Support\Ai\GeminiClient;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/** When a Gemini model runs out of quota, is overloaded or is gone, the next model in the chain answers; a wrong request does not hop. */
class GeminiFallbackTest extends TestCase
{
    private function ok(string $text = 'fine'): \GuzzleHttp\Promise\PromiseInterface
    {
        return Http::response(['candidates' => [['content' => ['parts' => [['text' => $text]]]]]], 200);
    }

    private function body(): array
    {
        return ['contents' => [['role' => 'user', 'parts' => [['text' => 'hi']]]], 'generationConfig' => ['maxOutputTokens' => 50]];
    }

    /** @return array<int, string> the model of each request sent, in order */
    private function modelsTried(): array
    {
        return Http::recorded()->map(fn ($pair) => preg_replace('#.*/models/([^:]+):.*#', '$1', $pair[0]->url()))->values()->all();
    }

    protected function setUp(): void
    {
        parent::setUp();
        config(['services.gemini.key' => 'g-test', 'services.gemini.model' => 'm-primary', 'services.gemini.models' => 'm-second,gemini-2.0-flash']);
    }

    public function test_the_chain_is_the_primary_then_the_listed_fallbacks_without_repeats_and_has_a_built_in_default(): void
    {
        $this->assertSame(['m-primary', 'm-second', 'gemini-2.0-flash'], GeminiClient::chain());

        config(['services.gemini.models' => 'm-primary, m-second']);
        $this->assertSame(['m-primary', 'm-second'], GeminiClient::chain());

        config(['services.gemini.models' => '']);
        $this->assertSame('m-primary', GeminiClient::chain()[0]);
        $this->assertContains('gemini-3.5-flash-lite', GeminiClient::chain(), 'blank means the built-in list');
    }

    public function test_when_the_quota_is_used_up_the_next_model_answers_and_the_spent_one_is_skipped_afterwards(): void
    {
        Http::fake([
            '*models/m-primary:*' => Http::response(['error' => ['message' => 'quota']], 429),
            '*models/m-second:*' => $this->ok('from second'),
        ]);

        $first = GeminiClient::generate($this->body());
        $this->assertSame('from second', $first['candidates'][0]['content']['parts'][0]['text']);
        $this->assertSame(['m-primary', 'm-second'], $this->modelsTried());

        GeminiClient::generate($this->body());
        $this->assertSame(['m-primary', 'm-second', 'm-second'], $this->modelsTried(), 'the spent model is not asked again for a while');
    }

    public function test_an_overloaded_or_retired_model_also_hands_over(): void
    {
        Http::fake([
            '*models/m-primary:*' => Http::response('busy', 503),
            '*models/m-second:*' => Http::response('gone', 404),
            '*models/gemini-2.0-flash:*' => $this->ok('third'),
        ]);

        $r = GeminiClient::generate($this->body());

        $this->assertSame('third', $r['candidates'][0]['content']['parts'][0]['text']);
        $this->assertSame(['m-primary', 'm-second', 'gemini-2.0-flash'], $this->modelsTried());
    }

    public function test_a_wrong_request_or_key_stops_at_once_instead_of_trying_every_model(): void
    {
        Http::fake(['*' => Http::response(['error' => 'API key not valid'], 400)]);

        try {
            GeminiClient::generate($this->body());
            $this->fail('should have thrown');
        } catch (\RuntimeException $e) {
            $this->assertSame('AI answered 400', $e->getMessage());
        }
        $this->assertSame(['m-primary'], $this->modelsTried());
    }

    public function test_when_every_model_is_down_it_reports_failure_and_next_time_tries_them_all_again(): void
    {
        Http::fake(['*' => Http::response('busy', 503)]);

        foreach ([1, 2] as $round) {
            try {
                GeminiClient::generate($this->body());
                $this->fail('should have thrown');
            } catch (\RuntimeException $e) {
                $this->assertSame('AI answered 503', $e->getMessage());
            }
        }

        $this->assertCount(6, $this->modelsTried(), 'two full passes over three models: nothing stays stuck as "down"');
    }

    public function test_thinking_is_switched_off_only_where_the_model_accepts_it(): void
    {
        config(['services.gemini.model' => 'gemini-2.5-flash', 'services.gemini.models' => 'gemini-2.0-flash']);
        Http::fake([
            '*models/gemini-2.5-flash:*' => Http::response('busy', 503),
            '*models/gemini-2.0-flash:*' => $this->ok(),
        ]);

        GeminiClient::generate($this->body());

        $sent = Http::recorded()->map(fn ($pair) => $pair[0]->data())->values()->all();
        $this->assertSame(0, $sent[0]['generationConfig']['thinkingConfig']['thinkingBudget']);
        $this->assertArrayNotHasKey('thinkingConfig', $sent[1]['generationConfig'], 'the 2.0 models reject the field');
    }

    public function test_the_key_goes_in_a_header_and_never_in_the_url(): void
    {
        Http::fake(['*' => $this->ok()]);

        GeminiClient::generate($this->body());

        Http::assertSent(fn ($req) => $req->hasHeader('x-goog-api-key', 'g-test') && !str_contains($req->url(), 'g-test'));
    }
}
