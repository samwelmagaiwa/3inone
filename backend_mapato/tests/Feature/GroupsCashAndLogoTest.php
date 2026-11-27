<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

/**
 * Groups (Vikundi): money never goes out that the books do not show the group holding (an opening balance records cash held before),
 * dividends are not cash, the overdue text states everything overdue, and the group can carry a logo of its own.
 */
class GroupsCashAndLogoTest extends TestCase
{
    use RefreshDatabase;

    private User $owner;

    /** @var array<string, User> */
    private array $people = [];

    /** @var array<string, int> */
    private array $ids = [];

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutMiddleware(ThrottleRequests::class);
        Carbon::setTestNow(Carbon::parse('2026-11-10 08:00:00'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG']);
        foreach ([['treasurer', 'Mweka Hazina', '0712000002', 'mweka_hazina'], ['assistant', 'Msaidizi', '0712000003', 'mweka_hazina_msaidizi'],
            ['asha', 'Asha Juma', '0713000001', null]] as [$key, $name, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => $name, 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->api($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->api($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function api(User $as, string $method, string $uri, array $body = [])
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->json($method, '/api/groups' . $uri, $body);
    }

    /** A fresh sign-in for a call outside /groups (the app keeps the last caller otherwise). */
    private function signedInAs(User $as): static
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('Accept', 'application/json');
    }

    /** The treasurer records, the assistant verifies. */
    private function money(array $body): int
    {
        $id = $this->api($this->people['treasurer'], 'POST', '/transactions', $body + ['method' => 'cash'])->assertCreated()->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$id}/verify")->assertOk();

        return (int) $id;
    }

    public function test_money_cannot_go_out_that_the_books_do_not_show(): void
    {
        $expense = ['category' => 'expense', 'payee' => 'Stationery shop', 'amount' => 30000, 'method' => 'cash'];
        $this->api($this->people['treasurer'], 'POST', '/transactions', $expense)->assertStatus(422)->assertJsonPath('code', 'not_enough_cash');

        // The cash the group held before it kept its books here: in, no member, verified by someone else like any money.
        $this->api($this->people['treasurer'], 'POST', '/transactions', ['category' => 'opening_balance', 'member_id' => $this->ids['asha'], 'amount' => 50000, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'opening_balance_group_only');
        $this->api($this->people['treasurer'], 'POST', '/transactions', ['category' => 'opening_balance', 'direction' => 'out', 'amount' => 50000, 'method' => 'cash'])
            ->assertStatus(422)->assertJsonPath('code', 'opening_balance_group_only');
        $this->money(['category' => 'opening_balance', 'amount' => 50000]);
        $this->api($this->people['treasurer'], 'GET', '/transactions/summary')->assertJsonPath('data.cash_on_record', 50000);

        // 30,000 fits; while it waits, a second 30,000 does not (50,000 less 30,000 waiting).
        $first = $this->api($this->people['treasurer'], 'POST', '/transactions', $expense)->assertCreated()->json('data.transaction.id');
        $this->api($this->people['treasurer'], 'POST', '/transactions', $expense)->assertStatus(422)->assertJsonPath('code', 'not_enough_cash');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$first}/verify")->assertOk();
        $this->api($this->people['treasurer'], 'GET', '/transactions/summary')->assertJsonPath('data.cash_on_record', 20000);

        // A savings withdrawal is cash going out too.
        $this->money(['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 10000]);
        $out = $this->api($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'direction' => 'out', 'amount' => 10000, 'method' => 'cash'])
            ->assertCreated()->json('data.transaction.id');
        $this->api($this->people['assistant'], 'POST', "/transactions/{$out}/verify")->assertOk();
        $this->api($this->people['treasurer'], 'GET', '/transactions/summary')->assertJsonPath('data.cash_on_record', 20000);
    }

    public function test_a_payout_waiting_is_checked_again_against_the_cash_when_it_is_verified(): void
    {
        $this->money(['category' => 'opening_balance', 'amount' => 40000]);
        $expense = ['category' => 'expense', 'payee' => 'Hall', 'amount' => 30000, 'method' => 'cash'];
        $waiting = $this->api($this->people['treasurer'], 'POST', '/transactions', $expense)->assertCreated()->json('data.transaction.id');
        // The cash on record drops after it was sent (say an earlier deposit was reversed).
        DB::table('group_transactions')->insert([
            'owner_id' => $this->owner->id, 'reference' => 'TX-OUT', 'member_id' => null, 'payee' => 'Rent', 'category' => 'expense', 'direction' => 'out', 'amount' => 20000,
            'method' => 'cash', 'paid_on' => '2026-11-09', 'status' => 'verified', 'verified_at' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
        $this->api($this->people['assistant'], 'POST', "/transactions/{$waiting}/verify")->assertStatus(409)->assertJsonPath('code', 'not_enough_cash');
    }

    public function test_dividends_are_credited_to_savings_but_are_not_cash(): void
    {
        $this->money(['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 100000]);
        DB::table('group_transactions')->insert([
            'owner_id' => $this->owner->id, 'reference' => 'TX-DIV', 'member_id' => $this->ids['asha'], 'category' => 'dividend', 'direction' => 'in', 'amount' => 2000,
            'method' => 'cash', 'paid_on' => '2026-11-09', 'status' => 'verified', 'verified_at' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
        $this->api($this->people['treasurer'], 'GET', '/transactions/summary')->assertJsonPath('data.cash_on_record', 100000);
        $d = $this->api($this->owner, 'GET', '/dashboard')->assertOk();
        $this->assertEquals(100000, $d->json('data.money.cash_on_record'));
        $this->assertEquals(102000, $d->json('data.money.savings'), 'the member still holds the dividend in savings');
        $this->assertEquals(100000, $d->json('data.money.month_in'), 'a dividend is not money that came in');
    }

    public function test_the_overdue_text_states_everything_that_is_overdue(): void
    {
        // Settings count from the day they are changed, so the group switches reminders on at the start of the month.
        Carbon::setTestNow(Carbon::parse('2026-11-01 08:00:00'));
        foreach ([['JAMII', 10000, 5], ['ADA', 5000, 3]] as [$name, $amount, $day]) {
            $type = $this->api($this->owner, 'POST', '/contribution-types', ['name' => $name, 'amount' => $amount, 'frequency' => 'monthly', 'due_day' => $day, 'starts_on' => '2026-01-01'])
                ->assertCreated()->json('data.type.id');
            $this->api($this->people['treasurer'], 'POST', "/contribution-types/{$type}/raise", ['month' => '2026-11'])->assertOk();
        }
        $this->api($this->owner, 'PUT', '/settings', ['values' => ['sms_reminders' => 'on', 'sms_show_amounts' => 'on'], 'reason' => 'Meeting decided'])->assertOk();

        // The 6th: JAMII (due the 5th) is one day late -- its reminder day; ADA (due the 3rd) is three days late, not its day.
        Carbon::setTestNow(Carbon::parse('2026-11-06 08:00:00'));
        Artisan::call('groups:daily');
        $asha = collect($this->sms->sent)->first(fn ($t) => str_ends_with((string) $t['to'], '713000001'));
        $this->assertNotNull($asha);
        $this->assertStringContainsString('15,000', $asha['message'], 'JAMII and ADA together');

        // The 7th: no contribution reaches its weekly day, so nobody is texted about overdue money.
        $before = count($this->sms->sent);
        Carbon::setTestNow(Carbon::parse('2026-11-07 08:00:00'));
        Artisan::call('groups:daily');
        $this->assertCount($before, $this->sms->sent);
    }

    public function test_the_owner_gives_the_group_a_logo_of_its_own_that_falls_back_to_the_business_logo(): void
    {
        Storage::fake('public');
        $png = tempnam(sys_get_temp_dir(), 'logo');
        file_put_contents($png, base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
        $upload = fn (?string $service, ?User $as = null) => $this->signedInAs($as ?? $this->owner)->post('/api/business/logo', array_filter(['service' => $service, 'logo' => new UploadedFile($png, 'logo.png', 'image/png', null, true)]), ['Accept' => 'application/json']);

        $this->api($this->people['asha'], 'GET', '/me')->assertJsonPath('data.group.logo_url', null);

        $upload(null)->assertOk();
        $business = $this->api($this->people['asha'], 'GET', '/me')->json('data.group.logo_url');
        $this->assertNotNull($business, 'no group logo yet: the business logo');

        $upload('groups')->assertOk()->assertJsonStructure(['data' => ['service_logos' => ['groups']]]);
        $group = $this->api($this->people['asha'], 'GET', '/me')->json('data.group.logo_url');
        $this->assertNotSame($business, $group);
        $this->assertStringContainsString('_groups_', $group);

        // A service the business does not have is refused; only the owner changes logos.
        $upload('rental')->assertStatus(422);
        $upload('groups', $this->people['asha'])->assertForbidden();

        // Removing the group's own logo goes back to the business logo.
        $this->signedInAs($this->owner)->deleteJson('/api/business/logo?service=groups')->assertOk();
        $this->assertSame($business, $this->api($this->people['asha'], 'GET', '/me')->json('data.group.logo_url'));
    }
}
