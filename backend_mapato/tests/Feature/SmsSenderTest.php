<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\Rental\House;
use App\Models\Rental\Property;
use App\Models\Rental\RentalAgreement;
use App\Models\Rental\RentBill;
use App\Models\User;
use App\Services\Rental\RentalService;
use App\Services\Sms\KilakonaSmsGateway;
use App\Support\SmsSenderName;
use Illuminate\Http\Client\Request as HttpRequest;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Each business can have its own registered SMS sender name, so its customers' phones show the business instead
 * of a number. A super admin sets the names (an owner can ask for one), registers them with the provider, and
 * marks them approved; only an approved name is ever used. Everything else keeps working under the platform's name.
 */
class SmsSenderTest extends TestCase
{
    use RefreshDatabase;

    private int $seq = 0;

    protected function setUp(): void
    {
        parent::setUp();
        config(['sms.kilakona.sender_id' => 'PLATFORM', 'billing.contact_phone' => '']);
    }

    private function owner(string $name, array $business = [], string $role = 'admin'): User
    {
        $owner = $this->givenServices(User::factory()->create([
            'name' => "{$name} Owner", 'role' => $role, 'is_active' => true,
            'phone_number' => '07230000' . str_pad((string) ++$this->seq, 2, '0', STR_PAD_LEFT),
        ]), 'transport', 'rental', 'inventory');
        Business::forOwnerId($owner->id)->update($business + ['name' => $name]);

        return $owner;
    }

    private function superAdmin(?string $phone = '0617919104'): User
    {
        return User::factory()->create(['role' => 'super_admin', 'is_active' => true, 'phone_number' => $phone]);
    }

