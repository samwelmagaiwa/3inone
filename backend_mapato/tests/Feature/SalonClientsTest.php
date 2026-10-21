<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Services\Sms\SmsGateway;
use App\Support\Tenancy\TenantContext;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\Support\FakeSmsGateway;
use Tests\TestCase;

/**
 * What a salon remembers about its clients (birthday, what they like, who sent them, photos with consent), who is new,
 * who comes back, who has gone quiet, messages to a group, and the birthday wish. Texts always respect "do not text me".
 */
class SalonClientsTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function tearDown(): void
    {
        Carbon::setTestNow();

        parent::tearDown();
    }

    private function salon(string $name = 'Glow Salon'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => 'admin', 'is_active' => true,
            'phone_number' => '0723' . str_pad((string) ++$this->seq, 6, '0', STR_PAD_LEFT),
        ]), 'salon');
        Business::forOwnerId($owner->id)->update(['name' => $name]);

        return $owner;
    }

    private function person(User $owner, string $name, string $role = 'hair_stylist'): User
    {
        return $this->givenServices(User::factory()->create(['name' => $name, 'role' => $role, 'is_active' => true, 'created_by' => $owner->id]), 'salon');
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('X-Service', 'salon')->json($method, $uri, $body);
    }

    private function rows(User $as, callable $fn)
    {
        return TenantContext::runAs($as, fn () => TenantContext::runInService('salon', $fn));
    }

    private function at(string $when): void
    {
        Carbon::setTestNow(Carbon::parse($when, 'UTC'));
    }

    private function service(User $as, string $name = 'Wash', int $price = 10000): int
    {
        return $this->api($as, 'POST', '/api/inventory/products', ['name' => $name, 'is_service' => true, 'quantity' => 0, 'min_stock' => 0, 'status' => 'active', 'cost_price' => 0, 'selling_price' => $price])->assertCreated()->json('data.id');
    }

    private function client(User $as, string $name, ?string $phone = '0711000001'): int
    {
        if ($phone === null) {
            // The till does not make a client without a number; an old or imported one can be like that.
            return (int) $this->rows($as, fn () => DB::table('inventory_customers')->insertGetId(['name' => $name, 'phone' => '', 'created_at' => now(), 'updated_at' => now()]));
        }

        return $this->api($as, 'POST', '/api/inventory/customers', ['name' => $name, 'phone' => $phone])->assertCreated()->json('data.id');
    }

    private function visit(User $as, int $client, int $service, int $price = 10000)
    {
        return $this->api($as, 'POST', '/api/inventory/sales', [
            'customer_id' => $client, 'payment_status' => 'paid', 'subtotal' => $price, 'discount' => 0, 'tax' => 0, 'total' => $price, 'paid_total' => $price,
            'items' => [['product_id' => $service, 'quantity' => 1, 'unit_price' => $price]],
        ])->assertCreated();
    }

    private function freshSms(): FakeSmsGateway
    {
        $this->sms = new FakeSmsGateway();
        $this->app->instance(SmsGateway::class, $this->sms);

        return $this->sms;
    }

    private function tinyPng(): UploadedFile
    {
        $path = tempnam(sys_get_temp_dir(), 'png');
        file_put_contents($path, base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));

        return new UploadedFile($path, 'style.png', 'image/png', null, true);
    }

    // ------------------------------------------------------------------ what they like

    public function test_a_clients_birthday_preferences_and_referrer_are_kept_and_shown(): void
    {
        $owner = $this->salon();
        $friend = $this->client($owner, 'Rehema', '0711000002');
        $neema = $this->client($owner, 'Neema');

        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$neema}", [
            'birthday' => '1990-10-08', 'referred_by' => $friend, 'notes' => 'Prefers a quiet corner',
            'preferences' => ['hairstyle' => 'Knotless braids', 'colour' => 'Burgundy', 'nails' => '  ', 'allergies' => 'Latex'],
        ])->assertOk();

        $c = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/history")->assertOk()->json('data.client');
        $this->assertSame(['1990-10-08', $friend, 'Rehema', 'Prefers a quiet corner'], [$c['birthday'], $c['referred_by'], $c['referred_by_name'], $c['notes']]);
        $this->assertSame(['hairstyle' => 'Knotless braids', 'colour' => 'Burgundy', 'allergies' => 'Latex'], $c['preferences'], 'an empty answer is not kept');

        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$neema}", ['preferences' => ['hairstyle' => '']])->assertOk();
        $this->assertEmpty($this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/history")->json('data.client.preferences'));
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$neema}", ['birthday' => null, 'referred_by' => null])->assertOk();
        $c = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/history")->json('data.client');
        $this->assertSame([null, null], [$c['birthday'], $c['referred_by']]);
    }

    public function test_the_checks_on_what_is_kept_about_a_client(): void
    {
        $owner = $this->salon();
        $other = $this->salon('Other');
        $neema = $this->client($owner, 'Neema');
        $theirs = $this->client($other, 'Theirs', '0799000001');
        $url = "/api/inventory/salon/clients/{$neema}";

        $this->api($owner, 'PATCH', $url, ['birthday' => '2999-01-01'])->assertStatus(422);
        $this->api($owner, 'PATCH', $url, ['birthday' => 'tomorrow'])->assertStatus(422);
        $this->api($owner, 'PATCH', $url, ['referred_by' => $neema])->assertStatus(422);
        $this->api($owner, 'PATCH', $url, ['referred_by' => 99999])->assertStatus(422);
        $this->api($owner, 'PATCH', $url, ['referred_by' => $theirs])->assertStatus(422);
        $this->api($owner, 'PATCH', $url, ['preferences' => ['hairstyle' => str_repeat('x', 161)]])->assertStatus(422);
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$theirs}", ['notes' => 'x'])->assertStatus(404);
    }

    public function test_a_client_is_new_until_the_second_visit_and_goods_are_not_a_visit(): void
    {
        $owner = $this->salon();
        $wash = $this->service($owner);
        $oil = $this->api($owner, 'POST', '/api/inventory/products', ['name' => 'Oil', 'quantity' => 9, 'min_stock' => 1, 'status' => 'active', 'cost_price' => 1, 'selling_price' => 5000])->json('data.id');
        $neema = $this->client($owner, 'Neema');
        $stats = fn () => $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/history")->json('data.stats');

        $this->at('2026-09-01 10:00:00');
        $this->visit($owner, $neema, $oil, 5000);
        $this->assertSame([false, null], [$stats()['is_returning'], $stats()['first_visit_on']]);
        $this->visit($owner, $neema, $wash);
        $this->assertSame([false, '2026-09-01', 1], [$stats()['is_returning'], $stats()['first_visit_on'], $stats()['visits']]);
        $this->at('2026-10-01 10:00:00');
        $this->visit($owner, $neema, $wash);
        $this->assertSame([true, '2026-09-01', 2], [$stats()['is_returning'], $stats()['first_visit_on'], $stats()['visits']]);
    }

    // ------------------------------------------------------------------ photos

    public function test_a_photo_is_only_kept_with_consent_and_given_back_as_a_signed_link(): void
    {
        Storage::fake('local');
        $owner = $this->salon();
        $neema = $this->client($owner, 'Neema');

        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/photos", ['photo' => $this->tinyPng()])->assertStatus(422);
        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/photos", ['photo' => $this->tinyPng(), 'consent' => false])->assertStatus(422);
        $this->assertSame(0, $this->rows($owner, fn () => DB::table('inventory_client_photos')->count()), 'nothing is kept without a yes');

        $res = $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/photos", ['photo' => $this->tinyPng(), 'consent' => true, 'caption' => 'Knotless, October'])->assertCreated();
        $this->assertStringContainsString('/api/files/private/salon_client_photos/', (string) $res->json('data.url'));

        $list = $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/photos")->json('data');
        $this->assertSame(['Knotless, October'], array_column($list, 'caption'));
        $this->assertStringContainsString('signature=', $list[0]['url']);

        // a photo whose consent was withdrawn is never shown
        $this->rows($owner, fn () => DB::table('inventory_client_photos')->update(['consent' => false]));
        $this->assertSame([], $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/photos")->json('data'));
    }

    public function test_a_photo_can_be_deleted_and_a_file_that_is_not_a_picture_is_refused(): void
    {
        Storage::fake('local');
        $owner = $this->salon();
        $neema = $this->client($owner, 'Neema');
        $id = $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/photos", ['photo' => $this->tinyPng(), 'consent' => true])->assertCreated()->json('data.id');

        $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/photos", ['photo' => UploadedFile::fake()->create('virus.php', 10, 'application/x-php'), 'consent' => true])->assertStatus(422);
        $this->api($owner, 'DELETE', "/api/inventory/salon/photos/{$id}")->assertOk();
        $this->assertSame([], $this->api($owner, 'GET', "/api/inventory/salon/clients/{$neema}/photos")->json('data'));
        $this->api($owner, 'DELETE', "/api/inventory/salon/photos/{$id}")->assertStatus(404);
    }

    public function test_another_salon_never_sees_or_adds_photos_to_a_client_that_is_not_theirs(): void
    {
        Storage::fake('local');
        $owner = $this->salon();
        $other = $this->salon('Other');
        $neema = $this->client($owner, 'Neema');
        $id = $this->api($owner, 'POST', "/api/inventory/salon/clients/{$neema}/photos", ['photo' => $this->tinyPng(), 'consent' => true])->json('data.id');

        $this->api($other, 'GET', "/api/inventory/salon/clients/{$neema}/photos")->assertStatus(404);
        $this->api($other, 'POST', "/api/inventory/salon/clients/{$neema}/photos", ['photo' => $this->tinyPng(), 'consent' => true])->assertStatus(404);
        $this->api($other, 'DELETE', "/api/inventory/salon/photos/{$id}")->assertStatus(404);
    }

    // ------------------------------------------------------------------ groups of clients

    /** Five clients: brand new, coming back, gone quiet, opted out, no phone; one has a birthday this month. */
    private function mixOfClients(User $owner): array
    {
        $wash = $this->service($owner);
        $ids = [
            'new' => $this->client($owner, 'Newbie', '0711000001'),
            'back' => $this->client($owner, 'Comeback', '0711000002'),
            'quiet' => $this->client($owner, 'Quiet', '0711000003'),
            'optout' => $this->client($owner, 'Optout', '0711000004'),
            'nophone' => $this->client($owner, 'Nophone', null),
        ];
        $this->at('2026-07-01 10:00:00');
        $this->visit($owner, $ids['quiet'], $wash, 5000);                      // long ago
        $this->at('2026-09-20 10:00:00');
        $this->visit($owner, $ids['back'], $wash, 20000);
        $this->visit($owner, $ids['optout'], $wash, 15000);
        $this->visit($owner, $ids['nophone'], $wash, 1000);
        $this->at('2026-10-05 10:00:00');
        $this->visit($owner, $ids['back'], $wash, 30000);
        $this->visit($owner, $ids['new'], $wash, 12000);
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$ids['optout']}", ['sms_opt_out' => true])->assertOk();
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$ids['new']}", ['birthday' => '1995-10-20'])->assertOk();
        $this->at('2026-10-10 09:00:00');

        return $ids;
    }

    public function test_the_overview_counts_new_returning_quiet_birthdays_and_best_spenders(): void
    {
        $owner = $this->salon();
        $ids = $this->mixOfClients($owner);

        $d = $this->api($owner, 'GET', '/api/inventory/salon/clients/overview')->assertOk()->json('data');

        $this->assertSame(5, $d['total']);
        $this->assertSame(4, $d['new'], 'first visit within 30 days: Newbie, Comeback, Optout, Nophone');
        $this->assertSame(1, $d['returning']);
        $this->assertSame(1, $d['inactive'], 'Quiet has not been since July (more than 8 weeks)');
        $this->assertSame([['Newbie', '1995-10-20']], array_map(fn ($b) => [$b['name'], $b['birthday']], $d['birthdays']));
        $this->assertSame(['Comeback', 'Optout', 'Newbie'], array_slice(array_column($d['top_spenders'], 'name'), 0, 3), 'the most spent first');
        $this->assertSame(50000, $d['top_spenders'][0]['spent']);

        $wide = $this->api($owner, 'GET', '/api/inventory/salon/clients/overview?inactive_weeks=2')->json('data');
        $this->assertSame(3, $wide['inactive'], 'two weeks of quiet: Quiet, and now Optout and Nophone, last seen on the 20th of September');
    }

    public function test_the_groups_say_how_many_they_would_reach_and_never_count_those_who_cannot_be_texted(): void
    {
        $owner = $this->salon();
        $this->mixOfClients($owner);

        $d = $this->api($owner, 'GET', '/api/inventory/salon/campaigns')->assertOk()->json('data');
        $by = collect($d['segments'])->keyBy('segment');

        $this->assertSame([5, 3], [$by['all']['members'], $by['all']['reachable']], 'one opted out, one has no phone');
        $this->assertSame([4, 2], [$by['new']['members'], $by['new']['reachable']]);
        $this->assertSame([1, 1], [$by['returning']['members'], $by['returning']['reachable']]);
        $this->assertSame([1, 1], [$by['inactive']['members'], $by['inactive']['reachable']]);
        $this->assertSame([1, 1], [$by['birthday_month']['members'], $by['birthday_month']['reachable']]);
        $this->assertSame([], $d['campaigns']);
    }

    public function test_a_message_goes_to_the_group_with_each_first_name_and_is_recorded(): void
    {
        $owner = $this->salon();
        $this->mixOfClients($owner);
        $this->freshSms();

        $res = $this->api($owner, 'POST', '/api/inventory/salon/campaigns', ['name' => 'Come back', 'segment' => 'inactive', 'message' => 'Habari {name}, tumekukumbuka! / Hello {name}, we miss you!'])->assertCreated();

        $this->assertSame([1, 1], [$res->json('data.recipients'), $res->json('data.sent')]);
        $this->assertSame('0711000003', $this->sms->sent[0]['to']);
        $this->assertSame('Habari Quiet, tumekukumbuka! / Hello Quiet, we miss you!', $this->sms->sent[0]['message']);

        $list = $this->api($owner, 'GET', '/api/inventory/salon/campaigns')->json('data.campaigns');
        $this->assertSame(['Come back', 'inactive', 1, 1], [$list[0]['name'], $list[0]['segment'], $list[0]['recipients'], $list[0]['sent']]);

        $this->freshSms();
        $this->api($owner, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'all', 'message' => 'Open on Sunday!'])->assertCreated()->assertJsonPath('data.recipients', 3);
        $this->assertSame(['0711000002', '0711000001', '0711000003'], array_column($this->sms->sent, 'to'), 'by name (Comeback, Newbie, Quiet); the opted-out client and the one with no phone are not texted');
    }

    public function test_a_text_that_could_not_be_sent_is_counted_as_not_sent(): void
    {
        $owner = $this->salon();
        $this->mixOfClients($owner);
        $this->freshSms()->refuseAll();

        $res = $this->api($owner, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'returning', 'message' => 'Hello {name}!'])->assertCreated();

        $this->assertSame([1, 0], [$res->json('data.recipients'), $res->json('data.sent')]);
    }

    public function test_a_message_needs_text_a_known_group_and_someone_to_reach(): void
    {
        $owner = $this->salon();
        $this->mixOfClients($owner);

        $this->api($owner, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'all', 'message' => 'Hi'])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'all', 'message' => str_repeat('x', 321)])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'martians', 'message' => 'Hello there'])->assertStatus(422);
        $this->api($owner, 'POST', '/api/inventory/salon/campaigns', ['message' => 'Hello there'])->assertStatus(422);

        $lonely = $this->salon('Lonely');
        $this->api($lonely, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'all', 'message' => 'Hello there'])->assertStatus(422);
        $this->assertSame(0, $this->rows($lonely, fn () => DB::table('inventory_campaigns')->count()));
    }

    public function test_only_whoever_holds_the_settings_right_sends_messages_and_never_the_super_admin(): void
    {
        $owner = $this->salon();
        $this->mixOfClients($owner);
        $asha = $this->person($owner, 'Asha');
        $manager = $this->person($owner, 'Mary', 'manager');
        $super = User::factory()->create(['role' => 'super_admin', 'is_active' => true, 'full_access' => true, 'phone_number' => '0755000000']);
        $this->freshSms();

        $this->api($asha, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'all', 'message' => 'Hello there'])->assertStatus(403);
        $this->api($asha, 'GET', '/api/inventory/salon/campaigns')->assertStatus(403);
        $this->api($super, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'all', 'message' => 'Hello there'])->assertStatus(403);
        $this->assertCount(0, $this->sms->sent);
        // Sending texts to groups of clients is setting the salon up: the "settings" right (the owner's), not a role name.
        $this->api($manager, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'returning', 'message' => 'Hello there'])->assertStatus(403);
        $manager->forceFill(['permissions' => ['inv_manage_settings']])->save();
        $this->api($manager->refresh(), 'POST', '/api/inventory/salon/campaigns', ['segment' => 'returning', 'message' => 'Hello there'])->assertCreated();
    }

    public function test_one_salon_never_messages_or_sees_the_clients_of_another(): void
    {
        $glow = $this->salon('Glow');
        $this->mixOfClients($glow);
        $other = $this->salon('Other');
        $this->freshSms();

        $d = $this->api($other, 'GET', '/api/inventory/salon/clients/overview')->json('data');
        $this->assertSame([0, 0, 0, 0], [$d['total'], $d['new'], $d['returning'], $d['inactive']]);
        $this->api($other, 'POST', '/api/inventory/salon/campaigns', ['segment' => 'all', 'message' => 'Hello there'])->assertStatus(422);
        $this->assertCount(0, $this->sms->sent);
    }

    // ------------------------------------------------------------------ the birthday wish

    private function enableBirthdays(User $owner, string $text = '10% off this week'): void
    {
        $this->api($owner, 'PUT', '/api/inventory/salon/settings', ['birthday_offer' => true, 'birthday_text' => $text])->assertOk()
            ->assertJsonPath('data.birthday_offer', true)->assertJsonPath('data.birthday_text', $text);
    }

    public function test_a_client_is_wished_once_a_year_on_their_birthday_with_the_owners_offer(): void
    {
        $owner = $this->salon('Glow Salon');
        $neema = $this->client($owner, 'neema juma');
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$neema}", ['birthday' => '1990-10-08'])->assertOk();
        $this->enableBirthdays($owner);
        $this->freshSms();

        $this->at('2026-10-07 05:30:00');                                         // the day before
        $this->artisan('salon:birthday-offers')->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent);

        $this->at('2026-10-08 05:30:00');
        $this->artisan('salon:birthday-offers', ['--dry-run' => true])->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'a dry run sends nothing');
        $this->artisan('salon:birthday-offers')->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent);
        $this->assertSame(
            'Habari Neema, heri ya kuzaliwa kutoka Glow Salon! 10% off this week. Karibu! / Happy birthday Neema from Glow Salon! 10% off this week. Welcome!',
            $this->sms->sent[0]['message']
        );

        $this->artisan('salon:birthday-offers')->assertExitCode(0);
        $this->assertCount(1, $this->sms->sent, 'the same day again: not twice');

        $this->at('2027-10-08 05:30:00');
        $this->artisan('salon:birthday-offers')->assertExitCode(0);
        $this->assertCount(2, $this->sms->sent, 'next year: wished again');
    }

    public function test_no_wish_unless_switched_on_and_never_to_someone_who_cannot_be_texted(): void
    {
        $owner = $this->salon();
        $a = $this->client($owner, 'Anna', '0711000001');
        $b = $this->client($owner, 'Optout', '0711000002');
        $c = $this->client($owner, 'Nophone', null);
        foreach ([$a, $b, $c] as $id) {
            $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$id}", ['birthday' => '1990-10-08'])->assertOk();
        }
        $this->api($owner, 'PATCH', "/api/inventory/salon/clients/{$b}", ['sms_opt_out' => true])->assertOk();
        $this->freshSms();
        $this->at('2026-10-08 05:30:00');

        $this->artisan('salon:birthday-offers')->assertExitCode(0);
        $this->assertCount(0, $this->sms->sent, 'off until the owner switches it on');

        $this->enableBirthdays($owner, '');
        $this->artisan('salon:birthday-offers')->assertExitCode(0);
        $this->assertSame(['0711000001'], array_column($this->sms->sent, 'to'));
        $this->assertStringNotContainsString('. .', $this->sms->sent[0]['message'], 'no offer, no gap in the sentence');
    }

    public function test_a_failed_wish_is_tried_again_and_each_salon_wishes_its_own(): void
    {
        $glow = $this->salon('Glow');
        $other = $this->salon('Other');
        foreach ([$glow, $other] as $o) {
            $id = $this->client($o, 'Anna', '0711000001');
            $this->api($o, 'PATCH', "/api/inventory/salon/clients/{$id}", ['birthday' => '1990-10-08'])->assertOk();
            $this->enableBirthdays($o, 'Gift');
        }
        $this->at('2026-10-08 05:30:00');

        $this->freshSms()->refuseAll();
        $this->artisan('salon:birthday-offers')->assertExitCode(0);
        $this->assertSame(0, $this->rows($glow, fn () => DB::table('inventory_birthday_wishes')->count()), 'the claim is given back');

        $this->freshSms();
        $this->artisan('salon:birthday-offers')->assertExitCode(0);
        $this->assertCount(2, $this->sms->sent);
        $messages = array_column($this->sms->sent, 'message');
        $this->assertCount(1, array_filter($messages, fn ($m) => str_contains($m, 'Glow')));
        $this->assertCount(1, array_filter($messages, fn ($m) => str_contains($m, 'Other')));
        $this->artisan('schedule:list')->expectsOutputToContain('salon:birthday-offers')->assertExitCode(0);
    }
}
