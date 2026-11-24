<?php

namespace Tests\Feature;

use App\Models\User;
use App\Support\Groups\GroupAccess;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Routing\Middleware\ThrottleRequests;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/** Groups (Vikundi): the leaders' dashboard -- one call, figures that add up, money only for whoever sees the money. */
class GroupsDashboardTest extends TestCase
{
    use RefreshDatabase;

    private function api(User $as, string $uri)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->getJson('/api/groups' . $uri);
    }

    private function send(User $as, string $uri, array $body)
    {
        $token = $as->createToken('test')->plainTextToken;
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        GroupAccess::forget();

        return $this->withHeader('Authorization', "Bearer {$token}")->postJson('/api/groups' . $uri, $body);
    }

    public function test_the_dashboard_adds_up_and_shows_money_only_to_those_who_see_it(): void
    {
        $this->withoutMiddleware(ThrottleRequests::class);
        Carbon::setTestNow(Carbon::parse('2026-11-10 08:00:00'));
        $owner = $this->givenServices(User::factory()->create(['role' => 'admin', 'is_active' => true, 'phone_number' => '0711000999']), 'groups');
        $people = [];
        foreach ([['secretary', '0712000004', 'katibu'], ['asha', '0713000001', null]] as [$key, $phone, $office]) {
            $id = $this->send($owner, '/members', ['full_name' => ucfirst($key) . ' M', 'phone' => $phone, 'existing' => true])->assertCreated()->json('data.member.id');
            if ($office) {
                $token = $owner->createToken('t')->plainTextToken;
                $this->app['auth']->forgetGuards();
                $this->withHeader('Authorization', "Bearer {$token}")->putJson("/api/groups/members/{$id}/office", ['office' => $office])->assertOk();
            }
            $this->send($owner, "/members/{$id}/sign-in", [])->assertCreated();
            $people[$key] = User::query()->find(DB::table('group_members')->where('id', $id)->value('user_id'));
            $people[$key . '_id'] = $id;
        }
        // Verified money this month and last month, and one still waiting.
        foreach ([[100000, 'savings', 'in', '2026-11-05'], [20000, 'shares', 'in', '2026-10-15'], [15000, 'expense', 'out', '2026-11-06']] as [$amount, $cat, $dir, $day]) {
            DB::table('group_transactions')->insert([
                'owner_id' => $owner->id, 'reference' => 'T' . $amount, 'member_id' => $cat === 'expense' ? null : $people['asha_id'], 'category' => $cat, 'direction' => $dir,
                'amount' => $amount, 'method' => 'cash', 'paid_on' => $day, 'status' => 'verified', 'verified_at' => $day . ' 10:00:00', 'created_at' => now(), 'updated_at' => now(),
            ]);
        }
        DB::table('group_transactions')->insert([
            'owner_id' => $owner->id, 'reference' => 'TP', 'member_id' => $people['asha_id'], 'category' => 'savings', 'direction' => 'in',
            'amount' => 999, 'method' => 'cash', 'paid_on' => '2026-11-07', 'status' => 'pending', 'created_at' => now(), 'updated_at' => now(),
        ]);

        $d = $this->api($owner, '/dashboard')->assertOk()->json('data');
        $this->assertSame(2, $d['members']['active']);
        $this->assertEquals(105000, $d['money']['cash_on_record']);
        $this->assertEquals(100000, $d['money']['month_in']);
        $this->assertEquals(15000, $d['money']['month_out']);
        $this->assertEquals(100000, $d['money']['savings']);
        $this->assertSame(1, $d['money']['pending_count']);
        $this->assertCount(12, $d['money']['trend']);
        $this->assertSame('2026-11', end($d['money']['trend'])['month']);
        $this->assertEquals(20000, collect($d['money']['trend'])->firstWhere('month', '2026-10')['in']);
        $this->assertEquals(15000, $d['money']['year']['expenses']);

        // The secretary sees members, not money; a plain member sees neither.
        $this->api($people['secretary'], '/dashboard')->assertOk()->assertJsonPath('data.money', null)->assertJsonPath('data.members.active', 2);
        $this->api($people['asha'], '/dashboard')->assertForbidden();
        Carbon::setTestNow();
    }
}
