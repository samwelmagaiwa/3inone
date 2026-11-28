<?php

namespace Tests\Feature;

use App\Models\Business;
use App\Models\User;
use App\Support\Ai\AssistantTools;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * The AI assistant in Groups (Vikundi): it answers from the group's own data, each person gets only the tools their group rights open (the
 * same rights as the screens), "ME" leaves only one's own account, and another group's members are never read.
 */
class AssistantGroupsTest extends TestCase
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
            ['asha', 'Asha Juma', '0713000001', null], ['baraka', 'Baraka Mollel', '0713000002', null]] as [$key, $name, $phone, $office]) {
            $id = $this->vikundi($this->owner, 'POST', '/members', ['full_name' => $name, 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office !== null) {
                $this->vikundi($this->owner, 'PUT', "/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->vikundi($this->owner, 'POST', "/members/{$id}/sign-in")->assertCreated();
            $this->ids[$key] = $id;
            $this->people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
        }
        // October's contribution was due on the 5th and nobody paid it; Asha saved 50,000 (verified).
        $type = $this->vikundi($this->owner, 'POST', '/contribution-types', ['name' => 'JAMII', 'amount' => 20000, 'frequency' => 'monthly', 'due_day' => 5, 'starts_on' => '2026-01-01'])
            ->assertCreated()->json('data.type.id');
        $this->vikundi($this->people['treasurer'], 'POST', "/contribution-types/{$type}/raise", ['month' => '2026-10'])->assertOk();
        $tx = $this->vikundi($this->people['treasurer'], 'POST', '/transactions', ['member_id' => $this->ids['asha'], 'category' => 'savings', 'amount' => 50000, 'method' => 'cash'])
            ->assertCreated()->json('data.transaction.id');
        $this->vikundi($this->people['assistant'], 'POST', "/transactions/{$tx}/verify")->assertOk();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function vikundi(User $as, string $method, string $uri, array $body = [])
    {
        return $this->as($as)->json($method, '/api/groups' . $uri, $body);
    }

    private function as(User $who, bool $me = false): static
    {
        $token = $who->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();
        GroupAccess::viewAsMember(false);

        return $this->withHeader('Authorization', "Bearer {$token}")->withHeader('Accept', 'application/json')->withHeaders($me ? ['X-Group-View' => 'member'] : []);
    }

    private function topics(User $who, bool $me = false): array
    {
        return array_values(array_filter($this->as($who, $me)->getJson('/api/assistant')->assertOk()->json('data.topics'), fn ($t) => str_starts_with($t, 'groups_')));
    }

    private function gemini(string $tool, array $args = []): void
    {
        config(['services.gemini.key' => 'g-test', 'services.gemini.model' => 'gemini-2.5-flash']);
        Http::fake(['generativelanguage.googleapis.com/*' => Http::sequence()
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['functionCall' => ['name' => $tool, 'args' => $args]]]]]]], 200)
            ->push(['candidates' => [['content' => ['role' => 'model', 'parts' => [['text' => 'Done.']]]]]], 200)]);
    }

    public function test_each_person_gets_the_group_tools_their_rights_open(): void
    {
        $this->assertEqualsCanonicalizing(['groups_overview', 'groups_who_owe', 'groups_member', 'groups_loans', 'groups_payments'], $this->topics($this->owner), 'the owner runs the group but is not a member');
        $this->assertContains('groups_my_account', $this->topics($this->people['treasurer']));
        $this->assertContains('groups_who_owe', $this->topics($this->people['treasurer']));
        $this->assertSame(['groups_my_account'], $this->topics($this->people['asha']), 'a plain member: only their own account');
        $this->assertSame(['groups_my_account'], $this->topics($this->people['treasurer'], true), 'ME: the treasurer looking as a member');

        $shop = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0719000001']), 'inventory');
        $this->assertSame([], $this->topics($shop), 'a shop has no group tools');
    }

    public function test_who_owes_contributions_comes_from_this_group_only(): void
    {
        // Another group, with a member who owes far more.
        $other = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0711000888']), 'groups');
        $this->vikundi($other, 'POST', '/members', ['full_name' => 'Other Group Member', 'phone' => '0714000001', 'existing' => true])->assertCreated();
        $type = $this->vikundi($other, 'POST', '/contribution-types', ['name' => 'KUBWA', 'amount' => 900000, 'frequency' => 'monthly', 'due_day' => 5, 'starts_on' => '2026-01-01'])->json('data.type.id');
        $this->vikundi($other, 'POST', "/contribution-types/{$type}/raise", ['month' => '2026-10'])->assertOk();

        $this->gemini('groups_who_owe');
        $r = $this->as($this->people['treasurer'])->postJson('/api/assistant', ['question' => 'Nani anadaiwa michango?'])->assertOk();
        $rows = $r->json('data.cards.0.rows');
        $names = array_column($rows, 'title');
        $this->assertContains('Asha Juma', $names);
        $this->assertContains('Baraka Mollel', $names);
        $this->assertNotContains('Other Group Member', $names);
        $this->assertSame('TSh 20,000', collect($rows)->firstWhere('title', 'Asha Juma')['value']);
        $sent = json_encode(Http::recorded()->map(fn ($p) => $p[0]->data())->values()->all()[1]['contents']);
        $this->assertStringNotContainsString('Other Group Member', $sent);
    }

    public function test_a_member_reads_their_own_account_and_cannot_reach_the_leaders_tools(): void
    {
        $this->gemini('groups_my_account');
        $card = $this->as($this->people['asha'])->postJson('/api/assistant', ['question' => 'Nina akiba kiasi gani?'])->assertOk()->json('data.cards.0');
        $this->assertSame('Asha Juma', $card['title']);
        $this->assertSame('TSh 50,000', $card['rows'][0]['value']);
        $this->assertSame('TSh 20,000', $card['rows'][2]['value']);

        // A tool their rights do not open answers with "not allowed", never with data.
        $this->as($this->people['asha']);
        $denied = AssistantTools::run('groups_who_owe', [], $this->people['asha']);
        $this->assertArrayHasKey('error', $denied['data']);
        $this->assertNull($denied['card']);
    }

    public function test_the_overview_member_and_payments_tools_answer_with_the_groups_figures(): void
    {
        $this->as($this->owner);
        $o = AssistantTools::run('groups_overview', [], $this->owner)['data'];
        $this->assertSame(4, $o['members']['active']);
        $this->assertEquals(50000, $o['money']['cash_on_record']);
        $this->assertEquals(50000, $o['money']['savings']);
        $this->assertArrayNotHasKey('trend', $o['money']);

        $m = AssistantTools::run('groups_member', ['name' => 'asha'], $this->owner)['data']['members'][0];
        $this->assertSame('Asha Juma', $m['name']);
        $this->assertEquals(50000, $m['balances']['savings']);
        $this->assertEquals(20000, $m['owes_contributions']);

        $p = AssistantTools::run('groups_payments', ['days' => 31], $this->owner)['data'];
        $this->assertSame('Asha Juma', $p['latest'][0]['who']);
        $this->assertEquals(50000, collect($p['by_kind'])->firstWhere('kind', 'savings')['in']);

        $this->assertSame([], AssistantTools::run('groups_loans', [], $this->owner)['data']['loans']);
    }
}
