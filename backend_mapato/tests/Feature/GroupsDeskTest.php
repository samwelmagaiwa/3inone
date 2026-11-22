<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Groups\GroupAccess;
use App\Support\Groups\GroupOffices;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * Groups (Vikundi): each office's desk: the figures its office oversees, and what waits for a person never includes what they may not decide.
 */
class GroupsDeskTest extends TestCase
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
        Carbon::setTestNow(Carbon::parse('2026-05-01 08:00:00'));
        $this->owner = $this->givenServices(User::factory()->create(['name' => 'MEG Owner', 'role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        Business::forOwnerId($this->owner->id)->update(['name' => 'MEG']);
        foreach ([['chair', '0712000001', 'mwenyekiti'], ['treasurer', '0712000002', 'mweka_hazina'], ['secretary', '0712000004', 'katibu'], ['projects', '0712000005', 'mwenyekiti_miradi'], ['committee', '0712000006', 'kamati_miradi'],
            ['asha', '0713000001', null], ['juma', '0713000002', null]] as [$key, $phone, $office]) {
            $id = $this->api($this->owner, 'POST', '/members', ['full_name' => ucfirst($key) . ' Member', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
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

    public function test_the_projects_office_sees_projects_and_loans_figures_without_the_money(): void
    {
        $this->api($this->people['asha'], 'POST', '/projects', ['title' => 'Layers', 'budget' => 500000])->assertCreated();
        $d = $this->api($this->people['committee'], 'GET', '/dashboard')->assertOk();
        $d->assertJsonPath('data.money', null);
        $d->assertJsonPath('data.desk.projects.proposed', 1);
        $this->assertNotNull($d->json('data.desk.loans'));
        $this->assertNull($d->json('data.desk.meetings'));
    }

    public function test_the_secretary_sees_the_meeting_figures_and_not_the_projects_money(): void
    {
        $d = $this->api($this->people['secretary'], 'GET', '/dashboard')->assertOk();
        $this->assertNotNull($d->json('data.desk.meetings'));
        $d->assertJsonPath('data.money', null);
    }

    public function test_an_ordinary_member_has_no_officers_dashboard(): void
    {
        $this->api($this->people['asha'], 'GET', '/dashboard')->assertForbidden();
        $this->api($this->people['asha'], 'GET', '/me')->assertOk()->assertJsonPath('data.waiting', []);
    }

    public function test_what_waits_never_includes_the_persons_own_request(): void
    {
        $this->api($this->people['treasurer'], 'POST', '/expenses', ['purpose' => 'Stationery', 'category' => 'office', 'payee' => 'Shop', 'amount' => 20000])->assertCreated();
        $this->api($this->people['secretary'], 'POST', '/expenses', ['purpose' => 'Chairs', 'category' => 'office', 'payee' => 'Shop', 'amount' => 30000])->assertCreated();
        // The treasurer may decide the secretary's request but not their own; the chair may decide both.
        $this->api($this->people['treasurer'], 'GET', '/me')->assertJsonPath('data.waiting.expenses_to_approve', 1);
        $this->api($this->people['chair'], 'GET', '/me')->assertJsonPath('data.waiting.expenses_to_approve', 2);

        $this->api($this->people['committee'], 'POST', '/projects', ['title' => 'Mine', 'budget' => 1000])->assertCreated();
        $this->api($this->people['committee'], 'GET', '/me')->assertJsonPath('data.waiting.projects_to_review', 0);
        $this->api($this->people['projects'], 'GET', '/me')->assertJsonPath('data.waiting.projects_to_review', 1);
    }
}
