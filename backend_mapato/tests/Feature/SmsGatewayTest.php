<?php

namespace Tests\Feature;

use App\Services\Sms\KilakonaSmsGateway;
use App\Services\Sms\LogSmsGateway;
use App\Services\Sms\PhoneNumber;
use App\Services\Sms\SmsGateway;
use App\Services\SmsService;
use Illuminate\Http\Client\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

/**
 * The SMS provider layer. Http is faked throughout, so no test ever sends a real message
 * or needs the real credentials (those live in the server's environment only).
 */
class SmsGatewayTest extends TestCase
{
    private function configureKilakona(bool $enabled = true): void
    {
        config([
            'sms.enabled' => $enabled,
            'sms.country_code' => '255',
            'sms.kilakona.api_url' => 'https://sms.example.test/send',
            'sms.kilakona.api_key' => 'test-key',
            'sms.kilakona.secret_key' => 'test-secret',
            'sms.kilakona.sender_id' => 'TESTSENDER',
        ]);
    }

    // ----------------------------------------------------------- numbers

    public function test_phone_numbers_become_international_digits(): void
    {
        foreach (['0743519100', '+255743519100', '255743519100', '743519100', '0743 519 100', '00255743519100'] as $written) {
            $this->assertSame('255743519100', PhoneNumber::international($written), $written);
        }
        $this->assertSame('', PhoneNumber::international(''));
        $this->assertSame('', PhoneNumber::international('abc'));
        $this->assertSame('254712345678', PhoneNumber::international('+254712345678'), 'another country keeps its own code');
    }

    public function test_a_masked_number_is_recognisable_but_not_usable(): void
    {
        $this->assertSame('2557*****100', PhoneNumber::mask('255743519100'));
        $this->assertSame('***', PhoneNumber::mask('123'));
    }

    // ---------------------------------------------------------- Kilakona

    public function test_a_message_is_posted_to_kilakona_in_the_shape_it_expects(): void
    {
        $this->configureKilakona();
        Http::fake(['sms.example.test/*' => Http::response(['success' => true], 200)]);

        $sent = (new KilakonaSmsGateway())->send('0743519100', 'Habari yako');

        $this->assertTrue($sent);
        Http::assertSent(function (Request $request) {
            return $request->url() === 'https://sms.example.test/send'
                && $request->method() === 'POST'
                && $request->hasHeader('api-key', 'test-key')
                && $request->hasHeader('api_secret', 'test-secret')
                && $request['senderId'] === 'TESTSENDER'
                && $request['messageType'] === 'text'
                && $request['contacts'] === '255743519100'
                && $request['message'] === 'Habari yako';
        });
    }

    public function test_a_reply_counts_as_sent_only_when_kilakona_says_so(): void
    {
        $this->configureKilakona();

        // One fake, answering in turn (a second Http::fake for the same URL would not replace the first).
        Http::fake(['sms.example.test/*' => Http::sequence()
            ->push(['code' => 200], 200)
            ->push(['success' => false, 'message' => 'no credit'], 200)
            ->push('boom', 500)
            ->pushFailedConnection('timeout')]);

        $this->assertTrue((new KilakonaSmsGateway())->send('0743519100', 'x'), '{"code":200} is a success');
        $this->assertFalse((new KilakonaSmsGateway())->send('0743519100', 'x'), '{"success":false} is not');
        $this->assertFalse((new KilakonaSmsGateway())->send('0743519100', 'x'), 'a server error is not');
        $this->assertFalse((new KilakonaSmsGateway())->send('0743519100', 'x'), 'a network failure is reported, not thrown');
    }

    public function test_nothing_is_sent_when_sms_is_switched_off_or_has_no_credentials(): void
    {
        Http::fake();

        $this->configureKilakona(enabled: false);
        $this->assertFalse((new KilakonaSmsGateway())->delivers());
        $this->assertTrue((new KilakonaSmsGateway())->send('0743519100', 'hello'), 'it behaves like the log stand-in');

        $this->configureKilakona();
        config(['sms.kilakona.api_key' => '']);
        $this->assertFalse((new KilakonaSmsGateway())->delivers());
        (new KilakonaSmsGateway())->send('0743519100', 'hello');

        Http::assertNothingSent();
    }

    public function test_a_bad_number_is_not_sent_anywhere(): void
    {
        $this->configureKilakona();
        Http::fake();

        $this->assertFalse((new KilakonaSmsGateway())->send('not a number', 'x'));

        Http::assertNothingSent();
    }

    public function test_the_message_text_is_never_written_to_the_log_when_kilakona_fails(): void
    {
        $this->configureKilakona();
        Http::fake(['sms.example.test/*' => Http::response(['success' => false], 200)]);
        Log::spy();

        (new KilakonaSmsGateway())->send('0743519100', 'Your code is 481516');

        Log::shouldHaveReceived('warning')->withArgs(fn ($message) => !str_contains((string) $message, '481516') && !str_contains((string) $message, '0743519100'));
    }

    // -------------------------------------------------- the log stand-in

    public function test_a_code_is_withheld_from_the_log_in_production_but_readable_in_development(): void
    {
        Log::spy();
        (new LogSmsGateway())->send('0743519100', 'Your code is 481516', sensitive: true);
        Log::shouldHaveReceived('info')->withArgs(fn ($message) => str_contains((string) $message, '481516'));

        $this->app['env'] = 'production';
        Log::spy();
        (new LogSmsGateway())->send('0743519100', 'Your code is 481516', sensitive: true);
        Log::shouldHaveReceived('info')->withArgs(fn ($message) => !str_contains((string) $message, '481516') && !str_contains((string) $message, '0743519100'));
    }

    // ----------------------------------------------------- the service

    public function test_the_container_picks_the_driver_from_config(): void
    {
        // TestCase replaces the gateway with a fake; ask the provider for the real binding.
        $this->app->forgetInstance(SmsGateway::class);

        config(['sms.driver' => 'kilakona']);
        $this->assertInstanceOf(KilakonaSmsGateway::class, $this->app->make(SmsGateway::class));

        $this->app->forgetInstance(SmsGateway::class);
        config(['sms.driver' => 'log']);
        $this->assertInstanceOf(LogSmsGateway::class, $this->app->make(SmsGateway::class));
    }

    public function test_the_sms_service_never_throws_whatever_the_provider_does(): void
    {
        $this->sms->failWith(new \RuntimeException('provider exploded'));

        $this->assertFalse(SmsService::send('0743519100', 'hi'));
    }

    public function test_the_credentials_are_not_in_the_code_or_the_config_defaults(): void
    {
        $config = file_get_contents(base_path('config/sms.php'));

        $this->assertStringNotContainsString('RUvm', $config);
        $this->assertSame('', config('sms.kilakona.secret_key', ''), 'the test environment has no real credentials');
        $this->assertSame('', config('sms.kilakona.api_key', ''));
    }
}