    private function as(User $user, string $method, string $uri, array $body = [])
    {
        $token = $user->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, $uri, $body);
    }

    private function staffOf(User $owner): User
    {
        $staff = User::factory()->create(['role' => 'manager', 'is_active' => true, 'created_by' => $owner->id, 'phone_number' => '0733000' . str_pad((string) ++$this->seq, 3, '0', STR_PAD_LEFT)]);

        return $this->givenServices($staff, 'transport');
    }

    private function business(User $owner): Business
    {
        return Business::forOwnerId($owner->id)->fresh();
    }

    private function save(User $super, User $owner, array $body)
    {
        return $this->as($super, 'PUT', '/api/admin/sms-senders/' . $this->business($owner)->id, $body);
    }

    /** @return array<int, array{to: string, message: string, sensitive: bool, sender: ?string}> */
    private function textsTo(string $phone): array
    {
        return $this->sms->to($phone);
    }

    // ------------------------------------------------------------ the super admin's page

    public function test_the_list_shows_what_needs_attention_first_with_counts(): void
    {
        $none = $this->owner('Alpha');
        $pending = $this->owner('Bravo', ['sms_sender_id' => 'BRAVOCO', 'sms_sender_status' => 'pending']);
        $good = $this->owner('Charlie', ['sms_sender_id' => 'CHARLIEBIZ', 'sms_sender_status' => 'approved']);
        $broken = $this->owner('Delta', ['sms_sender_id' => 'DELTASHOP', 'sms_sender_status' => 'approved', 'sms_last_error' => 'refused']);
        $rejected = $this->owner('Echo', ['sms_sender_id' => 'ECHOLTD', 'sms_sender_status' => 'rejected']);

        $response = $this->as($this->superAdmin(), 'GET', '/api/admin/sms-senders')->assertOk();

        $names = collect($response->json('data'))->pluck('name')->all();
        $this->assertSame(['Bravo', 'Delta', 'Charlie', 'Echo', 'Alpha'], $names, 'pending, then a name that stopped working, then approved, rejected, none');
        $response->assertJsonPath('meta.counts.total', 5)
            ->assertJsonPath('meta.counts.none', 1)
            ->assertJsonPath('meta.counts.pending', 1)
            ->assertJsonPath('meta.counts.approved', 2)
            ->assertJsonPath('meta.counts.rejected', 1)
            ->assertJsonPath('meta.counts.attention', 1)
            ->assertJsonPath('meta.platform_sender', 'PLATFORM')
            ->assertJsonPath('data.0.sms_sender.sender_id', 'BRAVOCO')
            ->assertJsonPath('data.0.owner.name', 'Bravo Owner');
        $this->assertTrue($response->json('data.1.sms_sender.needs_attention'));
        $this->assertFalse($response->json('data.2.sms_sender.needs_attention'));
    }

    public function test_the_list_filters_by_status_and_searches_names_owners_and_sender_names(): void
    {
        $this->owner('Alpha');
        $this->owner('Bravo', ['sms_sender_id' => 'BRAVOCO', 'sms_sender_status' => 'pending']);
        $this->owner('Charlie', ['sms_sender_id' => 'CHARLIEBIZ', 'sms_sender_status' => 'approved']);
        $this->owner('Delta', ['sms_sender_id' => 'DELTASHOP', 'sms_sender_status' => 'approved', 'sms_last_error' => 'refused']);
        $super = $this->superAdmin();

        $names = fn (string $query) => collect($this->as($super, 'GET', "/api/admin/sms-senders?{$query}")->assertOk()->json('data'))->pluck('name')->all();

        $this->assertSame(['Bravo'], $names('status=pending'));
        $this->assertSame(['Delta'], $names('status=attention'));
        $this->assertEqualsCanonicalizing(['Charlie', 'Delta'], $names('status=approved'));
        $this->assertSame(['Alpha'], $names('status=none'));
        $this->assertSame(['Charlie'], $names('q=charliebiz'), 'by sender name');
        $this->assertSame(['Bravo'], $names('q=Bravo+Owner'), 'by owner');
        $this->assertCount(4, $names('status=all'));
    }

    public function test_setting_a_name_and_approving_it_texts_the_owner_from_the_platform(): void
    {
        $owner = $this->owner('Mama Asha Store');
        $super = $this->superAdmin();

        $this->save($super, $owner, ['sender_id' => 'MAMAASHA', 'display_name' => 'Mama Asha', 'status' => 'approved'])
            ->assertOk()
            ->assertJsonPath('data.sms_sender.sender_id', 'MAMAASHA')
            ->assertJsonPath('data.sms_sender.status', 'approved')
            ->assertJsonPath('data.sms_sender.display_name', 'Mama Asha');

        $business = $this->business($owner);
        $this->assertSame('MAMAASHA', $business->usableSmsSender());
        $this->assertNotNull($business->sms_sender_approved_at);

        $texts = $this->textsTo($owner->phone_number);
        $this->assertCount(1, $texts);
        $this->assertStringContainsString('"MAMAASHA"', $texts[0]['message']);
        $this->assertStringContainsString('limeidhinishwa', $texts[0]['message']);
        $this->assertStringContainsString('is approved', $texts[0]['message']);
        $this->assertNull($texts[0]['sender'], 'the approval itself is a platform text');
    }

    public function test_a_name_set_without_a_status_waits_for_approval_and_is_not_used(): void
    {
        $owner = $this->owner('Mama Asha Store');

        $this->save($this->superAdmin(), $owner, ['sender_id' => 'MAMAASHA'])
            ->assertOk()
            ->assertJsonPath('data.sms_sender.status', 'pending');

        $business = $this->business($owner);
        $this->assertNull($business->usableSmsSender(), 'only an approved name is ever used');
        $this->assertNotNull($business->sms_sender_requested_at);
        $this->assertSame([], $this->textsTo($owner->phone_number), 'no text until it is approved or rejected');
    }

    public function test_changing_an_approved_name_sends_it_back_to_waiting(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'approved']);

        $this->save($this->superAdmin(), $owner, ['sender_id' => 'MAMAASHA2'])->assertOk()->assertJsonPath('data.sms_sender.status', 'pending');

        $this->assertNull($this->business($owner)->usableSmsSender());
        $this->assertNull($this->business($owner)->sms_sender_approved_at);
    }

    public function test_rejecting_texts_the_owner_with_the_reason(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'pending']);

        $this->save($this->superAdmin(), $owner, ['status' => 'rejected', 'note' => 'The network did not accept it'])->assertOk();

        $business = $this->business($owner);
        $this->assertSame('rejected', $business->sms_sender_status);
        $this->assertSame('The network did not accept it', $business->sms_sender_note);
        $this->assertNull($business->usableSmsSender());

        $text = $this->textsTo($owner->phone_number)[0]['message'];
        $this->assertStringContainsString('halikukubaliwa', $text);
        $this->assertStringContainsString('was not approved', $text);
        $this->assertStringContainsString('The network did not accept it', $text);
    }

    public function test_clearing_the_name_resets_the_business_and_a_status_needs_a_name(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'approved', 'sms_sender_approved_at' => now()]);
        $super = $this->superAdmin();

        $this->save($super, $owner, ['status' => 'approved', 'sender_id' => ''])->assertStatus(422);

        $this->save($super, $owner, ['sender_id' => ''])->assertOk()->assertJsonPath('data.sms_sender.status', 'none');
        $business = $this->business($owner);
        $this->assertNull($business->sms_sender_id);
        $this->assertNull($business->sms_sender_approved_at);
        $this->assertNull($business->usableSmsSender());
    }

    public function test_the_name_rules(): void
    {
        $owner = $this->owner('Mama Asha Store');
        $other = $this->owner('Baba Homes', ['sms_sender_id' => 'BABAHOMES', 'sms_sender_status' => 'approved']);
        $super = $this->superAdmin();

        foreach (['AB' => 'too short', 'TWELVECHARSX' => 'too long', '1MAMA' => 'starts with a digit', 'MAMA ASHA' => 'a space', 'MAMA-ASHA' => 'a symbol', 'MÀMA' => 'an accent'] as $name => $why) {
            $this->save($super, $owner, ['sender_id' => $name])->assertStatus(422)->assertJsonPath('errors.code', 'sender_invalid');
        }
        foreach (['MPESA', 'info', 'Vodacom', 'PLATFORM', '3INONE'] as $reserved) {
            $this->save($super, $owner, ['sender_id' => $reserved])->assertStatus(422);
        }
        $this->save($super, $owner, ['sender_id' => 'babahomes'])->assertStatus(422)->assertJsonPath('message', fn ($m) => str_contains($m, 'already used'));
        $this->assertNull($this->business($owner)->sms_sender_id, 'nothing was saved');

        // A name of exactly 11 letters/digits is fine, and a business can keep (or recase) its own name.
        $this->save($super, $owner, ['sender_id' => 'MamaAsha123'])->assertOk();
        $this->save($super, $owner, ['sender_id' => 'MAMAASHA123', 'status' => 'approved'])->assertOk();
        $this->assertSame('BABAHOMES', $this->business($other)->sms_sender_id);
    }

    public function test_the_rules_in_one_place(): void
    {
        $this->assertTrue(SmsSenderName::validFormat('MAMAASHA'));
        $this->assertFalse(SmsSenderName::validFormat('MAMA ASHA'));
        $this->assertTrue(SmsSenderName::isReserved('m-pesa'), 'compared without punctuation or case');
        $this->assertFalse(SmsSenderName::isReserved('MAMAASHA'));
        $this->assertSame('MAMAASHA', SmsSenderName::key('Mama-Asha'));
    }

    public function test_only_a_super_admin_manages_names(): void
    {
        $owner = $this->owner('Mama Asha Store');
        $business = $this->business($owner);
        $staff = $this->staffOf($owner);

        foreach ([$owner, $staff] as $user) {
            $this->as($user, 'GET', '/api/admin/sms-senders')->assertForbidden();
            $this->as($user, 'PUT', "/api/admin/sms-senders/{$business->id}", ['sender_id' => 'MAMAASHA'])->assertForbidden();
            $this->as($user, 'POST', "/api/admin/sms-senders/{$business->id}/test", ['sender_id' => 'MAMAASHA'])->assertForbidden();
        }
        $this->flushHeaders();
        $this->app['auth']->forgetGuards();
        $this->getJson('/api/admin/sms-senders')->assertUnauthorized();
        $this->assertNull($this->business($owner)->sms_sender_id);
    }

    // --------------------------------------------------------------- the owner asks

    public function test_an_owner_asks_for_a_name_and_the_super_admins_are_told_once(): void
    {
        $owner = $this->owner('Mama Asha Store');
        $this->superAdmin('0617919104');

        $this->as($owner, 'POST', '/api/business/sms-sender', ['sender_id' => 'MAMAASHA', 'display_name' => 'Mama Asha'])
            ->assertOk()
            ->assertJsonPath('data.sms_sender.sender_id', 'MAMAASHA')
            ->assertJsonPath('data.sms_sender.status', 'pending')
            ->assertJsonPath('data.sms_sender.display_name', 'Mama Asha');

        $texts = $this->textsTo('0617919104');
        $this->assertCount(1, $texts);
        $this->assertStringContainsString('"Mama Asha Store"', $texts[0]['message']);
        $this->assertStringContainsString('"MAMAASHA"', $texts[0]['message']);
        $this->assertNull($this->business($owner)->usableSmsSender());

        // asking again for the same name is not another text
        $this->as($owner, 'POST', '/api/business/sms-sender', ['sender_id' => 'MAMAASHA'])->assertOk();
        $this->assertCount(1, $this->textsTo('0617919104'));

        // a different name is
        $this->as($owner, 'POST', '/api/business/sms-sender', ['sender_id' => 'MAMAASHA2'])->assertOk();
        $this->assertCount(2, $this->textsTo('0617919104'));
    }

    public function test_an_owner_cannot_take_a_bad_or_taken_name_and_cannot_change_an_approved_one(): void
    {
        $owner = $this->owner('Mama Asha Store');
        $this->owner('Baba Homes', ['sms_sender_id' => 'BABAHOMES', 'sms_sender_status' => 'approved']);

        $this->as($owner, 'POST', '/api/business/sms-sender', ['sender_id' => 'mpesa'])->assertStatus(422);
        $this->as($owner, 'POST', '/api/business/sms-sender', ['sender_id' => 'BabaHomes'])->assertStatus(422);
        $this->as($owner, 'POST', '/api/business/sms-sender', ['sender_id' => 'x'])->assertStatus(422);
        $this->as($owner, 'POST', '/api/business/sms-sender', [])->assertStatus(422);
        $this->assertNull($this->business($owner)->sms_sender_id);

        $this->save($this->superAdmin(), $owner, ['sender_id' => 'MAMAASHA', 'status' => 'approved'])->assertOk();

        $this->as($owner, 'POST', '/api/business/sms-sender', ['sender_id' => 'SOMETHING'])->assertStatus(422)->assertJsonPath('errors.code', 'sender_locked');
        $this->as($owner, 'DELETE', '/api/business/sms-sender')->assertStatus(422)->assertJsonPath('errors.code', 'sender_locked');
        $this->assertSame('MAMAASHA', $this->business($owner)->usableSmsSender(), 'an approved name is the super admin\'s to change');
    }

    public function test_a_rejected_owner_can_ask_again_and_a_waiting_request_can_be_withdrawn(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'rejected', 'sms_sender_note' => 'No']);

        $this->as($owner, 'POST', '/api/business/sms-sender', ['sender_id' => 'MAMAASHATZ'])->assertOk()->assertJsonPath('data.sms_sender.status', 'pending');
        $this->assertNull($this->business($owner)->sms_sender_note, 'the old reason is gone');

        $this->as($owner, 'DELETE', '/api/business/sms-sender')->assertOk()->assertJsonPath('data.sms_sender.status', 'none');
        $business = $this->business($owner);
        $this->assertNull($business->sms_sender_id);
        $this->assertNull($business->sms_sender_requested_at);
    }

    public function test_only_the_owner_asks_and_the_owner_sees_their_own_status_but_not_the_counters(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'pending', 'sms_sent_count' => 9]);
        $staff = $this->staffOf($owner);

        $this->as($staff, 'POST', '/api/business/sms-sender', ['sender_id' => 'OTHERNAME'])->assertForbidden();
        $this->as($staff, 'DELETE', '/api/business/sms-sender')->assertForbidden();

        $view = $this->as($owner, 'GET', '/api/business')->assertOk();
        $view->assertJsonPath('data.sms_sender.sender_id', 'MAMAASHA')->assertJsonPath('data.sms_sender.status', 'pending');
        $this->assertArrayNotHasKey('sent_count', $view->json('data.sms_sender'));

        $this->as($staff, 'GET', '/api/business')->assertOk()->assertJsonPath('data.sms_sender.status', 'pending');
    }

    // ----------------------------------------------------------- texts go out under the name

    /** @return array{0: User, 1: User} landlord (with a business) and the tenant who owes rent */
    private function landlordWithOverdueTenant(string $name, array $business, string $tenantPhone): array
    {
        $landlord = $this->owner($name, $business + ['phone' => '0712999000'], 'landlord');
        $property = Property::create(['owner_id' => $landlord->id, 'name' => "{$name} Plot"]);
        $house = House::create(['property_id' => $property->id, 'house_number' => 'A1', 'rent_amount' => 100000]);
        $tenant = User::factory()->create(['role' => 'tenant', 'is_active' => true, 'created_by' => $landlord->id, 'phone_number' => $tenantPhone]);
        $agreement = RentalAgreement::create([
            'tenant_id' => $tenant->id, 'house_id' => $house->id, 'property_id' => $property->id,
            'start_date' => now()->subMonth()->toDateString(), 'rent_cycle' => 'monthly', 'rent_amount' => 100000, 'status' => 'active',
        ]);
        RentBill::create([
            'agreement_id' => $agreement->id, 'month_year' => now()->format('m-Y'), 'amount_due' => 100000,
            'balance' => 100000, 'due_date' => now()->subDays(2)->toDateString(), 'status' => 'unpaid',
        ]);

        return [$landlord, $tenant];
    }

    public function test_a_business_text_goes_out_under_its_approved_sender_name_and_is_counted(): void
    {
        [$landlord, $tenant] = $this->landlordWithOverdueTenant('Mama Rent', ['sms_sender_id' => 'MAMARENT', 'sms_sender_status' => 'approved'], '0766000111');

        app(RentalService::class)->processOverdueBills();

        $texts = $this->textsTo($tenant->phone_number);
        $this->assertCount(1, $texts);
        $this->assertSame('MAMARENT', $texts[0]['sender']);
        $this->assertStringStartsWith('Mama Rent: URGENT', $texts[0]['message'], 'the text still says who it is from');

        $business = $this->business($landlord);
        $this->assertSame(1, $business->sms_sent_count);
        $this->assertSame(1, $business->sms_own_count);
        $this->assertSame(0, $business->sms_fallback_count);
        $this->assertNotNull($business->sms_last_sent_at);
        $this->assertNull($business->sms_last_error);
    }

    public function test_a_name_that_is_not_approved_is_never_used(): void
    {
        foreach (['none' => null, 'pending' => 'WAITINGCO', 'rejected' => 'REJECTEDCO'] as $status => $name) {
            $this->sms->sent = [];
            $this->sms->attempts = [];
            [, $tenant] = $this->landlordWithOverdueTenant("Biz {$status}", ['sms_sender_id' => $name, 'sms_sender_status' => $status], '07660002' . strlen($status) . '0');

            app(RentalService::class)->processOverdueBills();

            $texts = $this->textsTo($tenant->phone_number);
            $this->assertCount(1, $texts, $status);
            $this->assertNull($texts[0]['sender'], "{$status}: the platform's name");
            $this->assertStringContainsString("Biz {$status}:", $texts[0]['message'], 'and the text names the business');

            RentBill::query()->update(['status' => 'paid']);
        }
    }

    public function test_each_business_texts_under_its_own_name_and_never_anothers(): void
    {
        [, $t1] = $this->landlordWithOverdueTenant('Mama Rent', ['sms_sender_id' => 'MAMARENT', 'sms_sender_status' => 'approved'], '0766000111');
        [, $t2] = $this->landlordWithOverdueTenant('Baba Homes', ['sms_sender_id' => 'BABAHOMES', 'sms_sender_status' => 'approved'], '0766000222');
        [, $t3] = $this->landlordWithOverdueTenant('Plain Co', [], '0766000333');

        app(RentalService::class)->processOverdueBills();

        $this->assertSame('MAMARENT', $this->textsTo($t1->phone_number)[0]['sender']);
        $this->assertSame('BABAHOMES', $this->textsTo($t2->phone_number)[0]['sender']);
        $this->assertNull($this->textsTo($t3->phone_number)[0]['sender']);
    }

    public function test_the_short_display_name_is_what_the_text_says(): void
    {
        [, $tenant] = $this->landlordWithOverdueTenant('Mama Asha Wholesale and Retail Stores Limited', [
            'sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'approved', 'sms_display_name' => 'Mama Asha',
        ], '0766000111');

        app(RentalService::class)->processOverdueBills();

        $this->assertStringStartsWith('Mama Asha: URGENT', $this->textsTo($tenant->phone_number)[0]['message']);
    }

    public function test_when_the_provider_refuses_the_name_the_customer_is_still_told_and_the_business_is_flagged(): void
    {
        [$landlord, $tenant] = $this->landlordWithOverdueTenant('Mama Rent', ['sms_sender_id' => 'MAMARENT', 'sms_sender_status' => 'approved'], '0766000111');
        $this->sms->refuseSenders('MAMARENT');

        app(RentalService::class)->processOverdueBills();

        $this->assertSame(
            [['sender' => 'MAMARENT', 'accepted' => false], ['sender' => null, 'accepted' => true]],
            array_map(fn (array $a) => ['sender' => $a['sender'], 'accepted' => $a['accepted']], $this->sms->attempts),
            'refused under its name, then once under the platform name'
        );
        $texts = $this->textsTo($tenant->phone_number);
        $this->assertCount(1, $texts, 'the customer got exactly one text');
        $this->assertNull($texts[0]['sender']);
        $this->assertStringStartsWith('Mama Rent:', $texts[0]['message']);

        $business = $this->business($landlord);
        $this->assertSame(1, $business->sms_sent_count);
        $this->assertSame(0, $business->sms_own_count);
        $this->assertSame(1, $business->sms_fallback_count);
        $this->assertStringContainsString('MAMARENT', (string) $business->sms_last_error);
        $this->assertTrue($business->smsNeedsAttention());

        $listed = $this->as($this->superAdmin(), 'GET', '/api/admin/sms-senders?status=attention')->assertOk();
        $this->assertSame(['Mama Rent'], collect($listed->json('data'))->pluck('name')->all());

        // The provider learns the name; the next text goes out under it and the flag clears itself.
        $this->sms->refuseSenders();
        RentBill::query()->update(['status' => 'unpaid']);
        app(RentalService::class)->processOverdueBills();

        $business = $this->business($landlord);
        $this->assertSame(1, $business->sms_own_count);
        $this->assertNull($business->sms_last_error);
        $this->assertFalse($business->smsNeedsAttention());
    }

    public function test_no_answer_from_the_provider_is_never_resent(): void
    {
        [$landlord, $tenant] = $this->landlordWithOverdueTenant('Mama Rent', ['sms_sender_id' => 'MAMARENT', 'sms_sender_status' => 'approved'], '0766000111');
        $this->sms->noAnswer();

        app(RentalService::class)->processOverdueBills();

        $this->assertCount(1, $this->sms->attempts, 'the first try may have gone through, so there is no second');
        $this->assertSame([], $this->textsTo($tenant->phone_number));
        $business = $this->business($landlord);
        $this->assertSame(0, $business->sms_sent_count);
        $this->assertSame(0, $business->sms_fallback_count);
        $this->assertNull($business->sms_last_error, 'a timeout says nothing about the name');
    }

    public function test_a_provider_that_throws_never_breaks_the_job_and_is_not_resent_either(): void
    {
        [$landlord, $tenant] = $this->landlordWithOverdueTenant('Mama Rent', ['sms_sender_id' => 'MAMARENT', 'sms_sender_status' => 'approved'], '0766000111');
        $this->sms->failWith(new \RuntimeException('provider down'));

        $this->assertSame(1, app(RentalService::class)->processOverdueBills(), 'the bill is still processed');

        $this->assertCount(1, $this->sms->attempts);
        $this->assertSame([], $this->textsTo($tenant->phone_number));
    }

    public function test_a_number_the_provider_refuses_is_not_blamed_on_the_name(): void
    {
        [$landlord] = $this->landlordWithOverdueTenant('Mama Rent', ['sms_sender_id' => 'MAMARENT', 'sms_sender_status' => 'approved'], '0766000111');
        $this->sms->refuseAll();

        app(RentalService::class)->processOverdueBills();

        $business = $this->business($landlord);
        $this->assertCount(2, $this->sms->attempts, 'tried under the name, then the platform name');
        $this->assertSame(0, $business->sms_sent_count);
        $this->assertNull($business->sms_last_error, 'it failed either way, so the name is not the problem');
    }

    public function test_nothing_is_counted_while_no_real_provider_is_on(): void
    {
        [$landlord, $tenant] = $this->landlordWithOverdueTenant('Mama Rent', ['sms_sender_id' => 'MAMARENT', 'sms_sender_status' => 'approved'], '0766000111');
        $this->sms->delivering = false;

        app(RentalService::class)->processOverdueBills();

        $this->assertCount(1, $this->textsTo($tenant->phone_number));
        $this->assertSame(0, $this->business($landlord)->sms_sent_count, 'the log stand-in accepts everything; that is not a sent text');
    }

    public function test_texts_from_the_platform_never_use_a_business_name(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'approved']);
        $super = $this->superAdmin();

        $this->as($super, 'POST', '/api/admin/businesses/' . $this->business($owner)->id . '/payments', ['amount' => 50000])->assertCreated();

        $texts = $this->textsTo($owner->phone_number);
        $this->assertNotEmpty($texts);
        foreach ($texts as $text) {
            $this->assertNull($text['sender'], 'a payment confirmation is from the platform');
        }
    }

    // ---------------------------------------------------------------------- try a name

    public function test_a_test_text_shows_whether_the_provider_accepts_a_name(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'pending']);
        $super = $this->superAdmin('0617919104');
        $id = $this->business($owner)->id;

        $this->as($super, 'POST', "/api/admin/sms-senders/{$id}/test", ['phone' => '0755111222'])
            ->assertOk()
            ->assertJsonPath('data.outcome', 'accepted')
            ->assertJsonPath('data.sender_id', 'MAMAASHA')
            ->assertJsonPath('data.platform_sender', 'PLATFORM');
        $texts = $this->textsTo('0755111222');
        $this->assertCount(1, $texts);
        $this->assertSame('MAMAASHA', $texts[0]['sender'], 'a name can be tried before it is approved');

        // It goes to the super admin's own phone when none is given.
        $this->as($super, 'POST', "/api/admin/sms-senders/{$id}/test")->assertOk();
        $this->assertCount(1, $this->textsTo('0617919104'));
    }

    public function test_a_test_with_a_name_the_provider_does_not_know_is_refused_and_not_resent_under_another_name(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'pending']);
        $this->sms->refuseSenders('MAMAASHA');

        $this->as($this->superAdmin(), 'POST', '/api/admin/sms-senders/' . $this->business($owner)->id . '/test')
            ->assertOk()
            ->assertJsonPath('data.outcome', 'refused');

        $this->assertCount(1, $this->sms->attempts, 'a test must show the truth, not quietly use the platform name');
        $this->assertSame([], $this->sms->sent);
    }

    public function test_a_test_says_so_when_no_real_provider_is_on_and_when_there_is_nothing_to_try(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'pending']);
        $bare = $this->owner('Baba Homes');
        $super = $this->superAdmin();

        $this->sms->delivering = false;
        $this->as($super, 'POST', '/api/admin/sms-senders/' . $this->business($owner)->id . '/test')
            ->assertOk()->assertJsonPath('data.outcome', 'not_delivering');
        $this->assertSame([], $this->sms->sent);

        $this->as($super, 'POST', '/api/admin/sms-senders/' . $this->business($bare)->id . '/test')->assertStatus(422);
        $this->as($super, 'POST', '/api/admin/sms-senders/' . $this->business($owner)->id . '/test', ['sender_id' => 'BAD NAME'])->assertStatus(422);

        $noPhone = $this->superAdmin(null);
        $this->as($noPhone, 'POST', '/api/admin/sms-senders/' . $this->business($owner)->id . '/test')->assertStatus(422);
    }

    public function test_an_accepted_test_clears_the_flag_on_a_name_that_had_stopped_working(): void
    {
        $owner = $this->owner('Mama Asha Store', ['sms_sender_id' => 'MAMAASHA', 'sms_sender_status' => 'approved', 'sms_last_error' => 'refused']);

        $this->as($this->superAdmin(), 'POST', '/api/admin/sms-senders/' . $this->business($owner)->id . '/test')
            ->assertOk()->assertJsonPath('data.outcome', 'accepted');

        $this->assertFalse($this->business($owner)->smsNeedsAttention());
    }

    // --------------------------------------------------- a business with an SMS account of its own

    private function configureOwnAccount(User $super, User $owner, array $extra = [])
    {
        $response = $this->save($super, $owner, array_merge([
            'sender_id' => 'MAMAASHA', 'status' => 'approved', 'api_key' => 'KEY-ALPHA-1234', 'api_secret' => 'SECRET-ALPHA-9876',
        ], $extra));

        // The approval text to the owner went out while saving; the tests below look at what happens after.
        $this->sms->sent = [];
        $this->sms->attempts = [];

        return $response;
    }

    public function test_the_key_and_secret_are_kept_encrypted_and_never_returned(): void
    {
        $owner = $this->owner('Mama Asha Store');
        $super = $this->superAdmin();

        $saved = $this->configureOwnAccount($super, $owner)->assertOk()
            ->assertJsonPath('data.sms_sender.has_api_key', true)
            ->assertJsonPath('data.sms_sender.has_api_secret', true)
            ->assertJsonPath('data.sms_sender.api_key_hint', '****1234');

        $listed = $this->as($super, 'GET', '/api/admin/sms-senders');
        $ownerView = $this->as($owner, 'GET', '/api/business');
        $profile = $this->as($owner, 'GET', '/api/auth/user');
        foreach ([$saved, $listed, $ownerView, $profile] as $response) {
            $body = $response->getContent();
            $this->assertStringNotContainsString('KEY-ALPHA-1234', $body);
            $this->assertStringNotContainsString('SECRET-ALPHA-9876', $body);
        }

        $raw = DB::table('businesses')->where('id', $this->business($owner)->id)->first();
        $this->assertNotSame('KEY-ALPHA-1234', $raw->sms_api_key, 'stored encrypted');
        $this->assertStringNotContainsString('KEY-ALPHA', (string) $raw->sms_api_key);
        $this->assertStringNotContainsString('SECRET-ALPHA', (string) $raw->sms_api_secret);

        $business = $this->business($owner);
        $this->assertSame(['api_key' => 'KEY-ALPHA-1234', 'api_secret' => 'SECRET-ALPHA-9876'], $business->smsCredentials());
        $this->assertStringNotContainsString('KEY-ALPHA', $business->toJson(), 'whatever serialises the model');

        $audit = \App\Support\Tenancy\TenantContext::withoutScope(fn () => DB::table('inventory_audit_log')->where('action', 'sms_sender_changed')->get())->map(fn ($r) => json_encode($r))->implode(' ');
        $this->assertStringNotContainsString('KEY-ALPHA', $audit, 'not in the permanent log either');
        $this->assertNotSame('', $audit, 'the change is in the log');
        $this->assertStringContainsString('own SMS account key changed', $audit);
    }

    public function test_a_business_with_its_own_account_texts_through_it(): void
    {
        [$landlord, $tenant] = $this->landlordWithOverdueTenant('Mama Rent', [], '0766000111');
        $this->configureOwnAccount($this->superAdmin(), $landlord);

        app(RentalService::class)->processOverdueBills();

        $texts = $this->textsTo($tenant->phone_number);
        $this->assertCount(1, $texts);
        $this->assertSame('MAMAASHA', $texts[0]['sender']);
        $this->assertSame(['api_key' => 'KEY-ALPHA-1234', 'api_secret' => 'SECRET-ALPHA-9876'], $texts[0]['credentials']);
    }

    public function test_other_businesses_and_platform_texts_never_use_that_account(): void
    {
        [$a] = $this->landlordWithOverdueTenant('Mama Rent', [], '0766000111');
        [, $tPlain] = $this->landlordWithOverdueTenant('Plain Co', [], '0766000222');
        [, $tNameOnly] = $this->landlordWithOverdueTenant('Baba Homes', ['sms_sender_id' => 'BABAHOMES', 'sms_sender_status' => 'approved'], '0766000333');
        $super = $this->superAdmin();
        $this->configureOwnAccount($super, $a);

        app(RentalService::class)->processOverdueBills();
        $this->as($super, 'POST', '/api/admin/businesses/' . $this->business($a)->id . '/payments', ['amount' => 1000])->assertCreated();

        $this->assertNull($this->textsTo($tPlain->phone_number)[0]['credentials']);
        $this->assertNull($this->textsTo($tNameOnly->phone_number)[0]['credentials'], 'a name without a key uses the platform account');
        foreach ($this->sms->sent as $text) {
            if ($text['sender'] === null) {
                $this->assertNull($text['credentials'], 'a platform text such as a payment confirmation');
            }
        }
    }

    public function test_a_key_without_a_secret_uses_the_platform_secret(): void
    {
        config(['sms.enabled' => true, 'sms.kilakona.api_url' => 'https://sms.example.test/send', 'sms.kilakona.api_key' => 'platform-key', 'sms.kilakona.secret_key' => 'platform-secret']);
        Http::fake(['sms.example.test/*' => Http::response(['success' => true], 200)]);

        (new KilakonaSmsGateway())->send('0743519100', 'Habari', false, 'MAMAASHA', ['api_key' => 'KEY-ALPHA-1234', 'api_secret' => null]);
        (new KilakonaSmsGateway())->send('0743519100', 'Habari', false, 'MAMAASHA', ['api_key' => 'KEY-ALPHA-1234', 'api_secret' => 'SECRET-ALPHA-9876']);
        (new KilakonaSmsGateway())->send('0743519100', 'Habari');

        $seen = [];
        Http::assertSent(function (HttpRequest $request) use (&$seen) {
            $seen[] = [$request->header('api-key')[0], $request->header('api_secret')[0], $request['senderId']];

            return true;
        });
        $this->assertSame([
            ['KEY-ALPHA-1234', 'platform-secret', 'MAMAASHA'],
            ['KEY-ALPHA-1234', 'SECRET-ALPHA-9876', 'MAMAASHA'],
            ['platform-key', 'platform-secret', 'PLATFORM'],
        ], $seen);
    }

    public function test_a_wrong_key_does_not_spend_the_platform_credit_by_default_but_is_flagged(): void
    {
        [$landlord, $tenant] = $this->landlordWithOverdueTenant('Mama Rent', [], '0766000111');
        $this->configureOwnAccount($this->superAdmin(), $landlord)->assertJsonPath('data.sms_sender.fallback_platform', false);
        $this->sms->rejectKeys('KEY-ALPHA-1234');

        app(RentalService::class)->processOverdueBills();

        $this->assertCount(1, $this->sms->attempts, 'only the business own account was tried');
        $this->assertSame([], $this->textsTo($tenant->phone_number), 'the platform account was not used');
        $business = $this->business($landlord);
        $this->assertSame(0, $business->sms_sent_count);
        $this->assertStringContainsString('NOT sent', (string) $business->sms_last_error);
        $this->assertTrue($business->smsNeedsAttention());
    }

    public function test_when_allowed_a_refused_account_falls_back_to_the_platform(): void
    {
        [$landlord, $tenant] = $this->landlordWithOverdueTenant('Mama Rent', [], '0766000111');
        $this->configureOwnAccount($this->superAdmin(), $landlord, ['fallback_platform' => true])->assertJsonPath('data.sms_sender.fallback_platform', true);
        $this->sms->rejectKeys('KEY-ALPHA-1234');

        app(RentalService::class)->processOverdueBills();

        $texts = $this->textsTo($tenant->phone_number);
        $this->assertCount(1, $texts);
        $this->assertNull($texts[0]['sender']);
        $this->assertNull($texts[0]['credentials']);
        $business = $this->business($landlord);
        $this->assertSame(1, $business->sms_fallback_count);
        $this->assertStringContainsString('API key', (string) $business->sms_last_error);
    }

    public function test_the_key_can_be_replaced_removed_and_goes_with_a_cleared_name(): void
    {
        $owner = $this->owner('Mama Asha Store');
        $super = $this->superAdmin();
        $this->configureOwnAccount($super, $owner)->assertOk();

        // another key replaces it without touching the choice about falling back
        $this->save($super, $owner, ['api_key' => 'KEY-NEW-5555'])->assertOk()
            ->assertJsonPath('data.sms_sender.api_key_hint', '****5555')
            ->assertJsonPath('data.sms_sender.fallback_platform', false);
        $this->assertSame('SECRET-ALPHA-9876', $this->business($owner)->smsCredentials()['api_secret'], 'the secret stays unless a new one is given');

        // saving other things leaves the key alone
        $this->save($super, $owner, ['display_name' => 'Mama Asha'])->assertOk()->assertJsonPath('data.sms_sender.has_api_key', true);

        $this->save($super, $owner, ['clear_credentials' => true])->assertOk()
            ->assertJsonPath('data.sms_sender.has_api_key', false)
            ->assertJsonPath('data.sms_sender.has_api_secret', false)
            ->assertJsonPath('data.sms_sender.api_key_hint', null)
            ->assertJsonPath('data.sms_sender.sender_id', 'MAMAASHA');
        $this->assertNull($this->business($owner)->smsCredentials());

        $this->save($super, $owner, ['api_key' => 'KEY-AGAIN-1111'])->assertOk();
        $this->save($super, $owner, ['sender_id' => ''])->assertOk()->assertJsonPath('data.sms_sender.has_api_key', false);
        $raw = DB::table('businesses')->where('id', $this->business($owner)->id)->first();
        $this->assertNull($raw->sms_api_key, 'no forgotten secret behind a cleared name');
        $this->assertTrue((bool) $raw->sms_fallback_platform);
    }

    public function test_a_secret_alone_is_not_enough(): void
    {
        $owner = $this->owner('Mama Asha Store');

        $this->save($this->superAdmin(), $owner, ['sender_id' => 'MAMAASHA', 'api_secret' => 'SECRET-ONLY'])->assertStatus(422);
        $this->assertNull($this->business($owner)->smsCredentials());
    }

    public function test_the_test_text_uses_the_key_just_typed_or_the_saved_one(): void
    {
        $owner = $this->owner('Mama Asha Store');
        $super = $this->superAdmin();
        $id = $this->business($owner)->id;
        $this->configureOwnAccount($super, $owner)->assertOk();

        // what is typed on the page is tried first, before it is saved
        $this->as($super, 'POST', "/api/admin/sms-senders/{$id}/test", ['api_key' => 'KEY-TYPED-0001', 'api_secret' => 'SECRET-TYPED'])
            ->assertOk()->assertJsonPath('data.outcome', 'accepted')->assertJsonPath('data.own_account', true);
        $this->assertSame(['api_key' => 'KEY-TYPED-0001', 'api_secret' => 'SECRET-TYPED'], $this->sms->attempts[0]['credentials']);

        // else the saved one
        $this->as($super, 'POST', "/api/admin/sms-senders/{$id}/test")->assertOk();
        $this->assertSame('KEY-ALPHA-1234', $this->sms->attempts[1]['credentials']['api_key']);

        // a key the provider rejects shows as refused, and no other account is quietly used
        $this->sms->rejectKeys('KEY-TYPED-0001');
        $before = count($this->sms->attempts);
        $this->as($super, 'POST', "/api/admin/sms-senders/{$id}/test", ['api_key' => 'KEY-TYPED-0001'])->assertOk()->assertJsonPath('data.outcome', 'refused');
        $this->assertCount($before + 1, $this->sms->attempts);
    }
}
